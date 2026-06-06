import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { getUser, unauthorized } from "../_shared/auth.ts";
import { handleCors, jsonResponse, errorResponse, corsHeaders } from "../_shared/cors.ts";
import { buildFinancialContext, callAI } from "../_shared/ai-brain.ts";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const user = await getUser(req);
  if (!user) return unauthorized();

  const url = new URL(req.url);
  const pathParts = url.pathname.replace(/^\/ai-chat\/?/, "").split("/").filter(Boolean);
  const method = req.method;

  // ── POST /ai-chat/sessions — create new chat session ───────────────────
  if (method === "POST" && pathParts[0] === "sessions") {
    const { data, error } = await supabaseAdmin.from("chat_sessions").insert({
      user_id: user.id,
      title: "New conversation",
    }).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data, 201);
  }

  // ── GET /ai-chat/sessions — list user's chat sessions ──────────────────
  if (method === "GET" && pathParts[0] === "sessions" && pathParts.length === 1) {
    const { data, error } = await supabaseAdmin.from("chat_sessions")
      .select("*")
      .eq("user_id", user.id)
      .eq("is_active", true)
      .order("last_message_at", { ascending: false })
      .limit(20);
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // ── DELETE /ai-chat/sessions/:id — soft-delete session ─────────────────
  if (method === "DELETE" && pathParts[0] === "sessions" && pathParts[1]) {
    const { error } = await supabaseAdmin.from("chat_sessions")
      .update({ is_active: false })
      .eq("id", pathParts[1])
      .eq("user_id", user.id);
    if (error) return errorResponse(error.message);
    return jsonResponse({ ok: true });
  }

  // ── GET /ai-chat/history?session_id=xxx — load chat history ────────────
  if (method === "GET" && pathParts[0] === "history") {
    const sessionId = url.searchParams.get("session_id");
    if (!sessionId) return errorResponse("session_id required", 400);

    const { data, error } = await supabaseAdmin.from("chat_messages")
      .select("id, role, content, created_at")
      .eq("session_id", sessionId)
      .eq("user_id", user.id)
      .order("created_at", { ascending: true })
      .limit(100);
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // ── POST /ai-chat/message — send message and get AI response ───────────
  if (method === "POST" && pathParts[0] === "message") {
    const body = await req.json();
    const { session_id, message } = body;

    if (!message?.trim()) return errorResponse("message required", 400);

    let sessionId = session_id;

    // Auto-create session if not provided
    if (!sessionId) {
      const { data: newSession, error: sessErr } = await supabaseAdmin
        .from("chat_sessions")
        .insert({ user_id: user.id, title: message.slice(0, 100) })
        .select("id")
        .single();
      if (sessErr) return errorResponse(sessErr.message);
      sessionId = newSession.id;
    }

    // Save user message
    await supabaseAdmin.from("chat_messages").insert({
      session_id: sessionId,
      user_id: user.id,
      role: "user",
      content: message,
    });

    // Load last 20 messages for context
    const { data: history } = await supabaseAdmin.from("chat_messages")
      .select("role, content")
      .eq("session_id", sessionId)
      .eq("user_id", user.id)
      .order("created_at", { ascending: true })
      .limit(20);

    // Build chat messages from history (OpenAI format)
    const chatMessages = (history ?? []).map((m: any) => ({
      role: m.role === "user" ? "user" as const : "assistant" as const,
      content: m.content as string,
    }));

    // Build financial context
    const financialContext = await buildFinancialContext(user.id);

    // Call AI via OpenRouter
    const aiResponse = await callAI(chatMessages, financialContext);

    // Save assistant response
    await supabaseAdmin.from("chat_messages").insert({
      session_id: sessionId,
      user_id: user.id,
      role: "assistant",
      content: aiResponse,
    });

    // Update session title (from first message) and last_message_at
    const updateData: any = { last_message_at: new Date().toISOString() };
    if (!session_id) {
      updateData.title = message.length > 60
        ? message.slice(0, 57) + "..."
        : message;
    }
    await supabaseAdmin.from("chat_sessions")
      .update(updateData)
      .eq("id", sessionId);

    return jsonResponse({
      session_id: sessionId,
      response: aiResponse,
    });
  }

  // ── POST /ai-chat/quick — one-shot question (no session) ──────────────
  if (method === "POST" && pathParts[0] === "quick") {
    const body = await req.json();
    const { message } = body;
    if (!message?.trim()) return errorResponse("message required", 400);

    const financialContext = await buildFinancialContext(user.id);
    const aiResponse = await callAI(
      [{ role: "user", content: message }],
      financialContext,
      { maxTokens: 500 }
    );

    return jsonResponse({ response: aiResponse });
  }

  return errorResponse("Not found", 404);
});

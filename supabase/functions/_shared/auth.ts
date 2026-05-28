import { supabaseAnon } from "./supabase-client.ts";

export interface AuthUser {
  id: string;
  phone?: string;
  email?: string;
}

export async function getUser(req: Request): Promise<AuthUser | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;

  const token = authHeader.split(" ")[1];
  const { data, error } = await supabaseAnon.auth.getUser(token);

  if (error || !data.user) return null;

  return {
    id: data.user.id,
    phone: data.user.phone,
    email: data.user.email,
  };
}

export function unauthorized(): Response {
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}

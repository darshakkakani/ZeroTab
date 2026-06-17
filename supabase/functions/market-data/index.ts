// Supabase Edge Function: market-data
//
// CORS-enabled HTTP proxy for Yahoo Finance and api.mfapi.in.
//
// Why this exists:
//   - Yahoo Finance (query1/query2.finance.yahoo.com) and api.mfapi.in do not
//     emit CORS headers, so browser/Flutter-web clients can't fetch them
//     directly.
//   - Yahoo also blocks the default Deno User-Agent, so we spoof a browser UA.
//
// Usage:
//   GET /functions/v1/market-data?url=<URL-encoded upstream URL>
//
// Pure stdlib — only depends on std/http/server.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/**
 * Hostnames we are willing to proxy. Anything else is rejected with 403.
 * P0: Yahoo v8/chart (query1 primary, query2 failover) + mfapi.in NAV history.
 * P1 (not yet enabled): www.nseindia.com, IPO Guru host.
 */
const ALLOWED_HOSTS: ReadonlySet<string> = new Set([
  "query1.finance.yahoo.com",
  "query2.finance.yahoo.com",
  "api.mfapi.in",
]);

/** Browser-ish UA so Yahoo doesn't 403 us. */
const BROWSER_UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

const BROWSER_ACCEPT =
  "application/json, text/plain, */*";

const BROWSER_ACCEPT_LANG = "en-US,en;q=0.9";

/**
 * Per-host upstream request header overrides.
 *
 * Yahoo (query1/query2): browser UA + JSON Accept is enough. v8/chart does
 * NOT require a Referer, and `^` in index symbols (e.g. `^GSPC` → `%5E GSPC`)
 * is already URL-encoded client-side; we forward `upstream.toString()` as-is
 * and the URL object does not double-encode an already-encoded path.
 *
 * mfapi.in: same generic headers work; left here so additions don't have to
 * touch the fetch site.
 *
 * Extension point for P1:
 *   - "www.nseindia.com" → add Referer + Chrome UA + cookie-warmer step
 *   - IPO Guru host       → add `X-API-KEY` from Deno.env.get("IPO_GURU_KEY")
 */
function headersForHost(host: string): Record<string, string> {
  const base: Record<string, string> = {
    "User-Agent": BROWSER_UA,
    "Accept": BROWSER_ACCEPT,
    "Accept-Language": BROWSER_ACCEPT_LANG,
  };

  switch (host) {
    case "query1.finance.yahoo.com":
    case "query2.finance.yahoo.com":
      // v8/chart works with the generic browser headers. Keep this branch
      // explicit so future Yahoo-only tweaks (e.g. Origin) land here.
      return base;

    case "api.mfapi.in":
      return base;

    // P1 hosts intentionally not added yet — see ALLOWED_HOSTS comment.
    default:
      return base;
  }
}

/** Base CORS headers attached to every response. */
const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Max-Age": "86400",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Build a JSON response with CORS headers. */
function jsonResponse(
  body: unknown,
  status: number,
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json; charset=utf-8",
      ...extra,
    },
  });
}

/**
 * Decide how long the browser/CDN may cache this response.
 *
 * - Intraday data (interval < 1d, or no interval param) -> 60 s.
 * - Daily/weekly/monthly data (interval=1d, 1wk, 1mo, 3mo) -> 3600 s.
 */
function cacheMaxAgeFor(upstream: URL): number {
  const interval = (upstream.searchParams.get("interval") ?? "").toLowerCase();
  // Anything that's a "day or longer" bucket gets the long cache.
  const dailyOrLonger = new Set(["1d", "5d", "1wk", "1mo", "3mo", "6mo", "1y"]);
  if (dailyOrLonger.has(interval)) return 3600;
  return 60;
}

/**
 * Parse and validate the `url` query parameter.
 *
 * Returns either a usable upstream URL or a Response describing the error.
 */
function parseUpstream(req: Request): URL | Response {
  const incoming = new URL(req.url);
  const raw = incoming.searchParams.get("url");
  if (!raw) {
    return jsonResponse(
      { error: "Missing required query parameter: url" },
      400,
    );
  }

  let upstream: URL;
  try {
    upstream = new URL(raw);
  } catch (_e) {
    return jsonResponse(
      { error: "Invalid url parameter: must be an absolute URL" },
      400,
    );
  }

  if (upstream.protocol !== "https:" && upstream.protocol !== "http:") {
    return jsonResponse(
      { error: "Invalid url parameter: only http/https are allowed" },
      400,
    );
  }

  if (!ALLOWED_HOSTS.has(upstream.hostname)) {
    return jsonResponse(
      {
        error: "Host not allowed",
        host: upstream.hostname,
        allowed: [...ALLOWED_HOSTS],
      },
      403,
    );
  }

  return upstream;
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

async function handler(req: Request): Promise<Response> {
  // Preflight.
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "GET") {
    return jsonResponse(
      { error: `Method ${req.method} not allowed. Use GET.` },
      405,
      { "Allow": "GET, OPTIONS" },
    );
  }

  const parsed = parseUpstream(req);
  if (parsed instanceof Response) return parsed;
  const upstream = parsed;

  const maxAge = cacheMaxAgeFor(upstream);

  // Fetch upstream with browser-ish headers, plus any per-host overrides.
  let upstreamRes: Response;
  try {
    upstreamRes = await fetch(upstream.toString(), {
      method: "GET",
      headers: headersForHost(upstream.hostname),
      // Edge Functions auto-follow redirects; that's what we want.
      redirect: "follow",
    });
  } catch (err) {
    return jsonResponse(
      {
        error: "Upstream fetch failed",
        detail: err instanceof Error ? err.message : String(err),
        upstream: upstream.toString(),
      },
      502,
    );
  }

  // Forward upstream body verbatim. We deliberately preserve the upstream
  // status code (e.g. 404 for a bad symbol) so the client can react.
  const contentType =
    upstreamRes.headers.get("content-type") ??
    "application/json; charset=utf-8";

  // Buffer the body — Edge Functions sometimes have trouble streaming a
  // ReadableStream that's already been consumed, and bodies here are small.
  let bodyBytes: ArrayBuffer;
  try {
    bodyBytes = await upstreamRes.arrayBuffer();
  } catch (err) {
    return jsonResponse(
      {
        error: "Failed to read upstream body",
        detail: err instanceof Error ? err.message : String(err),
      },
      502,
    );
  }

  return new Response(bodyBytes, {
    status: upstreamRes.status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": contentType,
      "Cache-Control": `public, max-age=${maxAge}`,
      "X-Proxy-Upstream": upstream.hostname,
    },
  });
}

serve(handler);

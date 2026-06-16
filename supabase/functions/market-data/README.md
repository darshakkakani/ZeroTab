# `market-data` Edge Function

A tiny Supabase Edge Function (Deno + TypeScript) that acts as a CORS-enabled
HTTP proxy in front of two upstream APIs:

- **Yahoo Finance** — `query1.finance.yahoo.com`, `query2.finance.yahoo.com`
- **mfapi.in** — `api.mfapi.in` (Indian mutual-fund NAV history)

## Why this exists

1. **CORS.** Yahoo Finance and `api.mfapi.in` do not send
   `Access-Control-Allow-Origin`, so a browser/Flutter-web client cannot call
   them directly. This proxy adds `Access-Control-Allow-Origin: *` and the
   matching preflight (`OPTIONS`) response.
2. **User-Agent gating.** Yahoo refuses requests that come in with the default
   Deno User-Agent. This function spoofs a real Chrome UA + `Accept` headers so
   Yahoo plays nicely.
3. **Caching.** The proxy sets `Cache-Control: public, max-age=60` for
   intraday data and `max-age=3600` for daily-or-longer intervals, so
   Supabase's edge CDN absorbs most of the load.

## How it works

```
client ──GET──▶ /functions/v1/market-data?url=<ENCODED_UPSTREAM_URL>
                          │
                          ▼
              host whitelist check
                          │
                          ▼
              fetch(upstream, { browser UA + Accept })
                          │
                          ▼
              forward status + body, attach CORS + Cache-Control
```

### Request

```
GET https://<project>.supabase.co/functions/v1/market-data
    ?url=<URL-encoded upstream URL>
```

### Response codes

| Status | When                                                          |
|-------:|---------------------------------------------------------------|
| 200    | Upstream returned 2xx — body is forwarded verbatim            |
| 4xx    | Upstream's own client error is forwarded as-is                |
| 400    | `url` parameter missing or not a valid absolute URL           |
| 403    | Upstream host is not in the whitelist                         |
| 405    | Non-GET, non-OPTIONS method                                   |
| 502    | Network failure or unreadable body when calling upstream      |

### Allowed upstream hosts

- `query1.finance.yahoo.com`
- `query2.finance.yahoo.com`
- `api.mfapi.in`

Anything else returns `403` with a JSON `{ error, host, allowed }` body.

## Deploy

From the project root (the folder that contains `supabase/`):

```bash
supabase functions deploy market-data --no-verify-jwt
```

`--no-verify-jwt` is intentional — this endpoint is meant to be hit by the
mobile/web app without an auth header.

To run locally during development:

```bash
supabase functions serve market-data --no-verify-jwt
# then hit: http://localhost:54321/functions/v1/market-data?url=...
```

## Invoking from Dart / Flutter

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class MarketDataClient {
  MarketDataClient({required this.supabaseUrl, required this.anonKey});

  final String supabaseUrl; // e.g. https://abcd.supabase.co
  final String anonKey;

  Uri _proxy(String upstream) {
    return Uri.parse('$supabaseUrl/functions/v1/market-data').replace(
      queryParameters: {'url': upstream},
    );
  }

  /// Fetch a Yahoo Finance chart for [symbol].
  Future<Map<String, dynamic>> yahooChart(
    String symbol, {
    String interval = '1d',
    String range = '1mo',
  }) async {
    final upstream =
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=$interval&range=$range';

    final res = await http.get(
      _proxy(upstream),
      headers: {
        // anonKey is required by Supabase's gateway, even with --no-verify-jwt
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );

    if (res.statusCode >= 400) {
      throw Exception('market-data ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Fetch NAV history for an Indian mutual fund scheme.
  Future<Map<String, dynamic>> mfNavHistory(int schemeCode) async {
    final upstream = 'https://api.mfapi.in/mf/$schemeCode';
    final res = await http.get(
      _proxy(upstream),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );
    if (res.statusCode >= 400) {
      throw Exception('market-data ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
```

> Tip: URL-encode the `url` parameter yourself if you build it as a raw string.
> `Uri.replace(queryParameters: ...)` (used above) handles that for you.

## Cost

This runs on **Supabase Edge Functions**, which on the **free tier** include:

- **500,000 function invocations per month**
- 2 GB of egress per month (more than enough for these tiny JSON payloads)

For a typical ZeroTab user polling a watchlist every minute during market
hours, you're looking at a few thousand invocations per day — well within the
free tier. The intraday `max-age=60` / daily `max-age=3600` cache headers
further reduce upstream and invocation pressure because Supabase's CDN can
serve repeated requests from cache.

If you ever exceed the free tier, the Pro plan ($25/mo) raises this to 2M
invocations and 250 GB egress.

## Rate limits

Supabase enforces a soft rate limit of **~1000 requests per minute per IP** on
Edge Functions on the free tier. For a single user on a phone this is
effectively unlimited; for a shared egress IP (e.g. a corporate NAT, a public
WiFi) you may want to add client-side throttling. The intraday `Cache-Control:
max-age=60` header on responses helps a lot here because the browser/CDN will
not re-hit the function for the same URL within a minute.

If you need stricter quotas (per-user, per-symbol, etc.) the natural place to
add them is at the top of `handler()` in `index.ts`, using a Supabase Postgres
table as a counter.

## Files

- `index.ts` — the function itself
- `README.md` — this file

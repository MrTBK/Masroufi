# AI proxy (P4) — deploy stub, no key in APK

The app NEVER calls an LLM directly. It POSTs a redacted summary to
YOUR proxy (`--dart-define AI_PROXY_URL=https://.../explain`), which
holds the Gemini/OpenAI key server-side.

## Request

```json
POST /explain
{"lang":"en","pro":false,"summary":{"v":1,"income":1000000,"expense":300000,"top":[{"cat":"Café","millimes":5500}],"forecast":{"projected":350000,"pacePct":70}}}
```

## Proxy logic (Cloudflare Worker / Supabase Edge sketch)

1. Verify rate limit: 20/mo per install-id (header `X-Install-Id`, free),
   unlimited when `pro:true` + valid Play receipt (verify server-side).
2. System prompt: "You explain Tunisian personal-finance numbers. Given JSON totals (millimes, 1000 = 1 TND), explain in {lang} (ar/fr/en), 3-5 bullets, no invented numbers, end with 'Planning aid, not advice.' Never give investment advice."
3. Call Gemini Flash (`temperature: 0.2`, `max_tokens: 300`).
4. Return `{"text":"..."}`. Never log the summary. 15s timeout.

## Env

- `LLM_API_KEY` (server only, never `--dart-define`)
- `PRO_RECEIPT_PUBLIC_KEY` for server-side PRO verify (optional v1)

## App wiring

- `lib/core/ai/ai_summary.dart` builds the payload (no notes by default).
- `lib/core/ai/ai_gateway.dart` POSTs when `AI_PROXY_URL` is set; null
  otherwise → offline fallback UI.
- Empty `AI_PROXY_URL` (default) = cloud disabled, on-device insights only.

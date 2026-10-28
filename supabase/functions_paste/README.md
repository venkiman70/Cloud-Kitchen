# Paste-in edge functions (Supabase dashboard → Edge Functions → Deploy a new function → Via Editor)

Single-file copies of `supabase/functions/*/index.ts` with `_shared/*.ts` inlined, for deploying
without the Supabase CLI. The originals in `supabase/functions/` are the source of truth;
regenerate these after changing them.

| Function name (exact) | File | Verify JWT |
| --- | --- | --- |
| `create-order` | create-order.ts | On |
| `stripe-webhook` | stripe-webhook.ts | **Off** (Stripe can't send a Supabase token) |
| `notify-ready` | notify-ready.ts | On |

Secrets (Edge Functions → Secrets): `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `APP_URL`, `ALLOWED_ORIGINS`
(optional: `RESEND_API_KEY`, `EMAIL_FROM`, `STRIPE_CONNECT_WEBHOOK_SECRET`). `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase automatically.

# Optional private writing and GIF service

The app works without this service. Nothing is deployed automatically. This template is for the owner's private testing, with one long random access token; it is not a public multi-user subscription backend.

It uses Cloudflare Workers AI, an AI binding and the Workers Rate Limiting API. Only `POST /write` (writing tools) and `GET /gifs` (GIF search) are served, both behind the access token. It returns `{ "text": "edited text" }`, never writes text history, disables observability in the supplied configuration and never logs request bodies/tokens. Cloudflare and model-provider terms/data policies still apply. Review them before sending private text.

## Manual setup

With a Cloudflare account and billing/usage settings you choose:

1. Use Wrangler 4.36.0 or later. From this directory, authenticate with `npx wrangler@4 login`.
2. Generate a cryptographically random access token, at least 32 characters, and store it with `npx wrangler@4 secret put API_TOKEN`. Do not commit it, share it or place it in app source.
3. Choose an unused rate-limit namespace ID in `wrangler.jsonc`; the supplied ID is an example. Check the model is available and choose a suitable model for your languages. The template uses `@cf/meta/llama-3.1-8b-instruct-fp8`.
4. For GIF search, create a free GIPHY API key at developers.giphy.com and store it with `npx wrangler@4 secret put GIPHY_API_KEY`. The key never reaches the app; the keyboard sends only the search words. GIPHY's terms require showing "Powered by GIPHY", which the keyboard does.
5. Deploy with `npx wrangler@4 deploy` only after accepting the provider's usage settings and costs.
6. In the iPhone app's Writing assistant, save `https://YOUR-WORKER.workers.dev/write` and the token. Copy/import the connection separately into the keyboard if desired.

The configured rate limit is 10 requests per minute **per Cloudflare location**, and is eventually consistent. It is not a hard global spend cap. Use account budgets/usage controls and add per-user authentication, authorization and durable accounting before public distribution. Token rotation requires updating the app and keyboard connections.

The request action is one of `grammar`, `professional`, `casual`, `translate`; language is a keyboard language code such as `en`, `fr` or `yo` (the v0.1 names `english`, `yoruba` and `pidgin` still work); text is limited to 3,000 Unicode code points. The client requires HTTPS and rejects redirects. Requests are sent only after an explicit user action.

The keyboard prefers Apple's on-device translation and Apple Intelligence rewriting when available, so this service is mainly a fallback for older iPhones and languages Apple doesn't cover. The AI output is not guaranteed to be correct. Yoruba diacritics, dialect and Pidgin translation require evaluation by speakers; the app always offers a preview before replacing selected text.

```sh
node --test worker.test.mjs
```

These tests use fake inference responses to validate access control, limits and the client contract. They do not test model quality or make billable provider calls.

Official references: [Workers AI bindings](https://developers.cloudflare.com/workers-ai/configuration/bindings/), [model interface](https://developers.cloudflare.com/workers-ai/models/llama-3.1-8b-instruct-fp8/), [Rate Limiting API](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/).

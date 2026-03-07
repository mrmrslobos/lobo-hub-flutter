<div align="center">
<img width="1200" height="475" alt="GHBanner" src="https://github.com/user-attachments/assets/0aa67016-6eaf-458a-adb2-6e31a0763ed6" />
</div>

# Run and deploy your AI Studio app

This contains everything you need to run your app locally.

View your app in AI Studio: https://ai.studio/apps/drive/15p7AfHNwBt9GtTlvVAhRnIfTcMPJ34Sm

## Run Locally

**Prerequisites:**  Node.js


1. Install dependencies:
   `npm install`
2. Set the `GEMINI_API_KEY` in [.env.local](.env.local) to your Gemini API key
3. Run the app:
   `npm run dev`


## Vercel + Supabase setup

To make cloud sync use Supabase in a Vercel deployment, set these **Environment Variables** in Vercel project settings:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `VITE_GEMINI_API_KEY` (or keep your existing Gemini key mapping strategy)

Then redeploy.

> Note: In Vite apps, only variables prefixed with `VITE_` are exposed to browser code at build time.

### Troubleshooting production env vars

If Gemini calls fail in production, verify at least one of these is set in Vercel:

- `VITE_GEMINI_API_KEY` (recommended)
- `GEMINI_API_KEY`
- `API_KEY`

If Supabase sync does not write to the database:

1. Ensure `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` are set (recommended for this Vite app).
2. Run [supabase/schema.sql](supabase/schema.sql) in the Supabase SQL editor so tables + policies exist.
3. Confirm table names in Supabase match the app sync map (`users`, `families`, `tasks`, etc.).

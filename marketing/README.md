# Huddle marketing site

Static landing page for app release signups. **Primary CTA:** [Google Play](https://play.google.com/store/apps/details?id=com.opensolutions.huddle&hl=en_AU).

## Local preview

```bash
cd marketing
npx --yes serve .
```

Open http://localhost:3000

## Deploy (Vercel)

1. Create a Vercel project with **Root Directory** = `marketing`.
2. No build command; output is static files.
3. Point your domain (e.g. `huddleapp.com.au`) at this project, or use a subdomain like `www`.

## Config

Edit `config.js`:

- `googlePlayUrl` — Play Store listing (already set)
- `appUrl` — Flutter web app for “Sign in on web”

Icons: `icons/icon-192.png` (copied from `web/icons/Icon-192.png`).

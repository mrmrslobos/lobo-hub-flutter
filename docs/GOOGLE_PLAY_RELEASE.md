# Google Play release & Developer API (Huddle)

## Open beta → Production (manual, no API)

If your **open beta** build is already good and you only need to widen availability:

1. [Google Play Console](https://play.google.com/console) → **Huddle** → **Release** → **Testing** → **Open testing**.
2. Open the release that is live on open beta → **Promote release** → **Production**.
3. Complete the production checklist (countries, content rating, Data safety, etc.) if prompted.
4. **Start rollout to Production**.

Use this when you do **not** need a new binary (no Billing Library / bugfix release).

---

## New production build (Billing Library 8, bugfixes)

You need a **signed AAB** with `versionCode` **greater** than whatever is on Play now.

### 1. Local signing (`android/key.properties`)

```bash
cp android/key.properties.example android/key.properties
# Edit paths/passwords — must be the SAME upload keystore used for open beta.
```

Build:

```bash
export SUPABASE_URL=https://your-project.supabase.co
export SUPABASE_ANON_KEY=your-anon-key
export RC_ANDROID_KEY=goog_xxxxx   # optional but recommended for subscriptions
chmod +x scripts/build-release-aab.sh
./scripts/build-release-aab.sh
```

Output: `build/app/outputs/bundle/standardRelease/app-standard-release.aab`

Upload in Play Console → **Production** → **Create new release** → upload AAB → review → rollout.

Bump `version` in `pubspec.yaml` (`1.0.31+32` = versionName 1.0.31, versionCode 32) before each Play upload.

---

## Google Play Developer API + Cursor / GitHub Actions

Cursor **does not** connect to Play Console like a logged-in browser. Automation uses the **Google Play Developer API** with a **service account JSON key**.

### A. Google Cloud — service account

1. [Google Cloud Console](https://console.cloud.google.com/) → pick or create a project.
2. **APIs & Services → Library** → enable **Google Play Android Developer API**.
3. **IAM & Admin → Service Accounts → Create service account** (no GCP roles required for Play-only use).
4. **Keys → Add key → JSON** → download `play-service-account.json`. **Store securely; never commit.**

### B. Play Console — grant the service account

1. [Play Console](https://play.google.com/console) → **Users and permissions**.
2. **Invite new users** → paste the service account email (`...@...iam.gserviceaccount.com`).
3. **App permissions** → add **Huddle** (`com.opensolutions.huddle`).
4. Enable at minimum:
   - **View app information** (read-only)
   - **Release to production, exclude devices, and use Play App Signing**
   - **Release apps to testing tracks**
   - **Manage testing tracks and edit tester lists**
5. **Invite user** (no email acceptance needed; status becomes Active).

Official guide: https://developers.google.com/android-publisher/getting_started

### C. Use credentials in Cursor Cloud Agent

1. Cursor → **Dashboard → Cloud → Secrets** (or your team’s secret store for agents).
2. Add secret `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` = **entire JSON file contents**.
3. Optional build secrets (for signed AAB in CI):
   - `ANDROID_KEYSTORE_BASE64` — base64 of your `.jks` / `.keystore`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS`
   - `ANDROID_KEY_PASSWORD`
   - `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `RC_ANDROID_KEY`

Agents can then run the **Release Android** workflow or `fastlane` / `gradle-play-publisher` with those env vars. There is **no** built-in “Publish to Play” button in Cursor without this setup.

### D. GitHub Actions (this repo)

Workflow: `.github/workflows/release-android.yml`

1. Add the secrets listed in that file under repo **Settings → Secrets and variables → Actions**.
2. **Actions → Release Android AAB → Run workflow** (manual).
3. Download the `app-standard-release.aab` artifact from the run.
4. Upload to Play Console **or** wire upload step (see below).

### E. Optional: upload AAB from CI (Fastlane)

Install Fastlane locally or in CI:

```bash
# Gemfile / fastlane recommended for repeatability
fastlane supply --aab build/app/outputs/bundle/standardRelease/app-standard-release.aab \
  --package_name com.opensolutions.huddle \
  --track production \
  --json_key /path/to/play-service-account.json
```

For **first production rollout from open beta**, you may prefer **Promote release** in the UI once, then use API for future updates.

### F. “Connect API to Cursor” summary

| What you want | What to set up |
|---------------|----------------|
| Agent builds signed AAB | `ANDROID_*` secrets + run `release-android` workflow |
| Agent uploads to Play | `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` + Fastlane `supply` or Play Publisher Gradle plugin |
| Agent promotes beta → prod | API `edits.tracks` or manual **Promote release** in Console |
| Agent reads crash/analytics | Different APIs (Firebase / Play reporting); not the Publisher API |

Cursor agents only automate what you expose via **secrets + scripts/workflows**. The JSON key is the “connection.”

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| “App must use Billing Library 8” | Merge PR with `purchases_flutter` 9.x; upload **new** signed AAB |
| Upload rejected: wrong signature | Use the **same upload keystore** as open beta (`key.properties`) |
| Upload rejected: version code | Increase `+N` in `pubspec.yaml` (e.g. `1.0.31+32`) |
| API 403 on upload | Service account missing Production release permission on this app |

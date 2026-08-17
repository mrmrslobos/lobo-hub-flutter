# RevenueCat setup (Huddle / LoboHub)

This app uses [RevenueCat](https://www.revenuecat.com/) via `purchases_flutter` for App Store and Google Play subscriptions. Server-side tier enforcement can stay in Supabase; RevenueCat is the source of truth for **what the user paid for on the stores**.

## 1. Create a RevenueCat project

1. Sign up at [app.revenuecat.com](https://app.revenuecat.com) and create a project.
2. Add **iOS** and **Android** apps with the same bundle / application id as this Flutter app (`com.opensolutions.huddle` unless you change it in Xcode / Gradle).
3. Copy the **public API keys** (iOS and Android) for use at build time (see below).

## 2. App Store Connect (iOS)

1. In [App Store Connect](https://appstoreconnect.apple.com/), create **subscription group(s)** and subscription products (monthly / annual) for Base, AI, and AI Family (or your chosen lineup).
2. Note each **product identifier** (e.g. `com.opensolutions.huddle.base.monthly`).
3. In RevenueCat → **Products**, add those App Store product IDs and link them to an **Entitlement**.

## 3. Google Play Console (Android)

1. Create subscription products under **Monetize → Subscriptions** with matching logic to iOS.
2. In RevenueCat → **Products**, add the Play product IDs (with base plan IDs where required).

## 4. Entitlements

The Flutter code expects these entitlement identifiers (see `PurchaseService.checkEntitlements` and `subscriptionTierFromCustomerInfo`):

- `base` — Base (or bundled) access  
- `ai` — AI features  
- `ai_family` — optional; use for AI Family so the app maps to `SubscriptionTier.ai_family` (otherwise map that product to `ai` as well if both apply)

**Note:** This project’s RevenueCat dashboard currently uses entitlement id `ai_family_annual` for AI Family products. The app and webhook accept both `ai_family` and `ai_family_annual`. Consider renaming the entitlement to `ai_family` in RevenueCat when convenient.

Map your store products to these entitlements in the RevenueCat dashboard.

After a purchase or restore, the app calls the Supabase RPC `sync_family_subscription_tier` so `families.subscription_tier` matches the store (required for `ai-proxy` enforcement). Apply migration `21_family_subscription_tier_sync.sql` to your project.

## 5. Offerings and packages

1. RevenueCat → **Offerings** → create or use the **current** offering (often named `default`).
2. Add **packages** whose identifiers **must match** what the app requests (on the offering marked **Current**):

| Package identifier   | Typical use        |
|---------------------|--------------------|
| `base_monthly`      | Base, monthly      |
| `base_annual`       | Base, yearly       |
| `ai_monthly`        | AI, monthly        |
| `ai_annual`         | AI, yearly         |
| `ai_family_monthly` | AI Family, monthly |
| `ai_family_annual`  | AI Family, yearly  |

For **yearly** plans, the app also accepts `*_yearly` instead of `*_annual` (e.g. `ai_family_yearly`) if you named packages that way in RevenueCat.

3. Attach the correct App Store / Play product to each package.

If you use different package IDs, update `PurchaseService.packageIdentifierCandidates` in `lib/services/purchase_service.dart` to match.

## 6. Build-time API keys (Flutter)

Pass public SDK keys as compile-time defines (do **not** commit secrets in source if the repo is public):

```bash
flutter build apk --release \
  --dart-define=RC_ANDROID_KEY=goog_xxx

flutter build ios --release \
  --dart-define=RC_IOS_KEY=appl_xxx
```

`lib/main.dart` reads `RC_IOS_KEY` and `RC_ANDROID_KEY` and passes them to `PurchaseService.init`.

## 7. User identity (Supabase ↔ RevenueCat)

On sign-in, the app calls `Purchases.logIn(<supabase user id>)` so purchases attach to the same user across devices. On sign-out it calls `Purchases.logOut()`.

Configure RevenueCat **REST API / webhooks** so `subscription_tier` stays in sync when subscriptions renew, expire, or cancel while the app is closed.

### Webhook (Supabase edge function)

The repo includes `supabase/functions/revenuecat-webhook`, which maps RevenueCat entitlement ids to `families.subscription_tier` via the `sync_family_subscription_tier_system` RPC.

1. Generate a long random secret (e.g. `openssl rand -hex 32`).
2. Set it on Supabase:
   ```bash
   supabase secrets set REVENUECAT_WEBHOOK_AUTHORIZATION="Bearer <your-secret>"
   ```
3. Deploy the function (or merge a PR that triggers your deploy pipeline):
   ```bash
   supabase functions deploy revenuecat-webhook --no-verify-jwt
   ```
4. In RevenueCat → **Integrations → Webhooks**, add:
   - **URL:** `https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook`
   - **Authorization header:** the same value as `REVENUECAT_WEBHOOK_AUTHORIZATION` (include `Bearer ` if you used it above)
   - **Environment:** Production (and Sandbox while testing)
   - **Events:** at minimum `INITIAL_PURCHASE`, `RENEWAL`, `PRODUCT_CHANGE`, `UNCANCELLATION`, `EXPIRATION`

`trial_start_date` is synced from the app on family create/update. `subscription_tier` is **not** written by normal client sync (security); only the app RPC after purchase/restore, or this webhook, may change it.

## 8. iOS project notes

After cloning, run `flutter pub get` and `cd ios && pod install` so `Generated.xcconfig`, CocoaPods, and `GeneratedPluginRegistrant` are created locally (some paths are gitignored by design).

Minimum iOS version for this project is **13.0** (see `ios/Podfile`).

## 9. Testing

- **iOS:** StoreKit Configuration in Xcode, or sandbox Apple IDs.  
- **Android:** License testers in Play Console.  
- Use RevenueCat’s **Customer profile** page to verify `appUserID` and entitlements after a test purchase.

## 10. Introductory pricing (AI Family yearly — AUD 149 first year, AUD 199 renewal)

Binding prices and eligibility always come from **Apple/Google**. Flutter marketing copy uses AUD amounts as a **guide** only when live store strings are unavailable.

**Configure intro offers on each platform:**

1. **App Store Connect** — Open the **annual AI Family** subscription → **Subscription Prices** → add an **Introductory Offer** (e.g. pay-as-you-go first period at AUD 149 for one year, then standard price AUD 199/year). Match Apple’s current workflows for introductory pricing and eligibility (often new subscribers only).

2. **Google Play Console** — Under the subscription **base plan** for AI Family yearly, add an **offer** or introductory phase (e.g. lower price year one, then renewal at AUD 199). Align base-plan renewal pricing with your ongoing yearly SKU.

3. **RevenueCat** — No separate package id is required if intro is on the **same** store product attached to `ai_family_annual` / `ai_family_yearly`; RevenueCat passes through `StoreProduct.priceString` from the store. Confirm on a **sandbox** purchase that the pay sheet shows the intro.

4. **Verify** — After publishing offers, run through Subscribe on device; optional checks in RevenueCat customer detail for introductory vs standard period.

If you change regional pricing, update fallback AUD figures in `lib/screens/subscription/subscription_screen.dart` (`_pricing`) so web/offline placeholders stay aligned with marketing.

# RevenueCat setup (FamilyHub / LoboHub)

This app uses [RevenueCat](https://www.revenuecat.com/) via `purchases_flutter` for App Store and Google Play subscriptions. Server-side tier enforcement can stay in Supabase; RevenueCat is the source of truth for **what the user paid for on the stores**.

## 1. Create a RevenueCat project

1. Sign up at [app.revenuecat.com](https://app.revenuecat.com) and create a project.
2. Add **iOS** and **Android** apps with the same bundle / application id as this Flutter app (`com.lobohub.app` unless you change it in Xcode / Gradle).
3. Copy the **public API keys** (iOS and Android) for use at build time (see below).

## 2. App Store Connect (iOS)

1. In [App Store Connect](https://appstoreconnect.apple.com/), create **subscription group(s)** and subscription products (monthly / annual) for Base, AI, and AI Family (or your chosen lineup).
2. Note each **product identifier** (e.g. `com.lobohub.app.base.monthly`).
3. In RevenueCat → **Products**, add those App Store product IDs and link them to an **Entitlement**.

## 3. Google Play Console (Android)

1. Create subscription products under **Monetize → Subscriptions** with matching logic to iOS.
2. In RevenueCat → **Products**, add the Play product IDs (with base plan IDs where required).

## 4. Entitlements

The Flutter code expects these entitlement identifiers (see `PurchaseService.checkEntitlements` and `subscriptionTierFromCustomerInfo`):

- `base` — Base (or bundled) access  
- `ai` — AI features  
- `ai_family` — optional; use for AI Family so the app maps to `SubscriptionTier.ai_family` (otherwise map that product to `ai` as well if both apply)

Map your store products to these entitlements in the RevenueCat dashboard.

After a purchase or restore, the app calls the Supabase RPC `sync_family_subscription_tier` so `families.subscription_tier` matches the store (required for `ai-proxy` enforcement). Apply migration `21_family_subscription_tier_sync.sql` to your project.

## 5. Offerings and packages

1. RevenueCat → **Offerings** → create or use the **current** offering (often named `default`).
2. Add **packages** whose identifiers **must match** what the app requests:

| Package identifier   | Typical use        |
|---------------------|--------------------|
| `base_monthly`      | Base, monthly      |
| `base_annual`       | Base, yearly       |
| `ai_monthly`        | AI, monthly        |
| `ai_annual`         | AI, yearly         |
| `ai_family_monthly` | AI Family, monthly |
| `ai_family_annual`  | AI Family, yearly  |

3. Attach the correct App Store / Play product to each package.

If you use different package IDs, update `PurchaseService.packageIdentifier` in `lib/services/purchase_service.dart` to match.

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

Configure RevenueCat **REST API / webhooks** if your Supabase backend must update `subscription_tier` when a subscription changes.

## 8. iOS project notes

After cloning, run `flutter pub get` and `cd ios && pod install` so `Generated.xcconfig`, CocoaPods, and `GeneratedPluginRegistrant` are created locally (some paths are gitignored by design).

Minimum iOS version for this project is **13.0** (see `ios/Podfile`).

## 9. Testing

- **iOS:** StoreKit Configuration in Xcode, or sandbox Apple IDs.  
- **Android:** License testers in Play Console.  
- Use RevenueCat’s **Customer profile** page to verify `appUserID` and entitlements after a test purchase.

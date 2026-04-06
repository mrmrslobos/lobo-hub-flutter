# Google Calendar Sync Setup

## Prerequisites

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a project (or use your existing Firebase project)
3. Enable the **Google Calendar API**
4. Configure the **OAuth consent screen** (External, add `../auth/calendar.readonly` scope)

## Android Setup

1. Go to **APIs & Services > Credentials**
2. Create an **OAuth 2.0 Client ID** for Android:
   - Application type: Android
   - Package name: `com.opensolutions.huddle`
   - SHA-1 fingerprint: Run `cd android && ./gradlew signingReport`
3. Download `google-services.json` from your Firebase project (or create one)
4. Place it at `android/app/google-services.json`

> An example file is at `android/app/google-services.json.example`

## iOS Setup

1. Create an **OAuth 2.0 Client ID** for iOS:
   - Application type: iOS
   - Bundle ID: `com.opensolutions.huddle`
2. Download the `GoogleService-Info.plist`
3. Place it at `ios/Runner/GoogleService-Info.plist`
4. In `ios/Runner/Info.plist`, replace the two placeholder values:
   - `com.googleusercontent.apps.YOUR_IOS_CLIENT_ID` → your reversed client ID
   - `YOUR_IOS_CLIENT_ID.apps.googleusercontent.com` → your client ID

## Web Setup (if applicable)

1. Create an **OAuth 2.0 Client ID** for Web application
2. Add authorized JavaScript origins and redirect URIs

## Testing

After setup, the "Google Sync" button on the Calendar screen should:
1. Open Google Sign-In
2. Show your Google Calendars for selection
3. Import events from selected calendars

The "My Calendars" button lets you manage connected calendars and re-sync.

import type { CapacitorConfig } from '@capacitor/cli';

/**
 * Capacitor configuration for iOS & Android app store builds.
 *
 * Steps to build:
 *   1. npm install
 *   2. npm run build          (creates dist/)
 *   3. npx cap add ios        (first time only — needs macOS + Xcode)
 *   4. npx cap add android    (first time only — needs Android Studio)
 *   5. npm run cap:ios        (build + open in Xcode)
 *   6. npm run cap:android    (build + open in Android Studio)
 *
 * Required accounts:
 *   - Apple Developer Program: $99/year — https://developer.apple.com
 *   - Google Play Console: $25 one-time — https://play.google.com/console
 */
const config: CapacitorConfig = {
  appId: 'com.lobohub.app',
  appName: 'FamilyHub',
  webDir: 'dist',
  server: {
    androidScheme: 'https',
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 2000,
      backgroundColor: '#fcfcf9',
      showSpinner: false,
    },
    StatusBar: {
      style: 'default',
      backgroundColor: '#6366f1',
      overlaysWebView: false,
    },
    PushNotifications: {
      // Show notifications even when the app is in the foreground
      presentationOptions: ['badge', 'sound', 'alert'],
    },
    LocalNotifications: {
      // Used for scheduled task reminders
      smallIcon: 'ic_stat_icon_config_sample',
      iconColor: '#6366f1',
      sound: 'default.wav',
    },
  },
  android: {
    // Allow the WebView to use navigator.geolocation.
    // Requires ACCESS_FINE_LOCATION in AndroidManifest.xml (added in android/app/src/main/AndroidManifest.xml).
    allowMixedContent: true,
  },
};

export default config;

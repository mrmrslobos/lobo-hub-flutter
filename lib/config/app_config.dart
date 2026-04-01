/// Central brand configuration for Huddle.
class AppConfig {
  static const String appName = 'Huddle';
  static const String appShortName = 'Huddle';
  static const String appDescription =
      'Family management app for tasks, meals, budget, calendar, and more.';
  static const String appBundleId = 'com.opensolutions.huddle';

  // Auth copy
  static const String loginTagline = 'Welcome back.';
  static const String signupTagline = 'Create your account.';
  static const String onboardingTagline = 'Set up your home.';

  // Onboarding
  static const String createHubLabel = 'Create New Home';
  static const String createHubSubLabel = 'Start fresh for your family';
  static const String joinHubLabel = 'Join Existing Home';
  static const String joinHubSubLabel = 'Join via invite code';
  static const String familyNamePlaceholder = 'e.g., The Smith Family';

  // Nav
  static const String defaultUserName = 'Family Member';

  // AI
  static const String aiCoachName = 'AI Wellness Assistant';

  // Storage keys
  static const String storageKey = 'lobohub_db';
  static const String activeUserKey = 'lobohub_active_user_id';

  // Subscription
  static const int trialDays = 14;

  // Theme
  static const String themeColorHex = '#6366f1';
  static const String backgroundColorHex = '#fcfcf9';

  // Legal
  static const String privacyPolicyUrl = 'https://huddleapp.com.au/privacy';
  static const String termsOfServiceUrl = 'https://huddleapp.com.au/terms';

  // OAuth / deep-link redirects
  static const String oauthRedirectScheme =
      'com.opensolutions.huddle://login-callback';
  static const String passwordResetRedirect =
      'com.opensolutions.huddle://reset-callback';
}

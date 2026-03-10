/// Central brand configuration for FamilyHub.
class AppConfig {
  static const String appName = 'FamilyHub';
  static const String appShortName = 'FamilyHub';
  static const String appDescription =
      'Family management hub for tasks, meals, budget, calendar, and more.';
  static const String appBundleId = 'com.lobohub.app';

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
  static const String aiCoachName = 'AI Health Coach';

  // Storage keys
  static const String storageKey = 'lobohub_db';
  static const String activeUserKey = 'lobohub_active_user_id';

  // Subscription
  static const int trialDays = 14;

  // Theme
  static const String themeColorHex = '#6366f1';
  static const String backgroundColorHex = '#fcfcf9';

  // OAuth / deep-link redirects
  static const String oauthRedirectScheme = 'com.lobohub.app://login-callback';
  static const String passwordResetRedirect =
      'com.lobohub.app://reset-callback';
}

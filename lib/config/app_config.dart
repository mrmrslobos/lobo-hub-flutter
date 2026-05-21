/// Central brand configuration for Huddle (customer-facing).
/// Internal / repo name: LoboHub — do not show in UI.
class AppConfig {
  static const String appName = 'Huddle';
  static const String appShortName = 'Huddle';
  static const String appDescription =
      'Family life in one app — tasks, calendar, meals, budget, and more.';
  static const String internalProductName = 'LoboHub';
  static const String appBundleId = 'com.opensolutions.huddle';

  /// Google Play listing (marketing site & in-app “get the app” links).
  static const String googlePlayUrl =
      'https://play.google.com/store/apps/details?id=com.opensolutions.huddle&hl=en_AU';

  // Auth copy
  static const String loginTagline = 'Welcome back.';
  static const String signupTagline = 'Create your account.';
  static const String onboardingTagline = 'Set up your family.';

  // Onboarding (family-first; “home” only where legally/store copy needs it)
  static const String createHubLabel = 'Start a new family';
  static const String createHubSubLabel = 'Invite people anytime with your code';
  static const String joinHubLabel = 'Join a family';
  static const String joinHubSubLabel = 'Use your invite code';
  static const String familyNamePlaceholder = 'e.g., The Smith Family';

  // Auth — create / join family (shared account, not “home” metaphor in headings)
  static const String authOnboardingSubtitle =
      'Create a new family or join one with a code';
  static const String authNameYourFamilyTitle = 'Name your family';
  static const String authNameYourFamilySubtitle =
      'This name is visible to everyone you invite';
  static const String authFamilyNameFieldLabel = 'Family name';
  static const String authCreateFamilyCta = 'Create family';
  static const String authJoinFamilyTitle = 'Join a family';
  static const String authJoinFamilyCta = 'Join family';
  static const String authInvalidInviteCodeFamily =
      'No family found with that code. Check and try again.';

  // Nav
  static const String defaultUserName = 'Family member';
  static const String manageFamilyMembersLabel = 'Family members';
  static const String manageFamilyMembersTitle = 'Family members';
  static const String activityLogLabel = 'Activity log';
  static const String familyPulseLabel = 'Family pulse';

  // Subscription — user-facing plan names (enums stay base / ai / ai_family in code)
  static const String planLabelEssentials = 'Essentials';
  static const String planDescEssentials = 'Core tools for your family';
  static const String planLabelAi = 'AI';
  static const String planDescAi = 'Smart AI features for busy families';
  static const String planLabelAiFamily = 'AI · Family';
  static const String planDescAiFamily =
      'Full AI for up to 2 adults and 2 children under 16';
  static const String planTrialExpiredBlurb =
      'You have Tasks, Lists & Calendar. Upgrade for the full app.';

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

  /// Customer support (mailto). Used from Settings → About.
  static const String supportEmail = 'support@huddleapp.com.au';

  // OAuth / deep-link redirects
  static const String oauthRedirectScheme =
      'com.opensolutions.huddle://login-callback';
  static const String passwordResetRedirect =
      'com.opensolutions.huddle://reset-callback';
}

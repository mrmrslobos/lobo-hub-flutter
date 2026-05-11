/// Compile-time flags. Photoframe wall mode:
/// `flutter run` / `flutter build apk` with `--dart-define=PHOTOFRAME=true`
/// (use with `--flavor photoframe` on Android for the launcher label).
abstract final class BuildFlags {
  static const bool photoframe =
      bool.fromEnvironment('PHOTOFRAME', defaultValue: false);
}

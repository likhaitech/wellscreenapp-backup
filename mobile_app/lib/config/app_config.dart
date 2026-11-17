/// Central place for settings that differ between local development and
/// a real deployment - right now just the backend's base URL.
class AppConfig {
  static const String backendBaseUrl = String.fromEnvironment(
    'WELLSCREEN_BACKEND_URL',
    defaultValue: 'https://wellscreenapp-backup.onrender.com',
  );
}

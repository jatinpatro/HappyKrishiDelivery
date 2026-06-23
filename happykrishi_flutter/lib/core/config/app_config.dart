/// App configuration — change values here to switch environments.
/// For CI/CD, override with --dart-define=API_BASE_URL=https://...
class AppConfig {
  // ── Environment ───────────────────────────────────────────────────────────────
  static const bool isProduction = bool.fromEnvironment('PRODUCTION', defaultValue: false);

  // ── Backend URL ───────────────────────────────────────────────────────────────
  // Local development:  http://localhost:3000
  // Production:         https://your-domain.com  (or EC2 IP)
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://localhost:3000',
  );

  // ── App info ──────────────────────────────────────────────────────────────────
  static const String appName = 'HappyKrishi Delivery';
  static const String appVersion = '1.0.0';

  // ── Business rules (mirrors backend app_config — UI only) ────────────────────
  // These are shown as defaults in the UI before app-info loads from backend.
  static const double defaultMinWalletBalance = 100;
  static const double defaultFreeDeliveryAbove = 500;
  static const double defaultBaseDeliveryCharge = 30;
}

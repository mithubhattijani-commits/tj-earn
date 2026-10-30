/// Runtime configuration, supplied with --dart-define at build time.
///
/// Nothing secret is baked in here: the anon key is a *public* Supabase key
/// (RLS still enforces all access rules). If either value is missing the app
/// shows a clear configuration error and never displays a fake balance.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

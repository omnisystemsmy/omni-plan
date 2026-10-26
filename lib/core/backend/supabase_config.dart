/// Public Supabase project configuration for the mobile client.
///
/// The publishable key identifies the app; it is not a service-role key.
/// Access control belongs in Supabase Auth and Row Level Security policies.
/// Both values can be overridden with dart defines for another environment.
class SupabaseConfig {
  SupabaseConfig._();

  /// False in isolated widget tests that build the local shell without the
  /// asynchronous application bootstrap. It is set true by main() after the
  /// client is initialized.
  static bool initialized = false;

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://oqsnrzfoohhjqqenxmhl.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_EMNRb568EiU3R1IGATgiFw_ju-mGH8c',
  );
}

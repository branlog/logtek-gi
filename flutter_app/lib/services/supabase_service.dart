import 'package:supabase_flutter/supabase_flutter.dart';

class Supa {
  Supa._(); // empêche l'instanciation

  // Evite l'init statique trop tôt : on expose un getter
  static SupabaseClient get i => Supabase.instance.client;

  static Future<void> init({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        // conserve la session et rafraîchit automatiquement le token
        autoRefreshToken: true,
        // authFlowType: AuthFlowType.pkce, // (optionnel, pkce est recommandé sur mobile)
      ),
    );
  }
}

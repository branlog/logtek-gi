import 'package:supabase_flutter/supabase_flutter.dart';

class AuthResult { final bool ok; final String? err; AuthResult(this.ok, [this.err]); }

class AuthService {
  static final _sb = Supabase.instance.client;

  static Future<AuthResult> signIn(String email, String password) async {
    try {
      await _sb.auth.signInWithPassword(email: email, password: password);
      return AuthResult(true);
    } on AuthException catch (e) {
      return AuthResult(false, e.message);
    } catch (e) {
      return AuthResult(false, e.toString());
    }
  }

  static Future<AuthResult> signUp(String email, String password) async {
    try {
      await _sb.auth.signUp(email: email, password: password);
      return AuthResult(true);
    } on AuthException catch (e) {
      return AuthResult(false, e.message);
    } catch (e) {
      return AuthResult(false, e.toString());
    }
  }

  static Future<void> signOut() => _sb.auth.signOut();
}

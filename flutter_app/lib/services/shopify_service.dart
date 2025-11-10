import 'package:supabase_flutter/supabase_flutter.dart';

class ShopifyLinkException implements Exception {
  ShopifyLinkException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'ShopifyLinkException: $message';
}

class ShopifyService {
  ShopifyService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static Future<void> linkAccount(
    String shopDomain,
    String email,
    String password,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw ShopifyLinkException(
        'Aucun utilisateur connecté. Merci de vous authentifier avant de lier un compte Shopify.',
      );
    }

    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'shopify-link',
        body: <String, dynamic>{
          'shopDomain': shopDomain.trim(),
          'email': email.trim(),
          'password': password,
        },
      );
    } on FunctionException catch (error) {
      throw ShopifyLinkException(
        _messageFromFunctionError(error.details) ??
            'La fonction edge shopify-link a retourné une erreur (${error.status}).',
        error,
      );
    } catch (error) {
      throw ShopifyLinkException(
        'Impossible d’appeler la fonction edge shopify-link.',
        error,
      );
    }

    final payload = _payloadAsMap(response.data);

    final upsertData = <String, dynamic>{
      'user_id': user.id,
      'shop_domain': shopDomain.trim(),
      if (payload['customer_id'] ?? payload['customerId'] != null)
        'customer_id': payload['customer_id'] ?? payload['customerId'],
      'customer_email':
          payload['customer_email'] ?? payload['customerEmail'] ?? email.trim(),
      if (payload['access_token'] ?? payload['accessToken'] != null)
        'access_token': payload['access_token'] ?? payload['accessToken'],
      if (payload['expires_at'] ?? payload['expiresAt'] != null)
        'expires_at':
            _normalizeTimestamp(payload['expires_at'] ?? payload['expiresAt']),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    upsertData.removeWhere((_, value) => value == null);

    try {
      await _client.from('shopify_accounts').upsert(upsertData);
    } on PostgrestException catch (error) {
      throw ShopifyLinkException(
        'Échec de l’enregistrement de shopify_accounts.',
        error,
      );
    } catch (error) {
      throw ShopifyLinkException(
        'Erreur inattendue lors de l’enregistrement de shopify_accounts.',
        error,
      );
    }
  }

  static Map<String, dynamic> _payloadAsMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map(
        (key, value) => MapEntry(key?.toString() ?? '', value),
      )..removeWhere((key, _) => key.isEmpty);
    }
    return <String, dynamic>{};
  }

  static String? _messageFromFunctionError(dynamic details) {
    if (details == null) return null;
    if (details is String && details.isNotEmpty) {
      return details;
    }
    if (details is Map) {
      final message = details['message'];
      if (message is String && message.isNotEmpty) return message;
      final error = details['error'];
      if (error is String && error.isNotEmpty) return error;
    }
    return null;
  }

  static String? _normalizeTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    if (raw is DateTime) return raw.toUtc().toIso8601String();
    if (raw is num) {
      final isSecondsPrecision = raw.abs() < 1000000000000;
      final epoch = isSecondsPrecision ? raw * 1000 : raw;
      final date = DateTime.fromMillisecondsSinceEpoch(
        epoch.round(),
        isUtc: true,
      );
      return date.toIso8601String();
    }
    return raw.toString();
  }
}

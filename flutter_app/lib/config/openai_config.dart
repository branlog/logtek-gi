import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIConfig {
  const OpenAIConfig._();

  static String get apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  static bool get isConfigured => apiKey.isNotEmpty;
}

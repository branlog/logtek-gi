import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../config/openai_config.dart';
import 'connectivity_service.dart';

enum CopilotIntentType {
  createPurchaseRequest,
  inventoryAdjust,
  equipmentTask,
  dieselLog,
  unknown,
}

class CopilotIntent {
  const CopilotIntent({
    required this.type,
    required this.summary,
    this.payload = const <String, dynamic>{},
    this.rawText,
  });

  final CopilotIntentType type;
  final String summary;
  final Map<String, dynamic> payload;
  final String? rawText;
}

class CopilotTranscript {
  const CopilotTranscript({
    required this.text,
    required this.isFinal,
    this.isError = false,
    this.isCopilot = false,
  });

  final String text;
  final bool isFinal;
  final bool isError;
  final bool isCopilot;
}

class CopilotFeedback {
  const CopilotFeedback({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;
}

class CopilotService {
  CopilotService._();

  static final CopilotService instance = CopilotService._();
  static const String _model = 'gpt-4o-mini';

  final stt.SpeechToText _speech = stt.SpeechToText();
  final http.Client _http = http.Client();
  bool _speechReady = false;
  bool _initialised = false;

  final StreamController<CopilotTranscript> _transcripts =
      StreamController<CopilotTranscript>.broadcast();
  final ValueNotifier<bool> isListening = ValueNotifier<bool>(false);

  Stream<CopilotTranscript> get transcriptStream => _transcripts.stream;

  Future<bool> initSpeech() async {
    if (_initialised) return _speechReady;
    _speechReady = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: _onSpeechError,
    );
    _initialised = true;
    return _speechReady;
  }

  void dispose() {
    _transcripts.close();
    isListening.dispose();
    _http.close();
  }

  Future<bool> startListening({String localeId = 'fr_FR'}) async {
    if (!ConnectivityService.instance.isOnline) {
      _transcripts.add(
        const CopilotTranscript(
          text: 'Micro hors ligne — connecte-toi pour la dictée.',
          isFinal: true,
          isError: true,
        ),
      );
      return false;
    }
    if (!_initialised) {
      await initSpeech();
    }
    if (!_speechReady) return false;
    isListening.value = true;
    await _speech.listen(
      localeId: localeId,
      onResult: _onSpeechResult,
      listenMode: stt.ListenMode.dictation,
    );
    return true;
  }

  Future<void> stopListening() async {
    if (!_speechReady) return;
    await _speech.stop();
    isListening.value = false;
  }

  void cancelListening() {
    if (!_speechReady) return;
    _speech.cancel();
    isListening.value = false;
  }

  Future<CopilotIntent> interpretText(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const CopilotIntent(
        type: CopilotIntentType.unknown,
        summary: 'Commande vide.',
        payload: <String, dynamic>{},
      );
    }
    if (!OpenAIConfig.isConfigured ||
        !ConnectivityService.instance.isOnline) {
      return _localIntent(trimmed);
    }
    try {
      final intent = await _interpretViaOpenAI(trimmed);
      if (intent != null) return intent;
    } catch (_) {
      // Échec — on retombe sur le moteur local.
    }
    return _localIntent(trimmed);
  }

  Future<String?> converse(String raw) async {
    final prompt = raw.trim();
    if (prompt.isEmpty) return null;
    if (!OpenAIConfig.isConfigured) {
      return 'LogAI n’est pas configuré pour répondre pour le moment.';
    }
    if (!ConnectivityService.instance.isOnline) {
      return 'LogAI est hors ligne. Réessaie quand la connexion sera rétablie.';
    }
    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    try {
      final response = await _http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${OpenAIConfig.apiKey}',
        },
        body: jsonEncode({
          'model': _model,
          'temperature': 0.5,
          'messages': [
            {
              'role': 'system',
              'content':
                  'Tu es LogAI, un assistant pour une entreprise de gestion d’inventaire. '
                      'Réponds en français de façon concise mais utile. '
                      'Si l’utilisateur pose une question générale ou demande un conseil, réponds directement. '
                      'Si la demande nécessite une action précise (inventaire, tâches, carburant), essaie de proposer des étapes.'
            },
            {
              'role': 'user',
              'content': prompt,
            },
          ],
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'];
        if (choices is List && choices.isNotEmpty) {
          final content =
              choices.first['message']?['content']?.toString().trim();
          if (content != null && content.isNotEmpty) {
            return content;
          }
        }
      }
    } catch (_) {
      // Ignorer — retour fallback.
    }
    return 'LogAI ne peut pas répondre pour l’instant.';
  }

  Future<CopilotIntent?> _interpretViaOpenAI(String raw) async {
    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final schema = {
      'name': 'copilot_intent',
      'schema': {
        'type': 'object',
        'required': ['intent', 'summary'],
        'properties': {
          'intent': {
            'type': 'string',
            'enum': [
              'purchase_request',
              'inventory_adjust',
              'equipment_task',
              'diesel_log',
              'unknown',
            ],
          },
          'summary': {'type': 'string'},
          'payload': {
            'type': 'object',
            'properties': {
              'item_name': {'type': 'string'},
              'qty': {'type': 'number'},
              'warehouse': {'type': 'string'},
              'section': {'type': 'string'},
              'note': {'type': 'string'},
              'priority': {'type': 'string'},
              'delay_days': {'type': 'number'},
              'repeat_days': {'type': 'number'},
              'equipment_name': {'type': 'string'},
              'equipment_id': {'type': 'string'},
              'liters': {'type': 'number'},
              'action': {'type': 'string'},
            },
          },
        },
      },
    };
    final response = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${OpenAIConfig.apiKey}',
      },
      body: jsonEncode({
        'model': _model,
        'temperature': 0.1,
        'response_format': {
          'type': 'json_schema',
          'json_schema': schema,
        },
        'messages': [
          {
            'role': 'system',
            'content':
                'Tu es LogAI, l’assistant pour une application d’inventaire. '
                    'Analyse la commande utilisateur et retourne un JSON respectant le schema. '
                    'Les intents possibles : purchase_request, inventory_adjust, equipment_task, diesel_log, unknown. '
                    'Interprète les quantités (chiffres, unités comme L, litres, gallons) et fournis un résumé court en français. '
                    'Le payload doit contenir tous les champs utiles : item_name, qty (positif pour ajout, négatif pour retrait), '
                    'warehouse, section, note, priority, delay_days, repeat_days, equipment_name, equipment_id, liters pour diesel, etc. '
                    'Si l’utilisateur indique avoir déjà acheté/reçu une pièce existante, mets payload.action="mark_purchased" pour fermer la demande concernée. '
                    'Si tu n’es pas certain, renvoie intent=unknown mais inclue la meilleure estimation dans payload.raw_text.'
          },
          {
            'role': 'user',
            'content': 'ajoute 12 chaînes pour l’entrepôt principal',
          },
          {
            'role': 'assistant',
            'content': jsonEncode({
              'intent': 'purchase_request',
              'summary': 'Ajouter 12 chaînes à commander.',
              'payload': {
                'item_name': 'chaînes',
                'qty': 12,
                'warehouse': 'principal',
              },
            }),
          },
          {
            'role': 'user',
            'content': '55L fuel sur la pelle mécanique 102',
          },
          {
            'role': 'assistant',
            'content': jsonEncode({
              'intent': 'diesel_log',
              'summary': 'Journaliser 55 L de diesel.',
              'payload': {
                'equipment_name': 'pelle mécanique 102',
                'liters': 55,
                'note': 'plein de fuel',
              },
            }),
          },
          {
            'role': 'user',
            'content': raw,
          },
        ],
      }),
    );
    if (response.statusCode >= 300) {
      return null;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final message = (choices.first as Map)['message'] as Map?;
    if (message == null) return null;
    final content = message['content'];
    final text = content is String
        ? content
        : (content is List && content.isNotEmpty
            ? content.first['text']?.toString()
            : null);
    if (text == null) return null;
    final parsed = jsonDecode(text);
    if (parsed is! Map) return null;
    return _intentFromJson(parsed.cast<String, dynamic>(),
        rawText: raw);
  }

  CopilotIntent _localIntent(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('demande') ||
        lower.contains('acheter') ||
        lower.contains('commande')) {
      return CopilotIntent(
        type: CopilotIntentType.createPurchaseRequest,
        summary: 'Créer une demande d’achat',
        payload: {'raw_text': raw},
        rawText: raw,
      );
    }
    if (lower.contains('inventaire') ||
        lower.contains('stock') ||
        lower.contains('section')) {
      return CopilotIntent(
        type: CopilotIntentType.inventoryAdjust,
        summary: 'Ajuster une quantité d’inventaire',
        payload: {'raw_text': raw},
        rawText: raw,
      );
    }
    if (lower.contains('diesel') ||
        lower.contains('fuel') ||
        lower.contains('carburant') ||
        lower.contains('essence')) {
      return CopilotIntent(
        type: CopilotIntentType.dieselLog,
        summary: 'Journaliser du carburant',
        payload: {'raw_text': raw},
        rawText: raw,
      );
    }
    if (lower.contains('tâche') || lower.contains('mécanique')) {
      return CopilotIntent(
        type: CopilotIntentType.equipmentTask,
        summary: 'Mettre à jour une tâche équipement',
        payload: {'raw_text': raw},
        rawText: raw,
      );
    }
    return CopilotIntent(
      type: CopilotIntentType.unknown,
      summary: 'Commande non reconnue',
      payload: {'raw_text': raw},
      rawText: raw,
    );
  }

  CopilotIntent _intentFromJson(
    Map<String, dynamic> data, {
    String? rawText,
  }) {
    final type = _intentTypeFromString(data['intent']?.toString());
    final summary = data['summary']?.toString() ?? 'Commande';
    final payload = data['payload'] is Map
        ? Map<String, dynamic>.from(data['payload'] as Map)
        : <String, dynamic>{};
    return CopilotIntent(
      type: type,
      summary: summary,
      payload: payload,
      rawText: rawText,
    );
  }

  CopilotIntentType _intentTypeFromString(String? raw) {
    switch (raw) {
      case 'purchase_request':
        return CopilotIntentType.createPurchaseRequest;
      case 'inventory_adjust':
        return CopilotIntentType.inventoryAdjust;
      case 'equipment_task':
        return CopilotIntentType.equipmentTask;
      case 'diesel_log':
        return CopilotIntentType.dieselLog;
      default:
        return CopilotIntentType.unknown;
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    _transcripts.add(
      CopilotTranscript(
        text: result.recognizedWords,
        isFinal: result.finalResult,
      ),
    );
  }

  void _onSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      isListening.value = false;
    } else if (status == 'listening') {
      isListening.value = true;
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    final rawMessage = error.errorMsg;
    final message =
        rawMessage.isNotEmpty ? rawMessage : 'Erreur microphone';
    _transcripts.add(
      CopilotTranscript(
        text: message,
        isFinal: true,
        isError: true,
      ),
    );
    isListening.value = false;
  }
}

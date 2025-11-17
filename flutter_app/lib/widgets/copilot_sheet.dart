import 'dart:async';

import 'package:flutter/material.dart';

import '../services/copilot_service.dart';
import '../utils/async_utils.dart';

class CopilotSheet extends StatefulWidget {
  const CopilotSheet({
    super.key,
    required this.service,
    required this.onSubmit,
    required this.online,
    this.onlineStream,
  });

  final CopilotService service;
  final Future<CopilotFeedback?> Function(String text) onSubmit;
  final bool online;
  final Stream<bool>? onlineStream;

  @override
  State<CopilotSheet> createState() => _CopilotSheetState();
}

class _CopilotSheetState extends State<CopilotSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  final List<CopilotTranscript> _messages = <CopilotTranscript>[];
  StreamSubscription<CopilotTranscript>? _sub;
  StreamSubscription<bool>? _onlineSub;
  String? _error;
  bool _online = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _online = widget.online;
    _onlineSub = widget.onlineStream?.listen((online) {
      if (!mounted) return;
      setState(() => _online = online);
      if (!online) {
        widget.service.stopListening();
      }
    });
    _sub = widget.service.transcriptStream.listen((event) {
      setState(() {
        _messages.insert(0, event);
      });
      if (event.isFinal && !event.isError) {
        runDetached(_submitText(event.text, addBubble: false));
      }
      if (event.isError) {
        setState(() => _error = event.text);
      }
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _sub?.cancel();
    _onlineSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleListen() async {
    if (!_online) {
      setState(() => _error = 'Mode hors ligne — dictée indisponible.');
      return;
    }
    final listening = widget.service.isListening.value;
    if (listening) {
      await widget.service.stopListening();
      return;
    }
    final ok = await widget.service.startListening();
    if (!ok && mounted) {
      setState(
        () => _error = 'Micro non disponible. Vérifie les autorisations.',
      );
    }
  }

  Future<void> _handleSubmit() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    await _submitText(text);
    if (mounted) {
      _textCtrl.clear();
    }
  }

  Future<void> _submitText(String text, {bool addBubble = true}) async {
    if (text.isEmpty) return;
    setState(() {
      _submitting = true;
      if (addBubble) {
        _messages.insert(
          0,
          CopilotTranscript(text: text, isFinal: true),
        );
      }
      _error = null;
    });
    CopilotFeedback? feedback;
    try {
      feedback = await widget.onSubmit(text);
    } catch (error) {
      feedback = CopilotFeedback(
        message: error.toString(),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
    if (feedback != null && mounted) {
      final CopilotFeedback result = feedback;
      setState(() {
        _messages.insert(
          0,
          CopilotTranscript(
            text: result.message,
            isFinal: true,
            isError: result.isError,
            isCopilot: true,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'LogAI',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (!_online)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text('Hors ligne'),
                      backgroundColor: Color(0xFFFFF1DC),
                    ),
                  ),
                ValueListenableBuilder<bool>(
                  valueListenable: widget.service.isListening,
                  builder: (context, listening, _) {
                    return FilledButton.icon(
                      onPressed: _online ? _toggleListen : null,
                      icon: Icon(listening ? Icons.stop : Icons.mic),
                      label: Text(listening ? 'Arrêter' : 'Parler'),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (_messages.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: ListView.builder(
                  reverse: true,
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Align(
                        alignment: msg.isCopilot
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: msg.isError
                                ? Colors.red.shade100
                                : msg.isCopilot
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.12)
                                    : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            msg.text,
                            style: TextStyle(
                              color: msg.isError ? Colors.red : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              decoration: InputDecoration(
                labelText: 'Commande',
                helperText: _online
                    ? 'Décris ce que tu veux accomplir.'
                    : 'Saisie manuelle disponible hors ligne.',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _submitting ? null : _handleSubmit,
                ),
              ),
              enabled: !_submitting,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSubmit(),
            ),
            if (_submitting) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../theme/app_theme.dart';

/// AI chat sidebar — canned responses, no real LLM. Mirrors the wireframe
/// behavior: keyword-matched replies + 3 quick-action prompt chips.
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.messages,
    required this.onSend,
    required this.enabled,
    required this.onToggle,
  });

  final List<ChatMessage> messages;
  final ValueChanged<String> onSend;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _ctrl = TextEditingController();

  void _send([String? override]) {
    final text = (override ?? _ctrl.text).trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border.all(color: rt.hair),
        borderRadius: RecipeRadius.cardBR,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('AI assistant',
              style: RecipeTypography.serif(size: 17, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.17)),
          const Spacer(),
          Switch(
            value: widget.enabled,
            onChanged: widget.onToggle,
            activeThumbColor: rt.accent,
          ),
        ]),
        const SizedBox(height: 8),
        if (!widget.enabled)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'AI is off — build manually with the calendar and candidates.',
              style: TextStyle(fontSize: 13, color: rt.ink3),
            ),
          )
        else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                children: [
                  for (final m in widget.messages) _Bubble(message: m),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final q in const [
              'Plan the whole week',
              'Suggest 3 candidates',
              'Build grocery list',
            ])
              _Chip(label: q, onTap: () => _send(q)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Ask the assistant…',
                  hintStyle: TextStyle(color: rt.ink3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
                  enabledBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
                  focusedBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.accent)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _send,
              icon: Icon(Icons.send, size: 18, color: rt.accent),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final isUser = message.who == ChatWho.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isUser ? rt.ink : rt.paper2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                color: isUser ? rt.paper : rt.ink2,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: rt.paper,
          border: Border.all(color: rt.hair),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: rt.ink2, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

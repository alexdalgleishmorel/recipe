import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/share_item.dart';
import '../../services/repositories.dart';
import '../../theme/app_theme.dart';
import '../buttons.dart';
import '../modal_shell.dart';
import '../toast.dart';

/// Share a recipe or collection as an editable COPY (fork). Two targeting
/// modes: enter a recipient email, or copy a shareable link. Mirrors the
/// styling of the other modals (`ModalShell` + field tokens).
Future<void> openShareModal(
  BuildContext context, {
  required ShareItem item,
  required SharingRepository sharingRepo,
}) async {
  await showRecipeModal<void>(
    context: context,
    builder: (ctx) => _ShareModalBody(item: item, sharingRepo: sharingRepo),
  );
}

class _ShareModalBody extends StatefulWidget {
  const _ShareModalBody({required this.item, required this.sharingRepo});

  final ShareItem item;
  final SharingRepository sharingRepo;

  @override
  State<_ShareModalBody> createState() => _ShareModalBodyState();
}

class _ShareModalBodyState extends State<_ShareModalBody> {
  final _emailCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  String get _kindLabel =>
      widget.item.type == ShareItemType.collection ? 'collection' : 'recipe';

  Future<void> _shareByEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showToast(context, 'Enter a valid email address');
      return;
    }
    setState(() => _sending = true);
    await widget.sharingRepo.shareByEmail(recipientEmail: email, item: widget.item);
    if (!mounted) return;
    setState(() => _sending = false);
    Navigator.of(context, rootNavigator: true).pop();
    showToast(context, 'Shared with $email');
  }

  Future<void> _copyLink() async {
    final link = await widget.sharingRepo.createShareLink(widget.item);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    showToast(context, 'Link copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return ModalShell(
      title: 'Share $_kindLabel',
      subtitle:
          'Sends an editable copy of "${widget.item.title}". The recipient gets their own independent fork.',
      actions: [
        const CancelButton(),
        Btn(
          label: _sending ? 'Sharing…' : 'Share',
          variant: BtnVariant.primary,
          onPressed: _sending ? null : _shareByEmail,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MonoLabel('Share to email'),
          const SizedBox(height: 8),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            onSubmitted: (_) => _shareByEmail(),
            style: TextStyle(fontSize: 14, color: rt.ink),
            decoration: InputDecoration(
              hintText: 'name@example.com',
              hintStyle: TextStyle(color: rt.ink3, fontSize: 14),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
              enabledBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
              focusedBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.accent)),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Divider(color: rt.hair, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('OR', style: RecipeTypography.mono(size: 10.5, color: rt.ink3, letterSpacing: 0.84)),
            ),
            Expanded(child: Divider(color: rt.hair, height: 1)),
          ]),
          const SizedBox(height: 18),
          MonoLabel('Shareable link'),
          const SizedBox(height: 8),
          Text(
            'Anyone with the link can add a copy to their own library.',
            style: TextStyle(fontSize: 12.5, color: rt.ink3, height: 1.4),
          ),
          const SizedBox(height: 10),
          Btn(
            label: 'Copy link',
            icon: Icons.link,
            onPressed: _copyLink,
          ),
        ],
      ),
    );
  }
}

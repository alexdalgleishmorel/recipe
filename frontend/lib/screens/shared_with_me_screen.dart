import 'package:flutter/material.dart';

import '../models/incoming_share.dart';
import '../models/share_item.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/page_head.dart';
import '../widgets/toast.dart';

/// Inbox of items shared with the current user. Claiming forks an independent
/// copy into the user's library, then triggers the shell's `onChanged` refetch
/// so the new recipe/collection appears in Browse / Collections.
class SharedWithMeScreen extends StatefulWidget {
  const SharedWithMeScreen({
    super.key,
    required this.sharingRepo,
    required this.onChanged,
  });

  final SharingRepository sharingRepo;
  final Future<void> Function() onChanged;

  @override
  State<SharedWithMeScreen> createState() => _SharedWithMeScreenState();
}

class _SharedWithMeScreenState extends State<SharedWithMeScreen> {
  List<IncomingShare> _shares = const [];
  bool _loading = true;
  String? _claimingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shares = await widget.sharingRepo.listIncoming();
    if (!mounted) return;
    setState(() {
      _shares = shares;
      _loading = false;
    });
  }

  Future<void> _claim(IncomingShare share) async {
    setState(() => _claimingId = share.id);
    await widget.sharingRepo.claim(share.id);
    await widget.onChanged();
    if (!mounted) return;
    setState(() => _claimingId = null);
    await _load();
    if (!mounted) return;
    showToast(context, 'Added "${share.item.title}" to your library');
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final pending = _shares.where((s) => !s.claimed).toList();
    final claimed = _shares.where((s) => s.claimed).toList();

    return Scaffold(
      backgroundColor: rt.paper,
      body: ContentScroll(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHead(
              title: 'Shared with me',
              subtitle: 'Items others shared with you. Add a copy to your library — it becomes yours to edit.',
            ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: rt.accent),
                ),
              )
            else if (_shares.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  'Nothing shared with you yet.',
                  style: TextStyle(color: rt.ink3, fontSize: 14),
                ),
              )
            else ...[
              for (final s in pending)
                _ShareRow(
                  share: s,
                  busy: _claimingId == s.id,
                  onClaim: () => _claim(s),
                ),
              if (claimed.isNotEmpty) ...[
                const SizedBox(height: 28),
                MonoLabel('Already added'),
                const SizedBox(height: 10),
                for (final s in claimed)
                  _ShareRow(share: s, busy: false, onClaim: null),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.share, required this.busy, required this.onClaim});

  final IncomingShare share;
  final bool busy;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final isCollection = share.item.type == ShareItemType.collection;
    final from = share.fromEmail == 'link' ? 'a shared link' : share.fromEmail;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: rt.paper,
          border: Border.all(color: rt.hair),
          borderRadius: RecipeRadius.cardBR,
        ),
        child: Row(
          children: [
            Icon(
              isCollection ? Icons.folder_outlined : Icons.restaurant_menu_outlined,
              size: 20,
              color: rt.ink3,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    share.item.title.isEmpty ? '(untitled $from)' : share.item.title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: rt.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${isCollection ? 'Collection' : 'Recipe'} · from $from',
                    style: TextStyle(fontSize: 12.5, color: rt.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (share.claimed)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check, size: 15, color: rt.ok),
                const SizedBox(width: 6),
                Text('Added', style: TextStyle(fontSize: 13, color: rt.ok, fontWeight: FontWeight.w500)),
              ])
            else
              Btn(
                label: busy ? 'Adding…' : 'Add to my library',
                icon: Icons.add,
                variant: BtnVariant.primary,
                size: BtnSize.sm,
                onPressed: busy ? null : onClaim,
              ),
          ],
        ),
      ),
    );
  }
}

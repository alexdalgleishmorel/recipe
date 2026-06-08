import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/page_head.dart';
import '../widgets/toast.dart';

/// Admin-only roster of all accounts, each with a toggle for the AI-import
/// entitlement (#6). Loads via [AdminRepository.listUsers]; flipping a toggle
/// calls [AdminRepository.setEntitlement] and replaces the row with the
/// server's updated user.
///
/// Reached from the account UI (shown only when the signed-in user is an
/// admin). Loading / empty / error states are handled inline so the page
/// never hangs on a permanent spinner.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, required this.adminRepo});

  final AdminRepository adminRepo;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<User> _users = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await widget.adminRepo.listUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setEntitlement(User user, bool value) async {
    setState(() => _saving.add(user.id));
    try {
      final updated = await widget.adminRepo.setEntitlement(user.id, value);
      if (!mounted) return;
      setState(() {
        _users = [
          for (final u in _users) u.id == updated.id ? updated : u,
        ];
        _saving.remove(user.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving.remove(user.id));
      showToast(context, 'Could not update ${user.displayName}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Scaffold(
      backgroundColor: rt.paper,
      appBar: AppBar(
        backgroundColor: rt.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: rt.ink2),
        leading: const BackButton(),
      ),
      body: ContentScroll(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHead(
              title: 'Manage users',
              subtitle:
                  'Enable or disable AI-assisted import for each account.',
            ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: rt.accent,
                  ),
                ),
              )
            else if (_error != null)
              _ErrorState(message: _error!, onRetry: _load)
            else if (_users.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  'No users found.',
                  style: TextStyle(color: rt.ink3, fontSize: 14),
                ),
              )
            else
              for (final u in _users)
                _UserRow(
                  user: u,
                  saving: _saving.contains(u.id),
                  onChanged: (v) => _setEntitlement(u, v),
                ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Could not load users',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: rt.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(fontSize: 13, color: rt.ink3, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.saving,
    required this.onChanged,
  });

  final User user;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayName.isEmpty
                              ? user.email
                              : user.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: rt.ink,
                          ),
                        ),
                      ),
                      if (user.isAdmin) ...[
                        const SizedBox(width: 8),
                        _AdminBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.email,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: rt.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'AI IMPORT',
              style: RecipeTypography.mono(
                size: 10,
                weight: FontWeight.w400,
                color: rt.ink3,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 10),
            _Toggle(
              value: user.canAiImport,
              busy: saving,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: rt.accentSoft,
        borderRadius: RecipeRadius.chipBR,
      ),
      child: Text(
        'ADMIN',
        style: RecipeTypography.mono(
          size: 9,
          weight: FontWeight.w500,
          color: rt.accentInk,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Pill switch mirroring the admin AI toggle styling used elsewhere. While a
/// save is in flight it shows a small spinner and ignores taps.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    if (busy) {
      return SizedBox(
        width: 34,
        height: 18,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: rt.accent),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: RecipeRadius.chipBR,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 34,
        height: 18,
        decoration: BoxDecoration(
          color: value ? rt.accent : rt.hair,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: rt.hair2),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              left: value ? 16 : 1,
              top: 0,
              child: Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: rt.paper,
                  shape: BoxShape.circle,
                  border: Border.all(color: rt.hair2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

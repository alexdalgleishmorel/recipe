import 'share_item.dart';

/// A share that has arrived in the current user's "Shared with me" inbox.
/// Locally these are synthesized by [LocalSharingRepository]; with a real
/// backend (#24) they come from cross-user delivery.
class IncomingShare {
  IncomingShare({
    required this.id,
    required this.item,
    required this.fromEmail,
    required this.sharedAt,
    this.token,
    this.claimed = false,
  });

  final String id;
  final ShareItem item;

  /// Email of the person who shared the item ("Me" / link shares use the
  /// current user's email or a synthetic value).
  final String fromEmail;
  final DateTime sharedAt;

  /// Present when the share originated from a shareable link.
  final String? token;
  final bool claimed;

  IncomingShare copyWith({
    String? id,
    ShareItem? item,
    String? fromEmail,
    DateTime? sharedAt,
    String? token,
    bool? claimed,
  }) =>
      IncomingShare(
        id: id ?? this.id,
        item: item ?? this.item,
        fromEmail: fromEmail ?? this.fromEmail,
        sharedAt: sharedAt ?? this.sharedAt,
        token: token ?? this.token,
        claimed: claimed ?? this.claimed,
      );

  factory IncomingShare.fromJson(Map<String, dynamic> j) => IncomingShare(
        id: j['id'] as String,
        item: ShareItem.fromJson(j['item'] as Map<String, dynamic>),
        fromEmail: (j['fromEmail'] ?? '') as String,
        sharedAt: DateTime.tryParse((j['sharedAt'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        token: j['token'] as String?,
        claimed: (j['claimed'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'item': item.toJson(),
        'fromEmail': fromEmail,
        'sharedAt': sharedAt.toIso8601String(),
        'token': token,
        'claimed': claimed,
      };
}

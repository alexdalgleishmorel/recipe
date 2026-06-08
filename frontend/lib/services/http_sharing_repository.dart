import '../models/incoming_share.dart';
import '../models/share_item.dart';
import 'http_api_client.dart';
import 'repositories.dart';

/// Live-backend implementation of [SharingRepository] against `/shares` (#18).
///
/// Unlike [LocalSharingRepository], delivery and the fork are the server's job:
/// each share snapshots the item at share time, and [claim] deep-copies that
/// snapshot into the caller's library with fresh ids. The UI then refetches
/// recipes/collections via its existing `onChanged` callbacks.
///
/// The backend's share record is flat (`itemType`, `itemId`, `snapshot.title`)
/// whereas the frontend models nest the pointer in a [ShareItem]; this repo
/// bridges the two so [IncomingShare] / [ShareItem] stay unchanged.
class HttpSharingRepository implements SharingRepository {
  HttpSharingRepository(this._api);

  final HttpApiClient _api;

  @override
  Future<void> shareByEmail({
    required String recipientEmail,
    required ShareItem item,
  }) async {
    await _api.postJson('/shares', {
      'itemType': shareItemTypeToString(item.type),
      'itemId': item.id,
      'target': {'email': recipientEmail},
    });
  }

  @override
  Future<String> createShareLink(ShareItem item) async {
    final data = await _api.postJson('/shares', {
      'itemType': shareItemTypeToString(item.type),
      'itemId': item.id,
      'target': {'link': true},
    });
    final share = (data as Map).cast<String, dynamic>();
    final token = (share['token'] ?? '') as String;
    return _shareLink(token);
  }

  @override
  Future<List<IncomingShare>> listIncoming() async {
    final data = await _api.getJson('/shares/incoming');
    final list = (data as List? ?? const []);
    return list
        .map((j) => _toIncomingShare((j as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> claim(String shareId) async {
    // Server-side fork. The id is the email share's id (or a link token); the
    // backend resolves both. The result is discarded — the UI refetches its
    // library after this completes.
    await _api.postJson('/shares/$shareId/claim', const {});
  }

  /// Map a backend share record (flat `itemType` / `itemId` + `snapshot.title`)
  /// onto the nested [IncomingShare] / [ShareItem] the UI consumes.
  IncomingShare _toIncomingShare(Map<String, dynamic> j) {
    final snapshot = (j['snapshot'] as Map?)?.cast<String, dynamic>() ?? const {};
    final title = (snapshot['title'] ?? '') as String;
    return IncomingShare(
      id: (j['id'] ?? '') as String,
      item: ShareItem(
        type: shareItemTypeFromString((j['itemType'] ?? 'recipe') as String),
        id: (j['itemId'] ?? '') as String,
        title: title,
      ),
      fromEmail: (j['fromEmail'] ?? '') as String,
      sharedAt: DateTime.tryParse((j['sharedAt'] ?? '') as String) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      token: j['token'] as String?,
      claimed: (j['claimed'] as bool?) ?? false,
    );
  }

  /// Shareable URL embedding the link [token]. Mirrors [LocalSharingRepository]'s
  /// link shape so the copy-link UX is identical in both modes.
  static String _shareLink(String token) => 'https://recipes.app/share/$token';
}

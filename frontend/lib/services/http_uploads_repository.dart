import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'http_api_client.dart';
import 'repositories.dart';

/// Live-backend implementation of [UploadsRepository] (#80).
///
/// Two-step flow:
///  1. `POST /uploads/presign {contentType}` (authenticated via [HttpApiClient])
///     → `{uploadUrl, key, publicUrl}`.
///  2. `PUT <uploadUrl>` with the raw bytes and a matching `Content-Type`
///     header, and crucially **no `Authorization` header** — the presigned URL
///     already carries the signature, and the signed `Content-Type` must match
///     exactly or the upload is rejected.
///
/// On success the object is served at `publicUrl`, which the caller stores in
/// `recipe.image`.
class HttpUploadsRepository implements UploadsRepository {
  HttpUploadsRepository(this._api, {http.Client? client})
      : _client = client ?? http.Client();

  final HttpApiClient _api;
  final http.Client _client;

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final presign = await _api.postJson('/uploads/presign', {
      'contentType': contentType,
    });
    if (presign is! Map<String, dynamic>) {
      throw http.ClientException('Presign returned an unexpected response.');
    }
    final uploadUrl = presign['uploadUrl'] as String?;
    final publicUrl = presign['publicUrl'] as String?;
    if (uploadUrl == null || uploadUrl.isEmpty || publicUrl == null || publicUrl.isEmpty) {
      throw http.ClientException('Presign response was missing a URL.');
    }

    // Plain PUT to the presigned URL — no auth header, Content-Type must match
    // what was signed.
    final res = await _client.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw http.ClientException(
        'Image upload failed (${res.statusCode}): ${res.body}',
      );
    }

    return publicUrl;
  }
}

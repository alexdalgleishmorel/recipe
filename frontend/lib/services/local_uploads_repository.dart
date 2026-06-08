import 'dart:convert';
import 'dart:typed_data';

import 'repositories.dart';

/// Default (no-backend) implementation of [UploadsRepository] (#80).
///
/// There is nowhere to upload to in mocked mode, so we encode the bytes as a
/// `data:` URL. `RecipeImage` renders it via `Image.network`, so picked photos
/// still display locally without a server.
class LocalUploadsRepository implements UploadsRepository {
  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String contentType,
  }) async {
    return 'data:$contentType;base64,${base64Encode(bytes)}';
  }
}

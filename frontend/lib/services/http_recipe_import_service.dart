import 'dart:convert';
import 'dart:typed_data';

import '../models/recipe.dart';
import 'http_api_client.dart';
import 'repositories.dart';

/// Thrown when AI import fails in a way the UI should message specifically.
/// In particular [notEntitled] is true when the backend rejects the request
/// with 403 because the account lacks the `canAiImport` entitlement (#6).
class RecipeImportException implements Exception {
  RecipeImportException(this.message, {this.notEntitled = false});

  final String message;

  /// True when the server returned 403 (the account is not entitled to AI
  /// import). The UI uses this to show "AI import isn't enabled for your
  /// account" instead of a generic parse error.
  final bool notEntitled;

  @override
  String toString() => 'RecipeImportException: $message';
}

/// Real AI-assisted import (#19/#25). Sends the picked file inline to the
/// Anthropic-backed Lambda at `POST /recipes/import` and turns the returned
/// draft JSON into a [Recipe] the user reviews before saving.
///
/// The request shape matches the backend handler
/// (`backend/functions/import_recipe/import_recipe.py`):
/// `{contentBase64, contentType, filename}`. The response is a Recipe draft
/// with no `id` (the server assigns one on save), so we stamp the same
/// `'staging'` id the review screen expects.
class HttpRecipeImportService implements RecipeImportService {
  HttpRecipeImportService(this._api);

  final HttpApiClient _api;

  @override
  Future<Recipe> parse({
    required Uint8List bytes,
    required String filename,
  }) async {
    final body = <String, dynamic>{
      'contentBase64': base64Encode(bytes),
      'contentType': _contentTypeFor(filename),
      'filename': filename,
    };

    final dynamic json;
    try {
      json = await _api.postJson('/recipes/import', body, auth403: false);
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        throw RecipeImportException(
          "AI import isn't enabled for your account.",
          notEntitled: true,
        );
      }
      rethrow;
    }

    if (json is! Map<String, dynamic>) {
      throw RecipeImportException('The server returned an unexpected response.');
    }
    // The draft has no id; the review screen and the local stub both use
    // 'staging' until the recipe is saved.
    return Recipe.fromJson({'id': 'staging', ...json});
  }

  /// Infer the request content type from the filename extension. Mirrors the
  /// backend's accepted types (image/* or application/pdf); defaults to
  /// `image/jpeg` for unknown extensions.
  String _contentTypeFor(String filename) {
    final dot = filename.lastIndexOf('.');
    final ext = dot >= 0 ? filename.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'image/jpeg';
    }
  }
}

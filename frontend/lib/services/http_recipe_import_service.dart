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

/// Infer the request content type from a filename extension. Mirrors the
/// backend's accepted types: `application/json` for `.json`, `image/*` for
/// images, `application/pdf` for PDFs; defaults to `image/jpeg` for unknown
/// extensions.
String contentTypeForFilename(String filename) {
  final dot = filename.lastIndexOf('.');
  final ext = dot >= 0 ? filename.substring(dot + 1).toLowerCase() : '';
  switch (ext) {
    case 'json':
      return 'application/json';
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

/// Real AI-assisted import (#19/#25/#77). Sends one or more picked files inline
/// to the Anthropic-backed Lambda at `POST /recipes/import` and turns the
/// returned draft JSON into [Recipe]s the user reviews before saving.
///
/// The multi request shape matches the backend handler (#76):
/// `{"files":[{"contentBase64","contentType","filename"}, ...]}` →
/// `{"results":[{"filename","ok":true,"tier","draft":{...}} | {"filename",
/// "ok":false,"error"}]}`. Each draft has no `id` (the server assigns one on
/// save), so we stamp the `'staging'` id the review screen expects.
class HttpRecipeImportService implements RecipeImportService {
  HttpRecipeImportService(this._api);

  final HttpApiClient _api;

  @override
  Future<Recipe> parse({
    required Uint8List bytes,
    required String filename,
  }) async {
    final results = await parseAll([
      RecipeImportFile(
        bytes: bytes,
        filename: filename,
        contentType: contentTypeForFilename(filename),
      ),
    ]);
    final result = results.first;
    final draft = result.draft;
    if (draft == null) {
      throw RecipeImportException(result.error ?? 'Could not parse that file');
    }
    return draft;
  }

  @override
  Future<List<RecipeImportResult>> parseAll(
    List<RecipeImportFile> files,
  ) async {
    final body = <String, dynamic>{
      'files': [
        for (final f in files)
          {
            'contentBase64': base64Encode(f.bytes),
            'contentType': f.contentType,
            'filename': f.filename,
          },
      ],
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
    final results = json['results'];
    if (results is! List) {
      throw RecipeImportException('The server returned an unexpected response.');
    }

    return results.map<RecipeImportResult>((dynamic raw) {
      final entry = raw as Map<String, dynamic>;
      final filename = (entry['filename'] ?? '') as String;
      final ok = entry['ok'] == true;
      if (!ok) {
        return RecipeImportResult(
          filename: filename,
          error: (entry['error'] as String?) ?? 'Could not parse that file',
        );
      }
      final draftJson = entry['draft'];
      if (draftJson is! Map<String, dynamic>) {
        return RecipeImportResult(
          filename: filename,
          error: 'The server returned an unexpected draft.',
        );
      }
      return RecipeImportResult(
        filename: filename,
        tier: entry['tier'] as String?,
        draft: Recipe.fromJson({'id': 'staging', ...draftJson}),
      );
    }).toList();
  }
}

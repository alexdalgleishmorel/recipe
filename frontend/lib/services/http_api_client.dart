import 'dart:convert';

import 'package:http/http.dart' as http;

/// Supplies the Cognito **id_token** for API authentication. Returns null when
/// there is no signed-in session. Typically wired to
/// `CognitoAuthRepository.currentIdToken`.
typedef AuthTokenProvider = Future<String?> Function();

/// Thrown when the backend rejects a request because the caller is not (or no
/// longer) authenticated. The auth gate treats this as a signal to send the
/// user back to login.
class ApiAuthException implements Exception {
  ApiAuthException([this.message = 'Authentication required.']);
  final String message;
  @override
  String toString() => 'ApiAuthException: $message';
}

/// Thrown for non-2xx responses other than 401.
class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'ApiException($statusCode): $body';
}

/// Thin authenticated JSON client shared by the `Http*` repositories. Each
/// request carries `Authorization: Bearer <id_token>`; a missing token or a
/// 401 surfaces as [ApiAuthException].
class HttpApiClient {
  HttpApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// API origin, e.g. `https://...execute-api.us-east-1.amazonaws.com`. A
  /// trailing slash is tolerated.
  final String baseUrl;
  final AuthTokenProvider tokenProvider;
  final http.Client _client;

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base$path');
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw ApiAuthException();
    }
    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  /// GET [path] and decode the JSON body. Returns `null` for a 404.
  Future<dynamic> getJson(String path) async {
    final res = await _client.get(_uri(path), headers: await _headers());
    return _decode(res, allow404: true);
  }

  /// POST [body] to [path] and decode the JSON response.
  ///
  /// By default a 403 is treated as an auth failure ([ApiAuthException]) like a
  /// 401. Set [auth403] to false when 403 is a meaningful application response
  /// the caller wants to handle itself (e.g. the import endpoint's
  /// not-entitled signal), in which case it surfaces as [ApiException].
  Future<dynamic> postJson(
    String path,
    Map<String, dynamic> body, {
    bool auth403 = true,
  }) async {
    final res = await _client.post(
      _uri(path),
      headers: await _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(res, auth403: auth403);
  }

  /// PUT [body] to [path] and decode the JSON response.
  Future<dynamic> putJson(String path, Map<String, dynamic> body) async {
    final res = await _client.put(
      _uri(path),
      headers: await _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  /// DELETE [path].
  Future<void> delete(String path) async {
    final res = await _client.delete(_uri(path), headers: await _headers());
    _decode(res, allow404: true);
  }

  dynamic _decode(http.Response res, {bool allow404 = false, bool auth403 = true}) {
    if (res.statusCode == 401 || (auth403 && res.statusCode == 403)) {
      throw ApiAuthException('Session expired or unauthorized.');
    }
    if (allow404 && res.statusCode == 404) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import '../models/user.dart';
import 'repositories.dart';

/// Real Cognito Hosted UI auth (Google only) over OAuth2 authorization-code +
/// PKCE, targeting Flutter **web**.
///
/// This is the production counterpart to [LocalAuthRepository] and implements
/// the exact same [AuthRepository] interface, so it can be swapped in via a
/// single line in `main.dart` (done separately in #23). This file is purely
/// additive and does not wire itself into the app.
///
/// Flow:
///  - [signInWithGoogle] redirects the browser to the Hosted UI authorize
///    endpoint with a freshly generated PKCE verifier/challenge + state.
///  - [currentUser] completes the redirect (exchanges `?code=` for tokens),
///    or — if a valid id_token is already stored — calls `GET /me` for the
///    authoritative profile (refreshing once on 401 when possible).
///  - [signOut] clears tokens (and best-effort hits the Hosted UI `/logout`).
///
/// Config is read via `--dart-define` with sensible defaults matching the
/// deployed stack.
class CognitoAuthRepository implements AuthRepository {
  CognitoAuthRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  // --- Config (overridable via --dart-define) ----------------------------

  static const String _domain = String.fromEnvironment(
    'COGNITO_DOMAIN',
    defaultValue:
        'https://recipe-app-696532327395.auth.us-east-1.amazoncognito.com',
  );

  static const String _clientId = String.fromEnvironment(
    'COGNITO_APP_CLIENT_ID',
    defaultValue: '4ku57vil6t0b2bapno4ju887th',
  );

  // Retained for parity with config/other impls; not needed for Hosted UI.
  // ignore: unused_field
  static const String _region = String.fromEnvironment(
    'COGNITO_REGION',
    defaultValue: 'us-east-1',
  );

  static const String _apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://yz0jib3efa.execute-api.us-east-1.amazonaws.com',
  );

  /// Explicit redirect URI override; when empty we derive it from the current
  /// browser origin (so localhost dev + GitHub Pages both work).
  static const String _redirectUriOverride = String.fromEnvironment(
    'OAUTH_REDIRECT_URI',
    defaultValue: '',
  );

  // --- Storage keys -------------------------------------------------------

  static const _kIdToken = 'auth.cognito.idToken';
  static const _kAccessToken = 'auth.cognito.accessToken';
  static const _kRefreshToken = 'auth.cognito.refreshToken';
  static const _kExpiresAt = 'auth.cognito.expiresAtMs';
  static const _kVerifier = 'auth.cognito.pkceVerifier';
  static const _kState = 'auth.cognito.oauthState';

  // -----------------------------------------------------------------------

  String get _redirectUri {
    if (_redirectUriOverride.isNotEmpty) return _redirectUriOverride;
    if (kIsWeb) {
      // Strip any query/hash; keep origin + path (e.g. GitHub Pages subpath).
      final loc = web.window.location;
      return '${loc.origin}${loc.pathname}';
    }
    return 'http://localhost:8080/';
  }

  // --- AuthRepository -----------------------------------------------------

  @override
  Future<User> signInWithGoogle() async {
    if (!kIsWeb) {
      throw UnsupportedError(
        'CognitoAuthRepository sign-in is only supported on web.',
      );
    }
    final prefs = await SharedPreferences.getInstance();

    final verifier = _randomUrlSafe(64);
    final challenge = _codeChallenge(verifier);
    final state = _randomUrlSafe(24);

    await prefs.setString(_kVerifier, verifier);
    await prefs.setString(_kState, state);

    final uri = Uri.parse('$_domain/oauth2/authorize').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'scope': 'openid email profile',
        'identity_provider': 'Google',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      },
    );

    web.window.location.assign(uri.toString());

    // The browser navigates away; this future never meaningfully completes.
    // Returning a never-completing future avoids a spurious "signed out".
    return Completer<User>().future;
  }

  @override
  Future<User?> currentUser() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) Complete a pending redirect, if any.
    if (kIsWeb) {
      final completed = await _maybeCompleteRedirect(prefs);
      if (completed != null) return completed;
    }

    // 2) Use a stored token (refreshing if needed) to fetch /me.
    final idToken = prefs.getString(_kIdToken);
    if (idToken == null) return null;

    if (_isExpired(prefs)) {
      final refreshed = await _refresh(prefs);
      if (!refreshed) {
        await _clearTokens(prefs);
        return null;
      }
    }

    return _fetchMe(prefs, retryOn401: true);
  }

  @override
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearTokens(prefs);
    if (kIsWeb) {
      final logout = Uri.parse('$_domain/logout').replace(queryParameters: {
        'client_id': _clientId,
        'logout_uri': _redirectUri,
      });
      web.window.location.assign(logout.toString());
    }
  }

  /// The current Cognito **id_token**, refreshing it first if expired. Returns
  /// null when there is no stored session (or a needed refresh failed). Used by
  /// the `Http*` repositories to authenticate API calls with the same token
  /// this repository manages.
  Future<String?> currentIdToken() async {
    final prefs = await SharedPreferences.getInstance();
    final idToken = prefs.getString(_kIdToken);
    if (idToken == null) return null;
    if (_isExpired(prefs)) {
      final refreshed = await _refresh(prefs);
      if (!refreshed) return null;
      return prefs.getString(_kIdToken);
    }
    return idToken;
  }

  // --- Internals ----------------------------------------------------------

  /// If the current URL carries `?code=`, validate state, exchange the code
  /// for tokens, strip the query, and return the resulting [User]. Returns
  /// null when there is no pending redirect.
  Future<User?> _maybeCompleteRedirect(SharedPreferences prefs) async {
    final href = web.window.location.href;
    final current = Uri.parse(href);
    final code = current.queryParameters['code'];
    if (code == null) return null;

    final returnedState = current.queryParameters['state'];
    final expectedState = prefs.getString(_kState);
    final verifier = prefs.getString(_kVerifier);

    // Always strip the query so a refresh doesn't re-trigger the exchange.
    _stripQuery();

    if (verifier == null ||
        returnedState == null ||
        expectedState == null ||
        returnedState != expectedState) {
      await prefs.remove(_kState);
      await prefs.remove(_kVerifier);
      return null;
    }

    final ok = await _exchangeCode(prefs, code: code, verifier: verifier);
    await prefs.remove(_kState);
    await prefs.remove(_kVerifier);
    if (!ok) return null;

    return _fetchMe(prefs, retryOn401: true);
  }

  Future<bool> _exchangeCode(
    SharedPreferences prefs, {
    required String code,
    required String verifier,
  }) async {
    final res = await _client.post(
      Uri.parse('$_domain/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'code': code,
        'redirect_uri': _redirectUri,
        'code_verifier': verifier,
      },
    );
    if (res.statusCode != 200) return false;
    await _storeTokens(prefs, jsonDecode(res.body) as Map<String, dynamic>);
    return true;
  }

  /// Refresh the id/access tokens using the stored refresh token. Returns
  /// false when there is no refresh token or the refresh fails.
  Future<bool> _refresh(SharedPreferences prefs) async {
    final refresh = prefs.getString(_kRefreshToken);
    if (refresh == null) return false;

    final res = await _client.post(
      Uri.parse('$_domain/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': refresh,
      },
    );
    if (res.statusCode != 200) return false;
    // A refresh response typically omits refresh_token; keep the existing one.
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    await _storeTokens(prefs, body, fallbackRefresh: refresh);
    return true;
  }

  Future<User?> _fetchMe(
    SharedPreferences prefs, {
    required bool retryOn401,
  }) async {
    final token = prefs.getString(_kIdToken);
    if (token == null) return null;

    final res = await _client.get(
      Uri.parse('$_apiBase/me'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode == 401 && retryOn401) {
      if (await _refresh(prefs)) {
        return _fetchMe(prefs, retryOn401: false);
      }
      await _clearTokens(prefs);
      return null;
    }

    if (res.statusCode == 401) {
      await _clearTokens(prefs);
      return null;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw http.ClientException(
        'GET /me failed (${res.statusCode}): ${res.body}',
      );
    }

    return User.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // --- Token storage ------------------------------------------------------

  Future<void> _storeTokens(
    SharedPreferences prefs,
    Map<String, dynamic> tokens, {
    String? fallbackRefresh,
  }) async {
    final idToken = tokens['id_token'] as String?;
    final accessToken = tokens['access_token'] as String?;
    final refreshToken = (tokens['refresh_token'] as String?) ?? fallbackRefresh;
    final expiresIn = (tokens['expires_in'] as num?)?.toInt() ?? 3600;

    if (idToken != null) await prefs.setString(_kIdToken, idToken);
    if (accessToken != null) await prefs.setString(_kAccessToken, accessToken);
    if (refreshToken != null) {
      await prefs.setString(_kRefreshToken, refreshToken);
    }
    // Apply a small safety margin so we refresh slightly early.
    final expiresAt = DateTime.now().millisecondsSinceEpoch +
        (expiresIn - 30).clamp(0, expiresIn) * 1000;
    await prefs.setInt(_kExpiresAt, expiresAt);
  }

  bool _isExpired(SharedPreferences prefs) {
    final at = prefs.getInt(_kExpiresAt);
    if (at == null) return true;
    return DateTime.now().millisecondsSinceEpoch >= at;
  }

  Future<void> _clearTokens(SharedPreferences prefs) async {
    await prefs.remove(_kIdToken);
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kExpiresAt);
  }

  // --- PKCE / utils -------------------------------------------------------

  /// A random URL-safe (base64url, no padding) string derived from [byteLen]
  /// random bytes. Used for the PKCE verifier (43–128 chars) and state.
  String _randomUrlSafe(int byteLen) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteLen, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _codeChallenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  /// Replace the browser URL with origin + path (dropping the OAuth `?code`/
  /// `state` query and any fragment), without a history entry or reload.
  ///
  /// NOTE: do not use `Uri.replace(query: '', queryParameters: {})` — passing
  /// both `query` and `queryParameters` throws ArgumentError. Reconstruct from
  /// the live location instead.
  void _stripQuery() {
    final loc = web.window.location;
    web.window.history.replaceState(null, '', '${loc.origin}${loc.pathname}');
  }
}

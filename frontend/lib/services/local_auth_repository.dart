import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'repositories.dart';

/// Stub auth that persists sign-in state in shared_preferences. Both sign-in
/// methods return the same demo user so admin / AI-gated UI is exercisable
/// during development.
///
// TODO(#11/#22): replace with Cognito Hosted UI OAuth (Google + Apple).
class LocalAuthRepository implements AuthRepository {
  static const _userKey = 'auth.currentUser';

  /// Demo account used by both sign-in methods until real auth lands.
  static final User _demoUser = User(
    id: 'demo-user',
    email: 'alex.dalgleishmorel@gmail.com',
    displayName: 'Alex',
    canAiImport: true,
    isAdmin: true,
  );

  @override
  Future<User?> currentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<User> signInWithGoogle() => _signInDemo();

  @override
  Future<User> signInWithApple() => _signInDemo();

  Future<User> _signInDemo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(_demoUser.toJson()));
    return _demoUser;
  }

  @override
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }
}

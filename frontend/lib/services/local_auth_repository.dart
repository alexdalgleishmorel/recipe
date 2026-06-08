import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'repositories.dart';

/// Stub auth that persists sign-in state in shared_preferences. Sign-in
/// returns a demo user so admin / AI-gated UI is exercisable during
/// development.
///
// TODO(#11/#22): replace with Cognito Hosted UI OAuth (Google only).
class LocalAuthRepository implements AuthRepository {
  static const _userKey = 'auth.currentUser';

  /// Demo account used by sign-in until real auth lands.
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

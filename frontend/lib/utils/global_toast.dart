import 'package:flutter/material.dart';

/// Messenger key wired onto the root `MaterialApp` so code without a
/// `BuildContext` (e.g. the demo repositories) can surface a SnackBar. The
/// in-app [showToast] overlay needs a context; this is the context-free escape
/// hatch used by the read-only demo write-block.
final GlobalKey<ScaffoldMessengerState> globalMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Show a transient SnackBar from anywhere (no `BuildContext` required).
/// No-op until the [MaterialApp] is mounted with [globalMessengerKey].
void showGlobalToast(String message) {
  final messenger = globalMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
}

import 'dart:math';

final _rand = Random();

String newId(String prefix) {
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final salt = _rand.nextInt(0x7fffffff).toRadixString(36);
  return '$prefix-$ts-$salt';
}

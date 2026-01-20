import 'dart:math';

String generateShortId([int length = 4]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  final randomPart = List.generate(
    length,
    (_) => chars[rand.nextInt(chars.length)],
  ).join();
  return '${DateTime.now().millisecondsSinceEpoch}_$randomPart';
}

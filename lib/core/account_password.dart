import 'dart:math';

String generateAccountPassword({Random? random}) {
  final generator = random ?? Random.secure();
  const uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const lowercase = 'abcdefghijklmnopqrstuvwxyz';
  const special = '!@#\$%^&*';
  final length = 9 + generator.nextInt(5);
  final first = uppercase[generator.nextInt(uppercase.length)];
  final middle = List.generate(
    length - 4,
    (_) => lowercase[generator.nextInt(lowercase.length)],
  ).join();
  final symbol = special[generator.nextInt(special.length)];
  return '$first$middle${generator.nextInt(10)}${generator.nextInt(10)}$symbol';
}

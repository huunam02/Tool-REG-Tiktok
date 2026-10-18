import 'proxy_store.dart';

/// One failed automatic signup attempt of a configuration.
class SignupFailure {
  const SignupFailure({
    required this.id,
    required this.configurationId,
    required this.email,
    required this.message,
    required this.createdAt,
    this.step = '',
  });

  final int id;
  final int configurationId;
  final String email;

  /// What the TikTok screen reported when the attempt stopped.
  final String message;

  /// The signup step shown on screen at that moment, when known.
  final String step;
  final DateTime createdAt;

  static SignupFailure fromRow(Map<String, Object?> row) => SignupFailure(
    id: row['id'] as int,
    configurationId: row['configuration_id'] as int,
    email: row['email'] as String,
    message: row['message'] as String,
    step: row['step'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );
}

/// An unregistered configuration whose last automatic signup failed.
class FailedConfiguration {
  const FailedConfiguration({
    required this.configuration,
    required this.failures,
    required this.failureCount,
  });

  final SavedProxy configuration;

  /// Newest first, limited to the most recent attempts.
  final List<SignupFailure> failures;

  /// Every recorded attempt, including those not loaded in [failures].
  final int failureCount;

  SignupFailure? get latest => failures.firstOrNull;
}

/// `HH:mm dd/MM/yyyy` in local time.
String formatFailureTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = time.toLocal();
  return '${two(local.hour)}:${two(local.minute)} '
      '${two(local.day)}/${two(local.month)}/${local.year}';
}

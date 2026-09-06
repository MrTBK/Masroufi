import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Stable UUID v4 ids for all rows (sync-ready).
String newId() => _uuid.v4();

/// Simple result type for validation without exceptions in UI code.
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final String messageKey;
  const Err(this.messageKey);
}

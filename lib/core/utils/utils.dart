import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Stable UUID v4 ids for all rows (sync-ready).
String newId() => _uuid.v4();

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

/// Identity of the domain library a receipt was written into: a digest of the
/// database file the connection is open on. Moving the file makes existing
/// receipts report an identity conflict instead of matching (fail closed).
String inquiryDomainIdentity(Database db) {
  final main = db
      .select('PRAGMA database_list')
      .firstWhere((row) => row['name'] == 'main');
  final file = main['file'] as String;
  if (file.isEmpty) {
    throw StateError('in-memory domain library has no identity');
  }
  return 'inquiry-db:${sha256.convert(utf8.encode(file))}';
}

/// Read-only lookup of a generic write receipt (CR-11 §1 片 D). Writes nothing:
/// no domain rows, no change log, no approvals, no notifications.
BusinessReceiptLookupResult lookupInquiryReceipt(
  Database db,
  BusinessReceiptQuery query,
) {
  final String domain;
  try {
    domain = inquiryDomainIdentity(db);
  } on Object {
    return BusinessReceiptLookupResult.unreadable(
      'domain library identity unavailable',
    );
  }
  final List<Row> rows;
  try {
    rows = db.select('SELECT value FROM meta WHERE key=?', [
      'reg4c:${query.operationId}',
    ]);
  } on Object {
    return BusinessReceiptLookupResult.unreadable(
      'receipt table cannot be read',
    );
  }
  if (rows.isEmpty) return BusinessReceiptLookupResult.notFound();
  final BusinessOperationReceipt receipt;
  try {
    receipt = _receiptFromRecord(
      query.operationId,
      rows.single['value'] as String,
      domain,
    );
  } on Object {
    return BusinessReceiptLookupResult.unreadable(
      'receipt record does not verify',
    );
  }
  return BusinessReceiptLookupResult.verify(query: query, receipt: receipt);
}

/// Rebuilds the proof from the stored record. Anything missing or inconsistent
/// throws, so the caller reports `unreadable`, never `notFound`.
BusinessOperationReceipt _receiptFromRecord(
  String operationId,
  String value,
  String domain,
) {
  final record = jsonDecode(value) as Map<String, Object?>;
  final arguments = record['arguments'] as String;
  final committed = record['result'] as Map<String, Object?>;
  if (committed['status'] != ToolCallStatus.succeeded.name) {
    throw const FormatException('receipt is not a committed success');
  }
  final args = jsonDecode(arguments) as Map<String, Object?>;
  final operation = args['operation'] as String;
  // Legacy reg4c rows have no schema tag. Accept only the explicit single
  // record schema emitted by the four generic write operations.
  if (!const {
    'create_record',
    'update_record',
    'delete_record',
    'restore_record',
  }.contains(operation)) {
    throw const FormatException('unsupported receipt operation');
  }
  final scopeKey = args['scope'] as String;
  final parameters = args['parameters'] as Map<String, Object?>;
  if (scopeKey.trim().isEmpty || parameters['operation_id'] != operationId) {
    throw const FormatException('receipt request identity is incomplete');
  }
  final data = committed['data'] as Map<String, Object?>;
  if (data['operation_id'] != operationId) {
    throw const FormatException('receipt belongs to another operation');
  }
  final type = data['type'] as String;
  final id = data['id'] as String;
  final version = data['version'];
  final deleted = data['deleted'];
  final creating = operation == 'create_record';
  final expectedVersion = parameters['expected_version'];
  if (!const {
        'supplier',
        'contact',
        'product',
        'project',
        'project_item',
        'inquiry',
        'quotation',
      }.contains(type) ||
      id.trim().isEmpty ||
      parameters['type'] != type ||
      (!creating && parameters['id'] != id) ||
      version is! int ||
      version < 1 ||
      deleted is! bool ||
      deleted != (operation == 'delete_record') ||
      (creating
          ? version != 1
          : expectedVersion is! int ||
                expectedVersion < 1 ||
                version != expectedVersion + 1)) {
    throw const FormatException('receipt result does not verify its request');
  }
  final refs = (committed['objectRefs'] as List).cast<Map<String, Object?>>();
  // Legacy compatibility (CR-11 §4): the single record reference must agree
  // with the data. Any other reference set is not a modified-object list.
  if (refs.length != 1 ||
      refs.single['moduleId'] != 'inquiry' ||
      refs.single['objectType'] != type ||
      refs.single['objectId'] != id ||
      refs.single['revisionRef'] != '$version') {
    throw const FormatException('record reference does not match its data');
  }
  return BusinessOperationReceipt(
    operationId: operationId,
    moduleId: 'inquiry',
    requestDigest: sha256.convert(utf8.encode(arguments)).toString(),
    toolId: 'inquiry.$operation',
    scopeDigest: sha256.convert(utf8.encode(scopeKey)).toString(),
    domainIdentity: domain,
    applied: true,
    resultData: {
      'type': type,
      'id': id,
      'version': version,
      'deleted': deleted,
    },
  );
}

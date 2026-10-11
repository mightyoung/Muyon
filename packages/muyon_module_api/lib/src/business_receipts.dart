import 'package:flutter/foundation.dart';

import 'context.dart';

void _requireText(String value, String what) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, what, 'must not be empty');
  }
}

/// What a lookup is asked to prove. Every part is required: a lookup by
/// operation id alone cannot tell a reuse of the id with other content from
/// the original write (CR-11 §1, §5 A).
class BusinessReceiptQuery {
  BusinessReceiptQuery({
    required this.operationId,
    required this.requestDigest,
    required this.toolId,
    required this.scopeDigest,
    required this.domainIdentity,
  }) {
    _requireText(operationId, 'operationId');
    _requireText(requestDigest, 'requestDigest');
    _requireText(toolId, 'toolId');
    _requireText(scopeDigest, 'scopeDigest');
    _requireText(domainIdentity, 'domainIdentity');
  }

  final String operationId;

  /// Digest of the original request (arguments as originally submitted).
  final String requestDigest;
  final String toolId;

  /// Digest of the resolved scope the write was made under.
  final String scopeDigest;

  /// Identity of the domain library the write committed to.
  final String domainIdentity;
}

/// The stored record of one business operation. A receipt without its full
/// identity cannot be constructed, so it can never be taken as evidence.
class BusinessOperationReceipt {
  BusinessOperationReceipt({
    required this.operationId,
    required this.moduleId,
    required this.requestDigest,
    required this.toolId,
    required this.scopeDigest,
    required this.domainIdentity,
    required this.applied,
    Map<String, Object?> resultData = const {},
  }) : resultData = freezeJsonMap(resultData) {
    _requireText(operationId, 'operationId');
    _requireText(moduleId, 'moduleId');
    _requireText(requestDigest, 'requestDigest');
    _requireText(toolId, 'toolId');
    _requireText(scopeDigest, 'scopeDigest');
    _requireText(domainIdentity, 'domainIdentity');
  }

  final String operationId, moduleId, requestDigest, toolId, scopeDigest;
  final String domainIdentity;

  /// Whether the domain write actually committed. `false` is evidence of
  /// nothing committed under this id, not of success.
  final bool applied;
  final Map<String, Object?> resultData;

  @override
  bool operator ==(Object other) =>
      other is BusinessOperationReceipt &&
      other.operationId == operationId &&
      other.moduleId == moduleId &&
      other.requestDigest == requestDigest &&
      other.toolId == toolId &&
      other.scopeDigest == scopeDigest &&
      other.domainIdentity == domainIdentity &&
      other.applied == applied &&
      mapEquals(other.resultData, resultData);

  @override
  int get hashCode => Object.hash(
    operationId,
    moduleId,
    requestDigest,
    toolId,
    scopeDigest,
    domainIdentity,
    applied,
  );
}

/// Five outcomes, and only [matched] is evidence of success.
enum BusinessReceiptStatus {
  /// Same identity as the query, and the domain write is proven applied.
  matched,

  /// The id exists but was used with other content, scope, tool or library.
  identityConflict,

  /// No record for this id; this does not prove the operation did not run.
  notFound,

  /// A record exists but cannot be read or does not verify.
  unreadable,

  /// Cannot establish the outcome, e.g. the original call is still running.
  unknown,
}

class BusinessReceiptLookupResult {
  BusinessReceiptLookupResult.matched(BusinessOperationReceipt receipt)
    : status = BusinessReceiptStatus.matched,
      receipt = receipt,
      reason = null {
    if (!receipt.applied) {
      throw ArgumentError('a matched receipt must prove the operation applied');
    }
  }

  BusinessReceiptLookupResult.identityConflict(String reason)
    : status = BusinessReceiptStatus.identityConflict,
      receipt = null,
      reason = _reason(reason);

  BusinessReceiptLookupResult.notFound()
    : status = BusinessReceiptStatus.notFound,
      receipt = null,
      reason = null;

  BusinessReceiptLookupResult.unreadable(String reason)
    : status = BusinessReceiptStatus.unreadable,
      receipt = null,
      reason = _reason(reason);

  BusinessReceiptLookupResult.unknown(String reason)
    : status = BusinessReceiptStatus.unknown,
      receipt = null,
      reason = _reason(reason);

  /// Compares the stored record with the query, part by part. Any mismatch is
  /// an identity conflict; a receipt that does not prove application is
  /// unknown, never success.
  static BusinessReceiptLookupResult verify({
    required BusinessReceiptQuery query,
    required BusinessOperationReceipt receipt,
  }) {
    final mismatched = <String>[
      if (receipt.operationId != query.operationId) 'operation id',
      if (receipt.requestDigest != query.requestDigest) 'request digest',
      if (receipt.toolId != query.toolId) 'tool',
      if (receipt.scopeDigest != query.scopeDigest) 'scope',
      if (receipt.domainIdentity != query.domainIdentity) 'domain library',
    ];
    if (mismatched.isNotEmpty) {
      return BusinessReceiptLookupResult.identityConflict(
        'same operation id, different ${mismatched.join(', ')}',
      );
    }
    if (!receipt.applied) {
      return BusinessReceiptLookupResult.unknown(
        'record does not prove the operation applied',
      );
    }
    return BusinessReceiptLookupResult.matched(receipt);
  }

  final BusinessReceiptStatus status;
  final BusinessOperationReceipt? receipt;
  final String? reason;

  /// Only a matched result is success. Applied-ness is enforced at
  /// construction, so a matched result is proven by construction.
  bool get succeeded => status == BusinessReceiptStatus.matched;

  static String? _reason(String value) {
    _requireText(value, 'reason');
    return value;
  }
}

/// Declared by `ModuleFeature.businessReceipts` (ADR-0004 §4.5, W4). Separate
/// from `ImportCapable.receipt`: write-card operation ids are not import ids.
abstract interface class BusinessReceiptLookup {
  /// Read-only. Must not write, approve, or re-run the operation.
  Future<BusinessReceiptLookupResult> lookupBusinessReceipt(
    BusinessReceiptQuery query,
  );
}

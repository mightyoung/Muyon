import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// Minimal implementers: the compliance checks only look at declared
/// features and at which interfaces the object implements.
final class _WriteModule implements WriteFormCapable {
  _WriteModule(this.writeForms);
  @override
  final List<ObjectWriteForm> writeForms;

  @override
  Future<WriteValidationResult> validateDraft(WriteDraft draft) async =>
      WriteValidationResult.ok(normalized: const {});
}

final class _ReceiptModule implements BusinessReceiptLookup {
  @override
  Future<BusinessReceiptLookupResult> lookupBusinessReceipt(
    BusinessReceiptQuery query,
  ) async => BusinessReceiptLookupResult.notFound();
}

final class _BothModule implements WriteFormCapable, BusinessReceiptLookup {
  _BothModule(this.writeForms);
  @override
  final List<ObjectWriteForm> writeForms;

  @override
  Future<WriteValidationResult> validateDraft(WriteDraft draft) async =>
      WriteValidationResult.ok(normalized: const {});

  @override
  Future<BusinessReceiptLookupResult> lookupBusinessReceipt(
    BusinessReceiptQuery query,
  ) async => BusinessReceiptLookupResult.notFound();
}

final class _BatchModule implements WriteFormCapable, AtomicBatchWriteCapable {
  _BatchModule(this.writeForms, this.atomicBatchForms);
  @override
  final List<ObjectWriteForm> writeForms;
  @override
  final List<AtomicBatchForm> atomicBatchForms;

  @override
  Future<WriteValidationResult> validateDraft(WriteDraft draft) async =>
      WriteValidationResult.ok(normalized: const {});
}

final class _BatchOnly implements AtomicBatchWriteCapable {
  _BatchOnly(this.atomicBatchForms);
  @override
  final List<AtomicBatchForm> atomicBatchForms;
}

const _digest = 'sha256:req-1';

BusinessReceiptQuery _query({
  String operationId = 'op-1',
  String requestDigest = _digest,
  String toolId = 'inquiry.record_quote',
  String scopeDigest = 'sha256:scope-1',
  String domainIdentity = 'inquiry-db-1',
}) => BusinessReceiptQuery(
  operationId: operationId,
  requestDigest: requestDigest,
  toolId: toolId,
  scopeDigest: scopeDigest,
  domainIdentity: domainIdentity,
);

BusinessOperationReceipt _receipt({
  String operationId = 'op-1',
  String requestDigest = _digest,
  String toolId = 'inquiry.record_quote',
  String scopeDigest = 'sha256:scope-1',
  String domainIdentity = 'inquiry-db-1',
  bool applied = true,
  Map<String, Object?> resultData = const {'quotation_id': 'q-1'},
}) => BusinessOperationReceipt(
  operationId: operationId,
  moduleId: 'inquiry',
  requestDigest: requestDigest,
  toolId: toolId,
  scopeDigest: scopeDigest,
  domainIdentity: domainIdentity,
  applied: applied,
  resultData: resultData,
);

ObjectWriteForm _form(
  String type, {
  String? humanOnlyReason,
  bool creates = true,
  bool updates = true,
}) => ObjectWriteForm(
  objectType: type,
  fields: const [],
  creates: humanOnlyReason == null && creates,
  updates: humanOnlyReason == null && updates,
  deletes: humanOnlyReason == null,
  restores: humanOnlyReason == null,
  humanOnlyReason: humanOnlyReason,
);

void main() {
  group('write field and form declarations', () {
    test('a required-on-create field must be creatable', () {
      expect(
        () => WriteFieldPolicy(
          field: 'name',
          create: false,
          requiredOnCreate: true,
        ),
        throwsArgumentError,
      );
    });

    test('a field path must be a plain identifier', () {
      expect(() => WriteFieldPolicy(field: ''), throwsArgumentError);
      expect(() => WriteFieldPolicy(field: 'a.b'), throwsArgumentError);
      expect(() => WriteFieldPolicy(field: 'Name'), throwsArgumentError);
      expect(WriteFieldPolicy(field: 'unit_cost').field, 'unit_cost');
    });

    test('a field needs at least one writable operation', () {
      expect(
        () => WriteFieldPolicy(field: 'name', create: false, update: false),
        throwsArgumentError,
      );
    });

    test('duplicate field names in one form are rejected', () {
      expect(
        () => ObjectWriteForm(
          objectType: 'contact',
          fields: [
            WriteFieldPolicy(field: 'name'),
            WriteFieldPolicy(field: 'name', clearable: false),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('a human-only type cannot also allow operations', () {
      expect(
        () => ObjectWriteForm(
          objectType: 'quotation',
          fields: const [],
          humanOnlyReason: '报价只能在人工页面修改',
        ),
        throwsArgumentError,
      );
    });

    test('a human-only type allows nothing and says why', () {
      final form = _form(
        'quotation',
        humanOnlyReason: '报价只能在人工页面修改',
        creates: false,
        updates: false,
      );
      expect(form.humanOnlyReason, '报价只能在人工页面修改');
      for (final op in WriteFormOp.values) {
        expect(form.allows(op), isFalse, reason: op.name);
      }
    });

    test('a writable type reports each operation it allows', () {
      final form = ObjectWriteForm(
        objectType: 'contact',
        fields: [WriteFieldPolicy(field: 'name')],
        deletes: false,
        restores: false,
      );
      expect(form.allows(WriteFormOp.create), isTrue);
      expect(form.allows(WriteFormOp.update), isTrue);
      expect(form.allows(WriteFormOp.delete), isFalse);
      expect(form.allows(WriteFormOp.restore), isFalse);
      expect(form.fieldPolicy('name')?.field, 'name');
      expect(form.fieldPolicy('missing'), isNull);
    });

    test('form lists are frozen', () {
      final form = ObjectWriteForm(
        objectType: 'contact',
        fields: [WriteFieldPolicy(field: 'name')],
      );
      expect(
        () => form.fields.add(WriteFieldPolicy(field: 'phone')),
        throwsUnsupportedError,
      );
      expect(
        () => form.relations.add(RelationWriteConstraint(relation: 'supplier')),
        throwsUnsupportedError,
      );
    });

    test('equal declarations compare by value', () {
      expect(
        WriteFieldPolicy(field: 'name', requiredOnCreate: true),
        WriteFieldPolicy(field: 'name', requiredOnCreate: true),
      );
      expect(
        WriteFieldPolicy(field: 'name').hashCode,
        WriteFieldPolicy(field: 'name').hashCode,
      );
      expect(
        WriteFieldPolicy(field: 'name'),
        isNot(WriteFieldPolicy(field: 'name', update: false)),
      );
    });

    test('a relation constraint needs a relation name', () {
      expect(() => RelationWriteConstraint(relation: ''), throwsArgumentError);
    });
  });

  group('draft and validation result', () {
    test('a create draft must not carry an id or a version', () {
      expect(
        () => WriteDraft(
          objectType: 'contact',
          op: WriteFormOp.create,
          id: 'c-1',
          scopeProof: Object(),
        ),
        throwsArgumentError,
      );
      expect(
        () => WriteDraft(
          objectType: 'contact',
          op: WriteFormOp.create,
          expectedVersion: 1,
          scopeProof: Object(),
        ),
        throwsArgumentError,
      );
    });

    test('an update draft needs an id', () {
      expect(
        () => WriteDraft(
          objectType: 'contact',
          op: WriteFormOp.update,
          scopeProof: Object(),
        ),
        throwsArgumentError,
      );
    });

    test('draft values are frozen', () {
      final draft = WriteDraft(
        objectType: 'contact',
        op: WriteFormOp.create,
        values: const {'name': '张三'},
        scopeProof: Object(),
      );
      expect(() => draft.values['name'] = 'x', throwsUnsupportedError);
    });

    test('an invalid result must say what is wrong', () {
      expect(
        () => WriteValidationResult.invalid(issues: const []),
        throwsArgumentError,
      );
    });

    test('an ok result is valid and freezes its normalized values', () {
      final result = WriteValidationResult.ok(
        normalized: {'qty': 20},
        draftRevision: 3,
      );
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
      expect(result.formBlocked, isFalse);
      expect(result.draftRevision, 3);
      expect(() => result.normalized!['qty'] = 1, throwsUnsupportedError);
    });

    test('an invalid result is not valid and keeps field paths', () {
      final result = WriteValidationResult.invalid(
        issues: [
          FieldIssue(
            code: 'range',
            fieldPath: 'price_tiers[0].min_qty',
            message: '最小数量须大于 0',
          ),
        ],
      );
      expect(result.isValid, isFalse);
      expect(result.formBlocked, isTrue);
      expect(result.issues.single.fieldPath, 'price_tiers[0].min_qty');
    });

    test('issue lists in a result are frozen', () {
      final result = WriteValidationResult.invalid(
        issues: [
          FieldIssue(code: 'required', fieldPath: 'name', message: '必填'),
        ],
        formIssues: [FormIssue(code: 'empty_update', message: '没有改动')],
      );
      expect(
        () => result.issues.add(
          FieldIssue(code: 'type', fieldPath: 'qty', message: 'x'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => result.formIssues.add(FormIssue(code: 'x', message: 'x')),
        throwsUnsupportedError,
      );
    });

    test('a form-level error alone also makes the result invalid', () {
      final result = WriteValidationResult.invalid(
        issues: const [],
        formIssues: [FormIssue(code: 'empty_update', message: '没有需要保存的改动')],
      );
      expect(result.isValid, isFalse);
    });

    test('a field path must follow the stable path form', () {
      for (final bad in ['', ' name', 'Name', 'a..b', 'items[x]']) {
        expect(
          () => FieldIssue(code: 'required', fieldPath: bad, message: 'x'),
          throwsArgumentError,
          reason: bad,
        );
      }
      expect(
        FieldIssue(
          code: 'type',
          fieldPath: 'item_ids[2]',
          message: 'x',
        ).fieldPath,
        'item_ids[2]',
      );
    });
  });

  group('structured conflict', () {
    test('conflict codes are a closed set', () {
      expect(
        () => WriteConflict(code: 'overwrite_ok', currentVersion: 2),
        throwsArgumentError,
      );
    });

    test('trusted data keeps stable keys and the current version', () {
      final data = WriteConflict(
        code: 'version_conflict',
        currentVersion: 4,
        fieldPaths: const ['qty'],
        details: const {'saved_by': 'other'},
      ).toTrustedData();
      expect(data, {
        'error_code': 'version_conflict',
        'current_version': 4,
        'field_paths': ['qty'],
        'details': {'saved_by': 'other'},
      });
    });

    test('the current version must be a scalar', () {
      expect(
        () => WriteConflict(
          code: 'version_conflict',
          currentVersion: const <int>[1],
        ),
        throwsArgumentError,
      );
    });
  });

  group('business receipt lookup', () {
    test('a query needs every identity part', () {
      expect(() => _query(operationId: ''), throwsArgumentError);
      expect(() => _query(requestDigest: ''), throwsArgumentError);
      expect(() => _query(toolId: ''), throwsArgumentError);
      expect(() => _query(scopeDigest: ''), throwsArgumentError);
      expect(() => _query(domainIdentity: ''), throwsArgumentError);
    });

    test('a receipt needs its full proof: digest, tool, scope and domain', () {
      expect(() => _receipt(requestDigest: ''), throwsArgumentError);
      expect(() => _receipt(toolId: ''), throwsArgumentError);
      expect(() => _receipt(scopeDigest: ''), throwsArgumentError);
      expect(() => _receipt(domainIdentity: ''), throwsArgumentError);
    });

    test('receipt result data is frozen and compares by value', () {
      final receipt = _receipt();
      expect(
        () => receipt.resultData['quotation_id'] = 'x',
        throwsUnsupportedError,
      );
      expect(receipt, _receipt());
    });

    test('a receipt with the same identity matches the query', () {
      final result = BusinessReceiptLookupResult.verify(
        query: _query(),
        receipt: _receipt(),
      );
      expect(result.status, BusinessReceiptStatus.matched);
      expect(result.succeeded, isTrue);
    });

    test('any mismatched identity part is an identity conflict', () {
      final cases = <String, BusinessOperationReceipt>{
        'request digest': _receipt(requestDigest: 'sha256:other'),
        'tool': _receipt(toolId: 'inquiry.set_item_qty'),
        'scope': _receipt(scopeDigest: 'sha256:scope-2'),
        'domain library': _receipt(domainIdentity: 'inquiry-db-2'),
      };
      for (final entry in cases.entries) {
        final result = BusinessReceiptLookupResult.verify(
          query: _query(),
          receipt: entry.value,
        );
        expect(
          result.status,
          BusinessReceiptStatus.identityConflict,
          reason: entry.key,
        );
        expect(result.succeeded, isFalse, reason: entry.key);
      }
    });

    test('only a matched, applied receipt counts as success', () {
      expect(BusinessReceiptLookupResult.notFound().succeeded, isFalse);
      expect(
        BusinessReceiptLookupResult.unreadable('meta 行损坏').succeeded,
        isFalse,
      );
      expect(BusinessReceiptLookupResult.unknown('仍在执行').succeeded, isFalse);
      expect(
        BusinessReceiptLookupResult.verify(
          query: _query(),
          receipt: _receipt(applied: false),
        ).succeeded,
        isFalse,
      );
    });

    test('a matched result cannot be built around an unapplied receipt', () {
      expect(
        () => BusinessReceiptLookupResult.matched(_receipt(applied: false)),
        throwsArgumentError,
      );
    });

    test('unreadable and unknown results need a reason', () {
      expect(
        () => BusinessReceiptLookupResult.unreadable(''),
        throwsArgumentError,
      );
      expect(
        () => BusinessReceiptLookupResult.unknown(' '),
        throwsArgumentError,
      );
    });

    test('the five statuses are exactly the contract', () {
      expect(BusinessReceiptStatus.values.map((s) => s.name).toSet(), {
        'matched',
        'identityConflict',
        'notFound',
        'unreadable',
        'unknown',
      });
    });
  });

  group('atomic batch declarations', () {
    test('a single-row write form never enables atomic batch by itself', () {
      expect(
        atomicBatchAllowed(
          features: {ModuleFeature.writeForms},
          module: _WriteModule([_form('contact')]),
          objectType: 'contact',
          op: WriteFormOp.create,
        ),
        isFalse,
      );
    });

    test(
      'atomic batch needs the feature, the interface, and a listed form',
      () {
        final module = _BatchModule(
          [_form('contact')],
          [AtomicBatchForm(objectType: 'contact', op: WriteFormOp.create)],
        );
        final features = {
          ModuleFeature.writeForms,
          ModuleFeature.atomicBatchWrite,
        };
        expect(
          atomicBatchAllowed(
            features: features,
            module: module,
            objectType: 'contact',
            op: WriteFormOp.create,
          ),
          isTrue,
        );
        expect(
          atomicBatchAllowed(
            features: features,
            module: module,
            objectType: 'contact',
            op: WriteFormOp.update,
          ),
          isFalse,
          reason: 'an op that was not listed is not batchable',
        );
      },
    );

    test('batch limits must be positive', () {
      expect(
        () => AtomicBatchForm(
          objectType: 'contact',
          op: WriteFormOp.create,
          maxRows: 0,
        ),
        throwsArgumentError,
      );
      expect(
        AtomicBatchForm(objectType: 'contact', op: WriteFormOp.create).maxRows,
        50,
      );
    });

    test('batch declarations compare by value', () {
      expect(
        AtomicBatchForm(objectType: 'contact', op: WriteFormOp.create),
        AtomicBatchForm(objectType: 'contact', op: WriteFormOp.create),
      );
      expect(
        AtomicBatchForm(objectType: 'contact', op: WriteFormOp.create),
        isNot(AtomicBatchForm(objectType: 'contact', op: WriteFormOp.update)),
      );
    });
  });

  group('compliance', () {
    test('a module without optional write features has no violations', () {
      expect(
        writeContractViolations(features: const {}, module: Object()),
        isEmpty,
      );
    });

    test('declared writeForms without WriteFormCapable is a violation', () {
      final problems = writeContractViolations(
        features: {ModuleFeature.writeForms},
        module: Object(),
      );
      expect(problems.single, contains('validateDraft'));
    });

    test('WriteFormCapable without the writeForms feature is a violation', () {
      final problems = writeContractViolations(
        features: const {},
        module: _WriteModule(const []),
      );
      expect(problems.single, contains('writeForms'));
    });

    test('duplicate object types in writeForms are a violation', () {
      final problems = writeContractViolations(
        features: {ModuleFeature.writeForms},
        module: _WriteModule([_form('contact'), _form('contact')]),
      );
      expect(problems.single, contains('contact'));
    });

    test('declared businessReceipts without a lookup is a violation', () {
      final problems = writeContractViolations(
        features: {ModuleFeature.businessReceipts},
        module: Object(),
      );
      expect(problems.single, contains('BusinessReceiptLookup'));
    });

    test('a lookup without the businessReceipts feature is a violation', () {
      final problems = writeContractViolations(
        features: const {},
        module: _ReceiptModule(),
      );
      expect(problems.single, contains('businessReceipts'));
    });

    test('a batch declaration must be backed by a single-row form', () {
      final problems = writeContractViolations(
        features: {ModuleFeature.writeForms, ModuleFeature.atomicBatchWrite},
        module: _BatchModule(
          [_form('contact', updates: false)],
          [AtomicBatchForm(objectType: 'contact', op: WriteFormOp.update)],
        ),
      );
      expect(problems.single, contains('contact'));
      expect(problems.single, contains('update'));
    });

    test('atomic batch without its feature or interface is a violation', () {
      expect(
        writeContractViolations(
          features: const {},
          module: _BatchOnly([
            AtomicBatchForm(objectType: 'contact', op: WriteFormOp.create),
          ]),
        ),
        anyElement(contains('atomicBatchWrite')),
      );
      expect(
        writeContractViolations(
          features: {ModuleFeature.atomicBatchWrite},
          module: Object(),
        ).single,
        contains('AtomicBatchWriteCapable'),
      );
    });

    test('matching declarations and implementations are clean', () {
      expect(
        writeContractViolations(
          features: {ModuleFeature.writeForms, ModuleFeature.businessReceipts},
          module: _BothModule([_form('contact')]),
        ),
        isEmpty,
      );
    });
  });
}

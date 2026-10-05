// Assertions over a finished North Star run. They hold for the fixture and for
// a real model alike: they check what the host recorded, not model wording.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'north_star_fixture_model.dart';
import 'north_star_records.dart';

/// Seeded quotes per budget line, keyed by their price set, with the lowest
/// supplier and price the module must report. Matching on the quotes instead
/// of the request lets a real model ask about either line.
const _seededComparisons = {
  '11.8,12.5': ('北极星乙线缆', 11.8),
  '45.0,47.2': ('北极星甲电气', 45.0),
};

/// Whatever the model asked, the registered tools return the module's own
/// numbers: the cheapest quote per seeded line, and budget cost
/// 100×11.80 + 20×45.00 = 2080 over both lines. Checked on every matching
/// receipt. With [requireAll] (the fixture, which asks both questions) both
/// checks must have run, so a changed tool result cannot skip them silently.
void checkReadResults(
  List<Map<String, Object?>> receipts,
  Map<String, Object?> evidence, {
  required bool requireAll,
}) {
  final checked = <String>[];
  for (final receipt in receipts) {
    final result = jsonDecode(receipt['result_json'] as String) as Map;
    final output = result['data'] as Map?;
    if (output == null) continue;
    if (receipt['tool_id'] == 'inquiry.compare_quotes') {
      final quotes = [
        for (final g in (output['result'] as List?) ?? const [])
          ...((g as Map)['quotes'] as List).cast<Map>(),
      ];
      final prices = [
        for (final q in quotes) double.parse(q['price'] as String),
      ]..sort();
      final expected = _seededComparisons[prices.join(',')];
      if (expected != null) {
        final lowest = quotes.singleWhere((q) => q['lowest'] == true);
        expect(lowest['supplier'], expected.$1);
        expect(double.parse(lowest['price'] as String), expected.$2);
        checked.add('compare_quotes');
      }
    }
    if (receipt['tool_id'] == 'inquiry.project_budget' &&
        output['cost'] != null) {
      expect(output['total'], 2, reason: 'Both seeded budget lines');
      expect(double.parse(output['cost'] as String), 2080);
      checked.add('project_budget');
    }
  }
  if (requireAll) {
    expect(checked.toSet(), {
      'compare_quotes',
      'project_budget',
    }, reason: 'Fixture read results must match the seeded data');
  }
  evidence['readResultsChecked'] = checked;
}

/// Every offered, proposed and executed tool is registered; exactly one write
/// ran; one succeeded ledger row per confirmed model send; with the fixture,
/// the ledger digests exactly the bytes the endpoint received.
void checkInvariants(
  MuyonHost host,
  Set<String> registered, {
  required List<Map<String, Object?>> taskEvidence,
  required FixtureModelServer? fixture,
  required Map<String, Object?> evidence,
}) {
  for (final task in host.foundation.tasks()) {
    expect(task.state, PersonalTaskState.succeeded, reason: task.id);
    final system = jsonDecode(
      ((task.payload['messages'] as List).first as Map)['content'] as String,
    ) as Map;
    for (final offered in system['tools'] as List) {
      expect(registered, contains((offered as Map)['toolId']));
    }
    for (final toolId in proposedTools(task)) {
      expect(registered, contains(toolId), reason: 'proposed tool');
    }
  }
  final receipts = receiptRows(host);
  for (final receipt in receipts) {
    expect(registered, contains(receipt['tool_id']));
    expect(receipt['state'], 'succeeded');
  }
  final writes = receipts.where(
    (r) =>
        host.tools.inspect(r['tool_id'] as String)!.accessLevel !=
        ToolAccessLevel.read,
  );
  expect(writes, hasLength(1), reason: 'Exactly one approved write');
  final ledger = ledgerRows(host);
  final confirmations = taskEvidence.fold<int>(
    0,
    (n, t) => n + (t['modelConfirmations'] as int),
  );
  expect(ledger, hasLength(confirmations), reason: 'One row per model send');
  for (final row in ledger) {
    expect(row['status'], 'succeeded', reason: '${row['error']}');
    expect(row['caller'], 'assistant');
    expect(row['http_status'], 200);
  }
  if (fixture != null) {
    expect(fixture.errors, isEmpty);
    expect(fixture.pending, 0, reason: 'Every scripted turn was used');
    expect(
      ledger.map((r) => r['payload_sha256']).toSet(),
      fixture.bodies
          .map((b) => sha256.convert(utf8.encode(b)).toString())
          .toSet(),
    );
  }
  evidence['ledger'] = {
    'rows': ledger.length,
    'statuses': histogram(ledger.map((r) => '${r['status']}')),
    'bytesSent': ledger.fold<int>(0, (n, r) => n + (r['payload_bytes'] as int)),
  };
  evidence['receipts'] = {
    'rows': receipts.length,
    'byTool': histogram(receipts.map((r) => '${r['tool_id']}')),
  };
}

/// Endpoint as written to evidence: scheme, host, port and path only, so a key
/// passed in user info or the query string never reaches the evidence file.
String evidenceEndpoint(Uri endpoint) => Uri(
  scheme: endpoint.scheme,
  host: endpoint.host,
  port: endpoint.hasPort ? endpoint.port : null,
  path: endpoint.path,
).toString();

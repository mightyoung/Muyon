part of 'agent_eval.dart';

// ---------------------------------------------------------------- scoring

/// What one run of one task did, as far as scoring needs it.
class AgentObservation {
  const AgentObservation({
    required this.state,
    this.error,
    this.rejectedWrite = false,
    this.proposedTools = const [],
    this.proposedWrites = const [],
    this.appliedWrites = const [],
    this.answer,
    this.writeStateErrors = const [],
    this.storeChanged = false,
    this.scopePinned = false,
  });

  /// Final [PersonalTaskState] name.
  final String state;
  final String? error;

  /// The harness refused a write the task did not expect.
  final bool rejectedWrite;

  /// Tool ids the model proposed, in order.
  final List<String> proposedTools;

  /// The proposed tools that are not read-only.
  final List<String> proposedWrites;

  /// Write tools whose receipt says they succeeded.
  final List<String> appliedWrites;
  final String? answer;

  /// Mismatches found by [checkWriteState].
  final List<String> writeStateErrors;

  /// Any inquiry-module record differs from the seeded one.
  final bool storeChanged;

  /// The task failed on the scope check after a write had changed a selected
  /// record (see [AgentFailure.scopePinned]).
  final bool scopePinned;
}

class AgentVerdict {
  const AgentVerdict(this.failures);
  final List<String> failures;
  bool get success => failures.isEmpty;
}

/// Multiset difference: items of [a] not matched by an item of [b].
List<String> _minus(List<String> a, List<String> b) {
  final rest = [...b];
  final out = <String>[];
  for (final item in a) {
    if (!rest.remove(item)) out.add(item);
  }
  return out;
}

bool _isSubsequence(List<String> wanted, List<String> seen) {
  var i = 0;
  for (final item in seen) {
    if (i < wanted.length && item == wanted[i]) i++;
  }
  return i == wanted.length;
}

/// Numbers in [text] as decimals; thousands commas are removed.
List<double> numbersIn(String text) => [
  for (final m in RegExp(r'\d+(?:,\d{3})*(?:\.\d+)?').allMatches(text))
    double.parse(m[0]!.replaceAll(',', '')),
];

bool answerStates(String? answer, AgentFact fact) {
  if (answer == null) return false;
  final text = fact.text;
  if (text != null) return answer.contains(text);
  final want = double.parse(fact.number!);
  if (fact.anchors.isEmpty && fact.prefixAnchors.isEmpty) {
    return numbersIn(answer).any((n) => (n - want).abs() < 1e-9);
  }
  for (final m in RegExp(r'\d+(?:,\d{3})*(?:\.\d+)?').allMatches(answer)) {
    final value = double.parse(m[0]!.replaceAll(',', ''));
    if ((value - want).abs() >= 1e-9) continue;
    final before = answer.substring(0, m.start).trimRight();
    final after = answer.substring(m.end).trimLeft();
    final lowerBefore = before.toLowerCase(), lowerAfter = after.toLowerCase();
    if (fact.rejectPrefixes.any(before.endsWith)) continue;
    if (fact.anchors.any((a) => lowerAfter.startsWith(a.toLowerCase())) ||
        fact.prefixAnchors.any((a) => lowerBefore.endsWith(a.toLowerCase()))) {
      return true;
    }
  }
  return false;
}

/// Success needs every one of: the task ended, no write the task did not
/// expect, the required tools (in order when asked), the expected writes
/// applied with the expected resulting state, and every fact in the answer.
AgentVerdict judgeTask(AgentTask task, AgentObservation seen) {
  final failures = <String>[];
  final expectedWriteTools = [for (final w in task.expectedWrites) w.tool];
  if (_minus(seen.proposedWrites, expectedWriteTools).isNotEmpty ||
      _minus(seen.appliedWrites, expectedWriteTools).isNotEmpty ||
      seen.rejectedWrite ||
      (!task.expectsWrite && seen.storeChanged)) {
    failures.add(AgentFailure.extraWrite);
  }
  if (seen.rejectedWrite) return AgentVerdict(failures);
  if (seen.state != PersonalTaskState.succeeded.name) {
    failures.add(
      seen.scopePinned ? AgentFailure.scopePinned : AgentFailure.requestFailed,
    );
    return AgentVerdict(failures);
  }
  if (task.noTools && seen.proposedTools.isNotEmpty) {
    failures.add(AgentFailure.unexpectedTool);
  }
  if (_minus(task.expectedTools, seen.proposedTools).isNotEmpty) {
    failures.add(AgentFailure.toolMissing);
  } else if (task.orderMatters &&
      !_isSubsequence(task.expectedTools, seen.proposedTools)) {
    failures.add(AgentFailure.toolOrder);
  }
  if (_minus(expectedWriteTools, seen.appliedWrites).isNotEmpty) {
    failures.add(AgentFailure.writeMissing);
  } else if (seen.writeStateErrors.isNotEmpty) {
    failures.add(AgentFailure.writeMismatch);
  }
  if (task.facts.any((fact) => !answerStates(seen.answer, fact))) {
    failures.add(AgentFailure.factMismatch);
  }
  return AgentVerdict(failures);
}

// ------------------------------------------------------- store inspection

const _snapshotTypes = [
  'project',
  'project_item',
  'supplier',
  'product',
  'quotation',
  'inquiry',
];

/// Every inquiry-module record by type and id, as its stored JSON.
Map<String, String> snapshotStore(Store store) => {
  for (final type in _snapshotTypes)
    for (final row in store.db.select('SELECT id, data FROM $type'))
      '$type/${row['id']}': row['data'] as String,
};

/// Checks one expected write's resulting state; returns the mismatches.
/// [ids] maps seed keys to ids; [before] is the snapshot taken after seeding.
List<String> checkWriteState(
  Store store,
  Map<String, Object?> check,
  Map<String, String> ids,
  Map<String, String> before,
) {
  String id(String key) => ids[key] ?? (throw StateError('unknown key $key'));
  final errors = <String>[];
  switch (check['kind']) {
    case 'inquiry_created':
      final created = [
        for (final row in store.db.select(
          'SELECT id, data FROM inquiry WHERE deleted = 0',
        ))
          if (!before.containsKey('inquiry/${row['id']}'))
            jsonDecode(row['data'] as String) as Map,
      ].where((d) => d['title'] == check['title']).toList();
      if (created.length != 1) {
        errors.add(
          'expected one new inquiry "${check['title']}", found '
          '${created.length}',
        );
        break;
      }
      final data = created.single;
      if (data['project_id'] != id(check['project'] as String)) {
        errors.add('inquiry is for another project');
      }
      if (data['status'] != 'open') errors.add('inquiry is not open');
      List<String> ofKeys(Object? keys) =>
          [for (final k in keys as List) id('$k')]..sort();
      if (jsonEncode(
            ([...(data['item_ids'] as List).cast<String>()]..sort()),
          ) !=
          jsonEncode(ofKeys(check['items']))) {
        errors.add('inquiry has other items');
      }
      if (jsonEncode(
            ([...(data['supplier_ids'] as List).cast<String>()]..sort()),
          ) !=
          jsonEncode(ofKeys(check['suppliers']))) {
        errors.add('inquiry has other suppliers');
      }
    case 'quote':
      final product = store
          .get('project_item', id(check['item'] as String))
          ?.data['product_id'];
      final rows = store.db.select(
        "SELECT data FROM quotation WHERE deleted = 0 "
        "AND json_extract(data,'\$.inquiry_id') = ? "
        "AND json_extract(data,'\$.supplier_id') = ? "
        "AND json_extract(data,'\$.product_id') = ? "
        "ORDER BY json_extract(data,'\$.quoted_on') DESC, rowid DESC LIMIT 1",
        [
          id(check['inquiry'] as String),
          id(check['supplier'] as String),
          product,
        ],
      );
      final price = rows.isEmpty
          ? null
          : (jsonDecode(rows.first['data'] as String) as Map)['price'];
      if (price == null ||
          double.tryParse('$price') != double.parse(check['price'] as String)) {
        errors.add('quote is $price, expected ${check['price']}');
      }
    case 'item_qty':
      final qty = store.get('project_item', id(check['item'] as String))?.data;
      if (qty == null ||
          double.tryParse('${qty['qty']}') !=
              double.parse(check['qty'] as String)) {
        errors.add('qty is ${qty?['qty']}, expected ${check['qty']}');
      }
    case 'inquiry_status':
      final status = store
          .get('inquiry', id(check['inquiry'] as String))
          ?.data['status'];
      if (status != check['status']) {
        errors.add('status is $status, expected ${check['status']}');
      }
    default:
      throw StateError('unknown write check ${check['kind']}');
  }
  return errors;
}

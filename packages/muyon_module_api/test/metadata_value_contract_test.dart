import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

// Runtime JSON input avoids testing only canonical const fixtures.
String runtimeText(String value) => jsonDecode(jsonEncode(value)) as String;

void main() {
  test('runtime coverage metadata retains surface and exclusion fields', () {
    final surface = Surface(
      runtimeText('package:example/example.dart'),
      runtimeText('Example'),
    );
    expect(surface.library, 'package:example/example.dart');
    expect(surface.name, 'Example');
    final kind = NotExposedKind.values.singleWhere(
      (kind) => kind.name == runtimeText('deferred'),
    );
    final exclusion = NotExposed(
      kind,
      runtimeText('Awaiting reviewed adapter'),
      taskId: runtimeText('adapter-task'),
    );
    expect(exclusion.kind, NotExposedKind.deferred);
    expect(exclusion.reason, 'Awaiting reviewed adapter');
    expect(exclusion.taskId, 'adapter-task');
    expect(NotExposed(kind, runtimeText('Deferred')).taskId, isNull);
  });

  test('empty capability coverage has version one and immutable empty lists', () {
    final empty = CapabilityCoverage.empty;
    expect(empty.version, 1);
    expect(empty.surfaces, isEmpty);
    expect(empty.operations, isEmpty);
    expect(() => empty.surfaces.clear(), throwsUnsupportedError);
    expect(() => empty.operations.clear(), throwsUnsupportedError);
  });

  test('runtime page support preserves bound and explicitly absent semantics', () {
    final factories = <String, ObjectPageSupport Function()>{
      runtimeText('bound'): ObjectPageSupport.bound,
    };
    final bound = factories[runtimeText('bound')]!();
    expect(bound.kind, ObjectPageKind.bound);
    expect(bound.reason, isNull);
    expect(bound.hasPage, isTrue);
    final absent = ObjectPageSupport.none(runtimeText('No document page'));
    expect(absent.kind, ObjectPageKind.none);
    expect(absent.reason, 'No document page');
    expect(absent.hasPage, isFalse);
  });

  test('flow step requires exactly one runtime tool or action binding', () {
    final tool = FlowStep(tool: runtimeText('document.inspect'));
    expect(tool.tool, 'document.inspect');
    expect(tool.action, isNull);
    final action = FlowStep(action: runtimeText('manual'));
    expect(action.action, 'manual');
    expect(action.tool, isNull);
    expect(() => FlowStep(), throwsAssertionError);
    expect(
      () => FlowStep(
        tool: runtimeText('document.inspect'),
        action: runtimeText('manual'),
      ),
      throwsAssertionError,
    );
  });
}

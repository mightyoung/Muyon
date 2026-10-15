import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_tool_registrar.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/platform/plugin_contract/catalog.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/plugin_fixture.dart';

class UnusedModuleLink implements ModuleLink {
  var activations = 0;
  @override
  Future<ModuleState> activate(String moduleId) async {
    activations++;
    throw StateError('registration must not activate a module');
  }
  @override
  T? runtime<T extends ModuleRuntime>(String moduleId) => null;
}

void main() {
  test('registrar preserves sensitivity without granting', () async {
    final f = await PluginFixture.open();
    final link = UnusedModuleLink();
    final registrar = HostToolRegistrar('probe', f.loop.tools,
      ModuleManifest(id: 'probe', apiVersion: 2), link);
    final labels = {'value': Sensitivity.commercial};
    var calls = 0;
    registrar.read(ToolSpec(name: 'read', description: 'Read synthetic value',
      resultSensitivity: labels), (_) async {
        calls++;
        return ToolCallResult(status: ToolCallStatus.succeeded, summary: 'synthetic');
      });
    labels['value'] = Sensitivity.none;
    final descriptor = f.loop.tools.inspect('probe.read')!.descriptor;
    expect(descriptor.resultSensitivity['value'], Sensitivity.commercial);
    expect(() => descriptor.resultSensitivity['value'] = Sensitivity.none,
        throwsUnsupportedError);
    expect(f.loop.tools.inspect(f.id)!.descriptor.resultSensitivity, isEmpty);
    expect(calls, 0);
    expect(link.activations, 0);
    expect(f.loop.approvals(), isEmpty);
    expect(f.loop.receipts(), isEmpty);
  });

  test('actual declarations map three distinct read contracts', () async {
    final root = Directory.systemTemp.createTempSync('plugin-map-');
    final host = await MuyonHost.open(root.path);
    addTearDown(() async { await host.close(); root.deleteSync(recursive: true); });
    for (final pair in [('research', 'research.read_object', {'project', 'document'}),
        ('inquiry', 'inquiry.object', {'supplier', 'product'})]) {
      final module = host.registry.require(pair.$1) as BusinessModuleV2;
      final descriptor = host.tools.inspect(pair.$2)!.descriptor;
      final mapped = PluginCatalog.mapRead(ontology: module.ontology,
        descriptor: descriptor, admittedTypes: pair.$3, bindingId: 'host-${pair.$1}');
      expect(mapped['module_id'], pair.$1);
      expect(mapped['data'], isNotEmpty);
      final operation = (mapped['operations'] as List).single as Map;
      expect((operation['input_schema'] as Map)['required'], ['type', 'id']);
      expect((operation['projection_schema'] as Map)['properties'], contains('objects'));
      // Input narrowing cannot replace native shapes with equipment aliases.
      expect((operation['input_schema'] as Map)['properties'], isNot(contains('equipment_key')));
      final f = await PluginFixture.open();
      final before = f.loop.receipts().length;
      expect(f.handlerCalls, 0);
      expect(f.loop.receipts().length, before);
    }
    final equipment = await PluginFixture.open();
    expect(equipment.enrolled, isTrue);
    final schema = ((equipment.bundle['operations'] as List).single as Map)['input_schema'] as Map;
    expect(schema['required'], ['equipment_key']);
    expect(schema['properties'], isNot(contains('type')));
    expect((equipment.bundle['views'] as List).single, isNot(contains('handler')));
  });

  test('permission filtered catalog drives selection', () async {
    final f = await PluginFixture.open();
    expect(f.enrolled, isTrue);
    final visible = await f.bridge.discover(f.request());
    final selection = PluginCatalogSelection(visible);
    expect(selection.select(prompt: 'inspect', scope: f.request().scope,
        availableTools: f.loop.tools.list(), modelAvailable: true).candidateIds,
        [f.id]);
    f.allowed = false;
    final denied = await f.bridge.discover(f.request());
    expect(denied, isEmpty);
    f.loop.tools.setAvailability(f.id, available: false);
    expect(selection.select(prompt: 'inspect', scope: f.request().scope,
        availableTools: f.loop.tools.list(), modelAvailable: true).candidateIds, isEmpty);
    expect(f.handlerCalls, 0);
    expect(f.loop.receipts(), isEmpty);
  });
}

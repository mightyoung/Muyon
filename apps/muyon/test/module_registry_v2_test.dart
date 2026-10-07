import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/module_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/fake_v2_module.dart';

class _V1 implements BusinessModule {
  _V1(String id, {int apiVersion = 1})
    : manifest = ModuleManifest(id: id, apiVersion: apiVersion);
  @override
  final ModuleManifest manifest;
  @override
  ModuleSchema get schema => throw UnimplementedError();
  @override
  List<ModuleRoute> get routes => const [];
  @override
  Future<ModuleRuntime> activate(ModuleResources resources) =>
      throw UnimplementedError();
}

void main() {
  test('API versions 1 and 2 are accepted', () {
    final registry = ModuleRegistry([_V1('old'), FakeV2Module('new')]);
    expect(registry.unavailable, isEmpty);
    expect(registry.modules.map((m) => m.manifest.id), {'old', 'new'});
    expect(ModuleRegistry.supportedApiVersions, {1, 2});
  });

  test('API versions 0 and 3 are refused with the version in the reason', () {
    final registry = ModuleRegistry([
      _V1('zero', apiVersion: 0),
      _V1('three', apiVersion: 3),
      FakeV2Module('three_v2', apiVersion: 3),
    ]);
    expect(registry.unavailable.keys, {'zero', 'three', 'three_v2'});
    expect(registry.unavailable['three'], contains('v3'));
    expect(registry.modules, isEmpty);
  });

  test('API v2 without BusinessModuleV2 is unavailable', () {
    final registry = ModuleRegistry([_V1('liar', apiVersion: 2)]);
    expect(
      registry.unavailable['liar'],
      'Declared API v2 without BusinessModuleV2',
    );
    expect(() => registry.require('liar'), throwsStateError);
  });

  test('a v2 module asking for an unregistered capability is unavailable', () {
    const known = {'knowledge', 'models', 'ocr', 'transfer', 'tools'};
    final registry = ModuleRegistry([
      FakeV2Module(
        'greedy',
        capabilities: {
          const CapabilityRequest(id: 'telepathy', reason: 'because'),
        },
      ),
      FakeV2Module(
        'fine',
        capabilities: {const CapabilityRequest(id: 'ocr', reason: 'scans')},
      ),
    ], knownCapabilities: known);
    expect(registry.unavailable['greedy'], contains('telepathy'));
    expect(registry.require('fine').manifest.id, 'fine');
  });

  test('a v2 module depending on a refused one is unavailable too', () {
    final registry = ModuleRegistry([
      _V1('base', apiVersion: 3),
      FakeV2Module('child', requires: ['base']),
    ]);
    expect(registry.unavailable.keys, {'base', 'child'});
  });
}

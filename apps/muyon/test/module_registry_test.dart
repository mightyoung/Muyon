import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/module_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

class _Module implements BusinessModule {
  _Module(
    String id, {
    int apiVersion = 1,
    List<String> requires = const [],
    List<String> optional = const [],
  }) : manifest = ModuleManifest(
         id: id,
         apiVersion: apiVersion,
         requiredDependencies: requires,
         optionalDependencies: optional,
       );
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
  test('broken modules are unavailable; healthy ones stay usable', () {
    final registry = ModuleRegistry([
      _Module('research'),
      _Module('old', apiVersion: 99),
      _Module('needs_missing', requires: ['ghost']),
      _Module('needs_old', requires: ['old']),
      _Module('cycle_a', requires: ['cycle_b']),
      _Module('cycle_b', requires: ['cycle_a']),
      _Module('optional', optional: ['ghost']),
    ]);
    expect(registry.require('research').manifest.id, 'research');
    expect(registry.require('optional').manifest.id, 'optional');
    expect(registry.unavailable.keys, {
      'old',
      'needs_missing',
      'needs_old',
      'cycle_a',
      'cycle_b',
    });
    expect(registry.unavailable['needs_missing'], contains('ghost'));
    expect(
      () => registry.require('needs_old'),
      throwsA(isA<StateError>()),
    );
    expect(registry.modules.map((m) => m.manifest.id), {
      'research',
      'optional',
    });
  });

  test('duplicate module ids are a build error', () {
    expect(
      () => ModuleRegistry([_Module('a'), _Module('a')]),
      throwsStateError,
    );
  });
}

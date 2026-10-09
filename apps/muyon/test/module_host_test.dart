import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/module_catalog.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/platform/module_grants.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/fake_v2_module.dart';

/// REG-2b: one generic activation path with failure isolation, grants on
/// record, and tools that follow the module's health.
void main() {
  late Directory root;
  MuyonHost? host;

  setUp(() => root = Directory.systemTemp.createTempSync('module-host-'));
  tearDown(() async {
    await host?.close();
    host = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<MuyonHost> open(List<BusinessModule> modules) async =>
      host = await MuyonHost.open(root.path, modules: modules);

  Map<String, Object?> registryRow(String id) => host!.workspaces.database.raw
      .select(
        'SELECT status,last_error FROM module_registry WHERE module_id=?',
        [id],
      )
      .map((r) => {'status': r['status'], 'error': r['last_error']})
      .single;

  void declareRead(ToolRegistrar r, [String name = 'ping']) => r.read(
    ToolSpec(name: name, description: '读取一条测试记录，仅用于测试，不改动任何数据。'),
    (ctx) async =>
        ToolCallResult(status: ToolCallStatus.succeeded, summary: 'pong'),
  );

  test('a v2 module activates through the generic path, once', () async {
    final alpha = FakeV2Module('alpha');
    await open([alpha]);
    expect(host!.modules.state('alpha').status, ModuleStatus.inactive);
    final states = await Future.wait([
      host!.modules.activate('alpha'),
      host!.modules.activate('alpha'),
    ]);
    expect(states.map((s) => s.status), everyElement(ModuleStatus.ready));
    await host!.modules.activate('alpha');
    expect(
      alpha.activations,
      1,
      reason: 'concurrent and repeated calls share one run',
    );
    expect(host!.modules.runtime<FakeRuntime>('alpha'), same(alpha.runtime));
    expect(registryRow('alpha'), {'status': 'ready', 'error': null});
    expect(alpha.lastResources!.files.rootPath, contains('alpha'));
    expect(alpha.lastResources!.database.raw, isNotNull);
  });

  test('one module failing leaves the others, and the host, working', () async {
    final bad = FakeV2Module(
      'bad',
      failActivation: true,
      onRegisterTools: declareRead,
    );
    final good = FakeV2Module('good', onRegisterTools: declareRead);
    await open([bad, good, ...moduleCatalog()]);

    final failed = await host!.modules.activate('bad');
    expect(failed.status, ModuleStatus.failed);
    expect(failed.reason, contains('boom from bad'));
    expect(host!.modules.error('bad'), contains('boom'));
    expect(host!.modules.runtime<FakeRuntime>('bad'), isNull);
    expect(registryRow('bad')['status'], 'failed');
    expect(registryRow('bad')['error'], contains('boom'));
    // Its tools are withdrawn with the reason; the other module's are not.
    expect(host!.tools.inspect('bad.ping')!.available, isFalse);
    expect(
      host!.tools.inspect('bad.ping')!.unavailableReason,
      contains('boom'),
    );

    final ok = await host!.modules.activate('good');
    expect(ok.status, ModuleStatus.ready);
    expect(host!.tools.inspect('good.ping')!.available, isTrue);
    final call = await host!.tools.invoke(
      ToolCallRequest(
        invocationId: 'good-ping',
        toolId: 'good.ping',
        scope: const AssistantScope.global(),
      ),
    );
    expect(call.status, ToolCallStatus.succeeded);
    // The built-in modules never noticed.
    await host!.activatePrototype();
    expect(host!.prototype, isNotNull);
    expect(host!.registry.unavailable, isEmpty);

    // The next call retries, and success brings the tools back.
    bad.failActivation = false;
    expect((await host!.modules.activate('bad')).status, ModuleStatus.ready);
    expect(registryRow('bad')['status'], 'ready');
    expect(host!.tools.inspect('bad.ping')!.available, isTrue);
  });

  test(
    'a tool call activates its module first, and reports a failed one',
    () async {
      final lazy = FakeV2Module('lazy', onRegisterTools: declareRead);
      await open([lazy]);
      expect(lazy.activations, 0, reason: 'registered at start, not activated');
      expect(host!.tools.inspect('lazy.ping'), isNotNull);
      final result = await host!.tools.invoke(
        ToolCallRequest(
          invocationId: 'lazy-1',
          toolId: 'lazy.ping',
          scope: const AssistantScope.global(),
        ),
      );
      expect(result.status, ToolCallStatus.succeeded);
      expect(lazy.activations, 1);

      final broken = FakeV2Module(
        'broken',
        failActivation: true,
        onRegisterTools: declareRead,
      );
      await host!.close();
      host = null;
      await open([broken]);
      final failed = await host!.tools.invoke(
        ToolCallRequest(
          invocationId: 'broken-1',
          toolId: 'broken.ping',
          scope: const AssistantScope.global(),
        ),
      );
      expect(failed.status, ToolCallStatus.failed);
      expect(failed.summary, contains('unavailable'));
    },
  );

  test('a required dependency that fails fails its dependent only', () async {
    final base = FakeV2Module('base', failActivation: true);
    final child = FakeV2Module('child', requires: ['base']);
    final other = FakeV2Module('other');
    await open([base, child, other]);
    final state = await host!.modules.activate('child');
    expect(state.status, ModuleStatus.failed);
    expect(state.reason, contains('Required module base is unavailable'));
    expect(child.activations, 0);
    expect((await host!.modules.activate('other')).status, ModuleStatus.ready);
  });

  group('capability grants', () {
    List<GrantDecision> grants(String id) => host!.grants.forModule(id);

    test('decisions follow the policy and are recorded', () async {
      final module = FakeV2Module(
        'asker',
        capabilities: {
          const CapabilityRequest(id: 'ocr', reason: '读取扫描件'),
          const CapabilityRequest(id: 'knowledge', reason: '检索资料'),
          const CapabilityRequest(id: 'tools', reason: '想调用工具'),
          const CapabilityRequest(id: 'transfer', reason: '想传输'),
        },
      );
      await open([module]);
      expect(
        (await host!.modules.activate('asker')).status,
        ModuleStatus.ready,
      );
      final byCap = {for (final d in grants('asker')) d.capability: d};
      expect(byCap['ocr']!.granted, isTrue);
      expect(byCap['ocr']!.policy, 'auto');
      expect(byCap['knowledge']!.granted, isFalse);
      expect(byCap['knowledge']!.policy, GrantPolicy.facadePending);
      expect(
        byCap['tools']!.granted,
        isFalse,
        reason: 'v2 declares tools through the registrar',
      );
      expect(
        byCap['transfer']!.granted,
        isFalse,
        reason: 'no exchange feature',
      );
      expect(byCap['ocr']!.required, isFalse);
      final caps = module.lastResources!.capabilities;
      expect(caps.available, {'ocr'});
      expect(caps.denied, {'knowledge', 'tools', 'transfer'});
      expect(() => caps.require<Object>('tools'), throwsStateError);
    });

    test('a required capability that is denied fails the module', () async {
      final module = FakeV2Module(
        'needy',
        capabilities: {
          const CapabilityRequest(id: 'tools', required: true, reason: '必需'),
        },
      );
      await open([module]);
      final state = await host!.modules.activate('needy');
      expect(state.status, ModuleStatus.failed);
      expect(state.reason, 'capability_denied: tools');
      expect(module.activations, 0);
      expect(grants('needy').single.granted, isFalse);
      expect(registryRow('needy')['error'], 'capability_denied: tools');
    });

    test('transfer needs the exchange feature', () async {
      final module = FakeV2Module(
        'exchanger',
        features: {ModuleFeature.exchange},
        capabilities: {const CapabilityRequest(id: 'transfer', reason: '收发')},
      );
      await open([module]);
      await host!.modules.activate('exchanger');
      expect(grants('exchanger').single.granted, isTrue);
      expect(module.lastResources!.capabilities.available, {'transfer'});
    });

    test('the host can revoke, and the module stays without it', () async {
      final module = FakeV2Module(
        'revoked',
        onRegisterTools: declareRead,
        capabilities: {const CapabilityRequest(id: 'ocr', reason: '扫描')},
      );
      await open([module]);
      await host!.modules.activate('revoked');
      expect(grants('revoked').single.granted, isTrue);
      await host!.modules.revokeCapability('revoked', 'ocr');
      expect(host!.modules.state('revoked').reason, 'capability_revoked: ocr');
      expect(host!.tools.inspect('revoked.ping')!.available, isFalse);
      expect(grants('revoked').single.policy, 'revoked');
      // Withdrawal remains fail closed until the host explicitly reconsiders.
      await host!.modules.activate('revoked');
      expect(grants('revoked').single.granted, isFalse);
      expect(host!.modules.state('revoked').status, ModuleStatus.failed);
      expect(host!.modules.runtime<ModuleRuntime>('revoked'), isNull);
    });
  });

  test('research keeps its grants on record when it activates', () async {
    await MuyonHost.open(root.path).then((h) => host = h);
    await host!.activateResearch();
    final decisions = host!.grants.forModule('research');
    expect(
      {for (final d in decisions) d.capability},
      {'knowledge', 'models'},
    );
    expect(decisions.every((d) => !d.granted && d.policy == GrantPolicy.facadePending), isTrue);
    await host!.activatePrototype();
    expect(host!.grants.forModule('prototype'), isEmpty);
  });

  group('declarations', () {
    test(
      'the three v1 modules are declared as the home and menu showed them',
      () async {
        await MuyonHost.open(root.path).then((h) => host = h);
        final declarations = host!.modules.declarations().toList();
        expect(declarations.map((d) => d.moduleId), [
          'inquiry',
          'research',
          'prototype',
        ]);
        expect(declarations.map((d) => d.displayName), [
          'Folio · 询价台账',
          '科研工作台',
          '原型页面',
        ]);
        expect(declarations.map((d) => d.tagline), [
          '完整供应商、询价报价和成本业务',
          '原文阅读、批注、研究过程和成果',
          '导入单页原型，评审版本并记录反馈（不是完整业务系统）',
        ]);
        final menu = host!.modules.sections().where((s) => s.showInModuleMenu);
        expect(menu.map((s) => (s.id, s.label)), [
          ('inquiry', 'Folio · 询价与成本'),
          ('research', '科研工作台'),
        ]);
      },
    );

    test('a v2 module is declared from its manifest and sections', () async {
      final module = FakeV2Module(
        'notes',
        displayName: '记事本',
        tagline: '随手记',
        sections: [fakeSection('notes', label: '记事本')],
      );
      await open([module]);
      final declarations = host!.modules.declarations().toList();
      expect(declarations.first.moduleId, 'notes');
      expect(declarations.first.displayName, '记事本');
      expect(declarations.first.tagline, '随手记');
      expect(host!.modules.moduleOfSection('notes'), 'notes');
    });
  });

  test(
    'tools of a module whose registration fails are withdrawn, others stay',
    () async {
      final flawed = FakeV2Module(
        'flawed',
        onRegisterTools: (r) {
          declareRead(r);
          declareRead(r, 'ping');
        },
      );
      final sound = FakeV2Module('sound', onRegisterTools: declareRead);
      await open([flawed, sound]);
      expect(host!.tools.inspect('flawed.ping')!.available, isFalse);
      final state = await host!.modules.activate('flawed');
      expect(state.status, ModuleStatus.failed);
      expect(state.reason, contains('Tool registration failed'));
      expect(host!.tools.inspect('sound.ping')!.available, isTrue);
      expect(
        (await host!.modules.activate('sound')).status,
        ModuleStatus.ready,
      );
    },
  );
}

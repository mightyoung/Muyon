import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/fake_v2_module.dart';

class NativeHttp extends HttpOverrides {
  HttpClient client() => super.createHttpClient(null);
}

class PausedModule extends FakeV2Module {
  PausedModule()
    : super(
        'paused',
        capabilities: {const CapabilityRequest(id: 'ocr', reason: 'scan')},
        onRegisterTools: (r) => r.read(
          ToolSpec(name: 'ping', description: 'test read'),
          (_) async =>
              ToolCallResult(status: ToolCallStatus.succeeded, summary: 'ok'),
        ),
      );
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ModuleRuntime> activate(ModuleResources resources) async {
    final result = await super.activate(resources);
    entered.complete();
    await release.future;
    return result;
  }
}

void main() {
  test(
    'failed revocation keeps admission closed until that capability retries',
    () async {
      final root = Directory.systemTemp.createTempSync('revocation-retry-');
      final module = FakeV2Module(
        'recovery',
        features: {ModuleFeature.exchange},
        capabilities: {
          const CapabilityRequest(id: 'ocr', reason: 'scan'),
          const CapabilityRequest(id: 'transfer', reason: 'exchange'),
        },
      );
      final host = await MuyonHost.open(root.path, modules: [module]);
      try {
        await host.modules.activate('recovery');
        await host.workspaces.database.write(
          (db) => db.execute(
            "CREATE TRIGGER deny_ocr_revocation BEFORE UPDATE ON module_grants WHEN NEW.module_id='recovery' AND NEW.capability='ocr' BEGIN SELECT RAISE(ABORT,'injected revoke failure'); END",
          ),
        );
        await expectLater(
          host.modules.revokeCapability('recovery', 'ocr'),
          throwsA(isA<SqliteException>()),
        );
        await host.modules.revokeCapability('recovery', 'transfer');
        expect(
          (await host.modules.activate('recovery')).status,
          ModuleStatus.failed,
        );
        expect(module.activations, 1);
        await host.workspaces.database.write(
          (db) => db.execute('DROP TRIGGER deny_ocr_revocation'),
        );
        await host.modules.revokeCapability('recovery', 'ocr');
        expect(
          (await host.modules.activate('recovery')).status,
          ModuleStatus.ready,
        );
        expect(host.grants.revoked('recovery'), {'ocr', 'transfer'});
        expect(module.lastResources!.capabilities.available, isEmpty);
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
      }
    },
  );

  test('overlapping revocations keep activation closed until both writes finish', () async {
    final root = Directory.systemTemp.createTempSync('overlapping-revokes-');
    final module = FakeV2Module(
      'parallel',
      features: {ModuleFeature.exchange},
      capabilities: {
        const CapabilityRequest(id: 'ocr', reason: 'scan'),
        const CapabilityRequest(id: 'transfer', reason: 'exchange'),
      },
    );
    final host = await MuyonHost.open(root.path, modules: [module]);
    final database = host.workspaces.database as ManagedConnection;
    final entered = Completer<void>(), release = Completer<void>();
    final previous = database.onCommit;
    Future<void>? second;
    var injected = false;
    try {
      await host.modules.activate('parallel');
      database.onCommit = () {
        previous?.call();
        final row = database.raw.select(
          "SELECT status FROM module_registry WHERE module_id='parallel'",
        );
        if (!injected &&
            row.isNotEmpty &&
            row.single['status'] == 'failed' &&
            host.grants.revoked('parallel').contains('ocr')) {
          injected = true;
          // Queue a barrier after the first revoke's durable failed record,
          // then the second revoke before the first async continuation resumes.
          database.exclusiveAsync((_) async {
            entered.complete();
            await release.future;
          });
          second = host.modules.revokeCapability('parallel', 'transfer');
        }
      };
      final first = host.modules.revokeCapability('parallel', 'ocr');
      await first;
      await entered.future.timeout(const Duration(seconds: 5));
      expect(host.grants.revoked('parallel'), {'ocr'});
      final activation = host.modules.activate('parallel');
      release.complete();
      await second;
      final state = await activation;
      expect(host.grants.revoked('parallel'), {
        'ocr',
        'transfer',
      }, reason: 'both durable withdrawals must survive reactivation');
      expect(state.status, ModuleStatus.failed);
      expect(module.activations, 1);
      expect(
        host.grants
            .forModule('parallel')
            .every((g) => !g.granted && g.policy == 'revoked'),
        isTrue,
      );
    } finally {
      database.onCommit = previous;
      if (!release.isCompleted) release.complete();
      await host.close();
      root.deleteSync(recursive: true);
    }
  });

  for (final restart in [false, true]) {
    test(
      'legacy research models revocation survives ${restart ? "restart" : "immediate reactivation"}',
      () async {
        final root = Directory.systemTemp.createTempSync('legacy-revoked-');
        var host = await MuyonHost.open(root.path);
        try {
          await host.activateResearch();
          expect(host.research, isNotNull);
          await host.modules.revokeCapability('research', 'models');
          if (restart) {
            await host.close();
            host = await MuyonHost.open(root.path);
          }
          await host.activateResearch();
          expect(host.modules.state('research').status, ModuleStatus.failed);
          expect(host.research, isNull);
          final decision = host.grants
              .forModule('research')
              .singleWhere((g) => g.capability == 'models');
          expect(decision.granted, isFalse);
          expect(decision.policy, 'revoked');
          expect(host.grants.revoked('research'), contains('models'));
        } finally {
          await host.close();
          root.deleteSync(recursive: true);
        }
      },
    );
  }

  test('API v3 module stays unavailable without activating', () async {
    final root = Directory.systemTemp.createTempSync('api3-admission-');
    final module = FakeV2Module('future', apiVersion: 3);
    final host = await MuyonHost.open(root.path, modules: [module]);
    expect(
      host.registry.unavailable['future'],
      contains('Unsupported module API v3'),
    );
    expect(module.activations, 0);
    await host.close();
    root.deleteSync(recursive: true);
  });

  test(
    'revocation during activation must prevent publishing stale runtime',
    () async {
      final root = Directory.systemTemp.createTempSync('xreview-revoke-');
      final module = PausedModule();
      final host = await MuyonHost.open(root.path, modules: [module]);
      final activation = host.modules.activate('paused');
      await module.entered.future.timeout(const Duration(seconds: 5));
      await host.modules.revokeCapability('paused', 'ocr');
      module.release.complete();
      final state = await activation;
      final allowed = module.lastResources!.capabilities.available;
      expect(host.modules.runtime<FakeRuntime>('paused'), isNull);
      expect(host.tools.inspect('paused.ping')!.available, isFalse);
      expect(
        () => module.lastResources!.capabilities.require<Object>('ocr'),
        throwsStateError,
      );
      await host.close();
      root.deleteSync(recursive: true);
      expect(
        state.status,
        ModuleStatus.failed,
        reason: 'revoked activation must not become ready',
      );
      expect(allowed, isNot(contains('ocr')));
    },
  );
  test(
    'module close must withdraw an approved channel before later send',
    () async {
      final root = Directory.systemTemp.createTempSync('xreview-close-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var sends = 0;
      server.listen((request) async {
        sends++;
        await request.drain<void>();
        request.response.write('ok');
        await request.response.close();
      });
      late HostChannel channel;
      final module = FakeV2Module(
        'sender',
        network: const NetworkPolicy(fixedHosts: {'127.0.0.1'}),
        onRegisterTools: (r) {
          channel = r.channel(
            ChannelSpec(
              name: 'send',
              description: 'test external channel',
              effect: ToolEffect.network,
              destination: const DestinationRule(fixedHosts: {'127.0.0.1'}),
              parameterSchema: const {
                'type': 'object',
                'properties': <String, Object?>{},
                'additionalProperties': false,
              },
            ),
          );
        },
      );
      final host = await MuyonHost.open(root.path, modules: [module]);
      await host.modules.activate('sender');
      final entered = Completer<void>(), release = Completer<void>();
      final cancellation = ToolCancellationToken();
      final operation = channel.run<String>(
        ChannelRequest(destination: 'http://127.0.0.1:${server.port}/send'),
        (guard) async {
          guard();
          entered.complete();
          await release.future;
          guard();
          final client = NativeHttp().client();
          try {
            final req = await client.postUrl(
              Uri.parse('http://127.0.0.1:${server.port}/send'),
            );
            req.write('payload');
            await (await req.close()).drain<void>();
            return 'sent';
          } finally {
            client.close(force: true);
          }
        },
        cancellation: cancellation,
        review: (_) async => true,
      );
      await entered.future.timeout(const Duration(seconds: 5));
      final closing = host.close();
      await Future.any([cancellation.whenCancelled, closing]);
      final available = host.tools.inspect('sender.send')!.available;
      release.complete();
      try {
        await operation;
      } catch (_) {
        // Channel wrapper reports cancellation to its caller.
      }
      await closing;
      await server.close(force: true);
      root.deleteSync(recursive: true);
      expect(available, isFalse, reason: "close withdraws channel authority");
      expect(
        sends,
        0,
        reason: 'closed module must not send even after a repeated guard',
      );
    },
  );
  test(
    'close drains an HTTP effect already sent before closing storage',
    () async {
      final root = Directory.systemTemp.createTempSync('close-after-send-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final arrived = Completer<void>(), releaseResponse = Completer<void>();
      final received = <int>[];
      server.listen((request) async {
        await for (final chunk in request) {
          received.addAll(chunk);
        }
        arrived.complete();
        await releaseResponse.future;
        request.response.write('ok');
        await request.response.close();
      });
      late HostChannel channel;
      final module = FakeV2Module(
        'sender',
        network: const NetworkPolicy(fixedHosts: {'127.0.0.1'}),
        onRegisterTools: (registrar) {
          channel = registrar.channel(
            ChannelSpec(
              name: 'send',
              description: 'held response',
              effect: ToolEffect.network,
              destination: const DestinationRule(fixedHosts: {'127.0.0.1'}),
              parameterSchema: const {
                'type': 'object',
                'properties': <String, Object?>{},
                'additionalProperties': false,
              },
            ),
          );
        },
      );
      final host = await MuyonHost.open(root.path, modules: [module]);
      await host.modules.activate('sender');
      String? invocationId;
      final operation = channel.run<String>(
        ChannelRequest(destination: 'http://127.0.0.1:${server.port}/send'),
        (guard) async {
          final client = NativeHttp().client();
          try {
            final request = await client.postUrl(
              Uri.parse('http://127.0.0.1:${server.port}/send'),
            );
            guard();
            request.write('sent payload');
            await (await request.close()).drain<void>();
            return 'sent';
          } finally {
            client.close(force: true);
          }
        },
        cancellation: ToolCancellationToken(),
        review: (preview) async {
          invocationId = preview.invocationId;
          return true;
        },
      );
      final settled = operation.then<Object?>(
        (value) => value,
        onError: (Object error) => error,
      );
      await arrived.future.timeout(const Duration(seconds: 5));
      var closed = false;
      final closing = host.close().then((_) {
        closed = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(closed, isFalse);
      expect(host.tools.inspect('sender.send')!.available, isFalse);
      expect(
        host.workspaces.database.raw.select('SELECT 1').single.values.single,
        1,
      );
      expect(host.tools.receiptFor(invocationId!)!.state, 'running');
      releaseResponse.complete();
      await settled;
      await closing;
      expect(String.fromCharCodes(received), 'sent payload');
      final inspected = sqlite3.open('${root.path}/muyon.sqlite');
      expect(
        inspected.select(
          'SELECT state FROM tool_invocation_receipts WHERE invocation_id=?',
          [invocationId],
        ).single['state'],
        'interrupted',
      );
      inspected.close();
      await server.close(force: true);
      root.deleteSync(recursive: true);
    },
  );
  test(
    'shutdown refuses new activation while draining admitted local work',
    () async {
      final root = Directory.systemTemp.createTempSync('close-admission-');
      final admitted = PausedModule();
      final later = FakeV2Module('later');
      final host = await MuyonHost.open(root.path, modules: [admitted, later]);
      final local = host.trackOperation(() async {
        await host.modules.activate('paused');
        expect(host.modules.runtime<FakeRuntime>('paused'), isNotNull);
      });
      await admitted.entered.future;
      final closing = host.close();
      await expectLater(host.modules.activate('later'), throwsStateError);
      expect(later.activations, 0);
      admitted.release.complete();
      await local;
      await closing;
      expect(later.activations, 0);
      root.deleteSync(recursive: true);
    },
  );
  test('optional dependency back-edge must not deadlock activation', () async {
    final root = Directory.systemTemp.createTempSync('xreview-cycle-');
    final host = await MuyonHost.open(
      root.path,
      modules: [
        FakeV2Module('aa', requires: ['cc'], optional: ['bb']),
        FakeV2Module('bb', requires: ['aa']),
        FakeV2Module('cc'),
      ],
    );
    var timedOut = false;
    try {
      await host.modules
          .activate('aa')
          .timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      timedOut = true;
    }
    if (timedOut) {
      // A failing implementation has a stuck activation; retain the failure
      // without waiting forever for its close drain.
      await host.personalAgent.close();
      await host.services.close();
      host.memoryReview.dispose();
      host.foundation.dispose();
      await host.storage.close();
    } else {
      await host.close();
    }
    root.deleteSync(recursive: true);
    expect(
      timedOut,
      isFalse,
      reason: 'optional dependency cycles must terminate',
    );
  });
  testWidgets('opening a declared v2 section must activate its module', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('xreview-home-');
    final module = FakeV2Module(
      'notes',
      displayName: 'XReview Notes',
      sections: [
        fakeSection('notes', body: const Scaffold(body: Text('XReview body'))),
      ],
    );
    final host = (await tester.runAsync(
      () => MuyonHost.open(root.path, modules: [module]),
    ))!;
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: PlatformShell(
          host: host,
          themeMode: ThemeMode.light,
          onTheme: (_) {},
          onRestore: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('XReview Notes'));
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (host.modules.state('notes').status != ModuleStatus.ready &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(host.close);
    root.deleteSync(recursive: true);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    expect(
      module.activations,
      1,
      reason: 'v2 section requires host activation before builder',
    );
  });
}

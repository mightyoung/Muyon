import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/features/hub/hub_publish.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/inquiry_hub_authority.dart';
import 'package:supplier_core/supplier_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mightyoung.muyon/secrets');
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  for (final change in ['address', 'token', 'close']) {
    test(
      'actual AppState $change during host review prevents any request',
      () async {
        final root = Directory.systemTemp.createTempSync('g3-state-');
        final host = await MuyonHost.open(root.path);
        try {
          await host.activateInquiry();
          final state = host.inquiry!.runtime.state;
          await state.saveHub(address: 'https://hub.invalid');
          final c = await state.hub(
            review: (p, c) async {
              if (change == 'address') {
                await state.saveHub(address: 'https://other.invalid');
              }
              if (change == 'token') {
                await state.saveHub(
                  address: 'https://hub.invalid',
                  token: 'changed',
                );
              }
              if (change == 'close') await host.inquiry!.close();
              return true;
            },
          );
          await expectLater(c!.status(), throwsA(isA<HubException>()));
          expect(
            host.tools.history(toolId: InquiryHubAuthority.toolId),
            isEmpty,
          );
          expect(
            host.tools.database.raw.select(
              'SELECT * FROM tool_approvals WHERE tool_id=?',
              [InquiryHubAuthority.toolId],
            ),
            isEmpty,
          );
        } finally {
          await host.close();
          root.deleteSync(recursive: true);
        }
      },
    );
  }

  test('actual host restart preserves pending publication and its original endpoint', () async {
    final root = Directory.systemTemp.createTempSync('g3-restart-');
    var host = await MuyonHost.open(root.path);
    try {
      await host.activateInquiry();
      final journal = host.inquiry!.runtime.state.hubJournal!;
      final draft = <String, Object?>{
        'publication_id': 'durable-id',
        'revision': 1,
      };
      await journal.reserve(
        'https://original.invalid',
        'original-center',
        draft,
        await hubDigest(draft),
      );
      await host.close();
      host = await MuyonHost.open(root.path);
      await host.activateInquiry();
      final state = host.inquiry!.runtime.state;
      expect(
        state.hubJournal!.unresolved('durable-id')!['endpoint'],
        'https://original.invalid',
      );
      await state.saveHub(address: 'https://other.invalid');
      final c = await state.hub(review: (p, c) async => true);
      await expectLater(
        c!.reconcile('durable-id'),
        throwsA(
          isA<HubException>().having(
            (e) => e.message,
            'original endpoint',
            contains('https://original.invalid'),
          ),
        ),
      );
      expect(host.tools.history(toolId: InquiryHubAuthority.toolId), isEmpty);
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'host review retains exact records/contact opt-in and recheck reconciles without POST retry',
    (tester) async {
      final prior = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prior);
      late Directory root;
      late MuyonHost host;
      late HttpServer server;
      var posts = 0;
      Map<String, Object?>? remote;
      final bodies = <Map<String, Object?>>[];
      await tester.runAsync(() async {
        root = Directory.systemTemp.createTempSync('g3-ui-');
        host = await MuyonHost.open(root.path);
        await host.activateInquiry();
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((r) async {
          final bytes = await r.fold<List<int>>([], (a, b) => a..addAll(b));
          r.response.headers.contentType = ContentType.json;
          if (r.uri.path.endsWith('/status')) {
            r.response.write(jsonEncode({'center_id': 'center'}));
          } else if (r.method == 'GET') {
            if (remote == null) {
              r.response.statusCode = 404;
              r.response.write('{}');
            } else {
              r.response.write(jsonEncode(remote));
            }
          } else {
            final body = (jsonDecode(utf8.decode(bytes)) as Map)
                .cast<String, Object?>();
            bodies.add(body);
            if (r.uri.path.endsWith('/preview')) {
              r.response.write('{}');
            } else {
              posts++;
              remote = {'origin': 'center', ...body};
              r.response.statusCode = 503;
              r.response.write('{}');
            }
          }
          await r.response.close();
        });
        await host.inquiry!.runtime.state.saveHub(
          address: 'http://127.0.0.1:${server.port}',
        );
      });
      addTearDown(() async {
        var closed = false;
        late Future<void> cleanup;
        await tester.runAsync(() async {
          cleanup = (() async {
            await server.close(force: true);
            await host.close();
            closed = true;
          })();
        });
        for (var i = 0; i < 100 && !closed; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(
          closed,
          isTrue,
          reason: 'real host cleanup must drain both widget and I/O clocks',
        );
        await tester.runAsync(() => cleanup);
        root.deleteSync(recursive: true);
      });
      final state = host.inquiry!.runtime.state;
      final id = state.store.save('supplier', {
        for (final f in Supplier.fields) f: null,
        'name': 'exact supplier',
        'aliases': <String>[],
        'categories': <String>[],
      });
      state.store.save('contact', {
        'supplier_id': id,
        'name': 'opt-in contact',
        'phone': '123-private',
        'wechat': null,
        'email': null,
        'notes': null,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showHubPublish(context, state, type: 'supplier', id: id),
                child: const Text('open publish'),
              ),
            ),
          ),
        ),
      );
      Future<void> until(Finder expected, {bool approve = true}) async {
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
          if (expected.evaluate().isNotEmpty) return;
          final allow = find.text('允许本次请求');
          if (approve && allow.evaluate().isNotEmpty) {
            await tester.tap(allow);
            await tester.pump();
          }
        }
        expect(expected, findsWidgets);
      }

      await tester.tap(find.text('open publish'));
      await until(find.textContaining('首次发布'));
      expect(find.text('同时共享联系人（1 位）'), findsOneWidget);
      expect(bodies.single['records'] as List, hasLength(1));
      await tester.tap(find.byType(CheckboxListTile));
      await until(find.textContaining('首次发布'));
      expect(bodies.last['records'] as List, hasLength(2));
      await tester.tap(find.text('发布'));
      await until(find.text('确认向中心发布'), approve: false);
      expect(find.textContaining('123-private'), findsOneWidget);
      expect(find.textContaining('POST http://127.0.0.1:'), findsOneWidget);
      await tester.tap(find.text('允许本次请求'));
      await until(find.text('重新核对'));
      expect(posts, 1);
      expect(find.textContaining('取消不代表远端撤回'), findsOneWidget);
      await tester.tap(find.text('重新核对'));
      await until(find.textContaining('中心已是最新'));
      expect(posts, 1);
      expect(
        bodies,
        hasLength(3),
        reason:
            'two reviewed previews and one write; reconciliation never POSTs',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    },
  );
}

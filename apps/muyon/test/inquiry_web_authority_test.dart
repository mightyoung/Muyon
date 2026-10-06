import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/features/ai/assistant_confirmation.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/inquiry_web_authority.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  test(
    'inquiry activation registers host-owned recorded web channel',
    () async {
      final root = Directory.systemTemp.createTempSync('g2-host-web-');
      final host = await MuyonHost.open(root.path);
      try {
        await host.activateInquiry();
        expect(host.inquiryError, isNull);
        final info = host.tools.inspect('inquiry.web.request');
        expect(info, isNotNull);
        expect(info!.descriptor.effect, ToolEffect.network);
        expect(info.providerId, 'inquiry');
        await host.inquiry!.close();
        expect(
          host.tools.inspect(InquiryWebAuthority.toolId)!.available,
          isFalse,
        );
        expect(
          host.tools.inspect(InquiryWebAuthority.toolId)!.unavailableReason,
          'Inquiry module is closed',
        );
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
      }
    },
  );

  for (final revoke in ['web', 'permission', 'session']) {
    test(
      'real hosted AppState $revoke revocation during UI review makes no grant/receipt',
      () async {
        final root = Directory.systemTemp.createTempSync('g2-state-');
        final host = await MuyonHost.open(root.path);
        try {
          await host.activateInquiry();
          final plugin = host.inquiry!;
          final state = plugin.runtime.state;
          state.assistantWebEnabled = true;
          final job = plugin.jobs.create(AiTask.conversation, {
            'question': 'fixture',
          });
          plugin.jobs.start(job.id);
          final web = state.createAssistantWebTools(
            job.id,
            review: (preview, cancel) async {
              if (revoke == 'web') state.assistantWebEnabled = false;
              if (revoke == 'permission') {
                state.assistantPermission = AssistantPermission.bypass;
              }
              if (revoke == 'session') plugin.jobs.invalidateAll();
              return true;
            },
          );
          final result = jsonDecode(
            await web.execute(
              'web_fetch',
              {'url': 'https://example.com/a'},
              callId: 'state',
              cancellation: AiCancellation(),
            ),
          );
          expect(result, contains('error'));
          expect(
            host.tools.history(toolId: InquiryWebAuthority.toolId),
            isEmpty,
          );
          expect(
            host.tools.database.raw.select(
              'SELECT * FROM tool_approvals WHERE tool_id=?',
              [InquiryWebAuthority.toolId],
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
  recordedChannelTests();
}

// Actual file SQLite and ToolRegistry; DNS and transport below are scripted
// application-owned fixtures, not native TLS, device or external network proof.
void recordedChannelTests() {
  group('recorded channel', () {
    late Directory root;
    late ManagedConnection db;
    late ToolRegistry registry;
    late InquiryWebAuthority authority;
    late DateTime now;
    late bool valid;
    late int dnsCalls, sends;
    late List<AssistantWebApprovalPreview> reviews;
    late AssistantWebResolver dns;
    late AssistantWebTransport transport;
    late AssistantWebReview review;
    List<String> states() => [
      for (final r in db.raw.select(
        'SELECT state FROM tool_invocation_receipts ORDER BY rowid',
      ))
        r['state'] as String,
    ];
    void receiptBeforeEffect(Uri uri) {
      final rows = db.raw.select(
        "SELECT r.state, a.state grant_state, a.destination, a.input_digest "
        "FROM tool_invocation_receipts r JOIN tool_approvals a ON a.identity_digest=r.identity_digest "
        "WHERE r.state='running'",
      );
      expect(rows, hasLength(1));
      expect(rows.single['grant_state'], 'consumed');
      expect(rows.single['destination'], uri.toString());
      expect(rows.single['input_digest'], reviews.last.parameterDigest);
    }

    AssistantWebResponse response({
      int status = 200,
      String? location,
      Stream<List<int>>? body,
      void Function()? close,
    }) => AssistantWebResponse(
      statusCode: status,
      contentType: 'text/plain',
      location: location,
      body: body ?? Stream.value(utf8.encode('bounded fixture')),
      close: close,
    );
    setUp(() {
      root = Directory.systemTemp.createTempSync('g2-sqlite-');
      db = ManagedConnection(sqlite3.open('${root.path}/host.sqlite'));
      installToolRegistrySchema(db.raw);
      now = DateTime.utc(2026, 10, 5);
      registry = ToolRegistry(
        database: db,
        clock: () => now,
        resolveScope: (scope) async =>
            ResolvedAssistantScope(requested: scope, objects: []),
      );
      authority = InquiryWebAuthority(registry);
      valid = true;
      dnsCalls = 0;
      sends = 0;
      reviews = [];
      review = (p, c) async {
        reviews.add(p);
        return true;
      };
      dns = (host) async {
        dnsCalls++;
        receiptBeforeEffect(reviews.last.destination);
        return [InternetAddress('93.184.216.34')];
      };
      transport = (uri, addresses, cancel) async {
        sends++;
        receiptBeforeEffect(uri);
        return response();
      };
    });
    tearDown(() async {
      await db.close();
      root.deleteSync(recursive: true);
    });
    AssistantWebTools tools({Duration? timeout}) => AssistantWebTools(
      hosted: true,
      sessionId: 'fixture-job',
      authority: authority,
      review: (p, c) => review(p, c),
      validateSession: () {
        if (!valid) throw StateError('Session/permission revoked');
      },
      resolver: (h) => dns(h),
      transport: (u, a, c) => transport(u, a, c),
      timeout: timeout ?? const Duration(seconds: 20),
    );
    Future<Map<String, dynamic>> fetch(
      AssistantWebTools web, {
      AiCancellation? cancel,
    }) async => jsonDecode(
      await web.execute(
        'web_fetch',
        {'url': 'https://example.com/a'},
        callId: 'same-model-call',
        cancellation: cancel ?? AiCancellation(),
      ),
    ) as Map<String, dynamic>;

    for (final close in [false, true]) {
      test(
        'concurrent invocation-bound operations stay separate; closed=$close',
        () async {
          final entered = Completer<void>();
          final released = Completer<List<InternetAddress>>();
          dns = (host) {
            dnsCalls++;
            if (dnsCalls == 2) entered.complete();
            return released.future;
          };
          transport = (uri, addresses, cancel) async {
            sends++;
            return response(
              body: Stream.value(utf8.encode('host=${uri.host}')),
            );
          };
          final web = tools();
          Future<Map<String, dynamic>> call(String host) async => jsonDecode(
            await web.execute(
              'web_fetch',
              {'url': 'https://$host/a'},
              callId: host,
              cancellation: AiCancellation(),
            ),
          ) as Map<String, dynamic>;
          final a = call('one.example'), b = call('two.example');
          await entered.future;
          expect(states(), ['running', 'running']);
          expect(
            db.raw
                .select('SELECT state FROM tool_approvals')
                .map((r) => r['state']),
            everyElement('consumed'),
          );
          if (close) authority.disable();
          released.complete([InternetAddress('93.184.216.34')]);
          final results = await Future.wait([a, b]);
          if (close) {
            expect(sends, 0);
            expect(states(), ['interrupted', 'interrupted']);
            expect(
              results.map((r) => r['network_outcome']),
              everyElement('interrupted'),
            );
          } else {
            expect(sends, 2);
            expect(results[0]['text'], 'host=one.example');
            expect(results[1]['text'], 'host=two.example');
            expect(states(), ['succeeded', 'succeeded']);
          }
        },
      );
    }
    test('registry calls cannot synthesize a trusted pending operation even with a host grant', () async {
      final request = ToolCallRequest(
        invocationId: 'no-pending',
        toolId: InquiryWebAuthority.toolId,
        scope: const AssistantScope.global(),
        destination: 'https://example.com/a',
        parameters: {
          'method': 'GET',
          'url': 'https://example.com/a',
          'sessionId': 'fixture-job',
          'maxBodyBytes': AssistantWebTools.maxBodyBytes,
        },
      );
      final grant = await registry.approve(await registry.prepare(request));
      final result = await registry.invoke(request.withApproval(grant));
      expect(result.status, ToolCallStatus.failed);
      expect(states(), ['failed']);
      expect([dnsCalls, sends], [0, 0]);
    });
    test('denial/missing review means zero DNS/send/receipt/grant', () async {
      review = (p, c) async => false;
      expect(await fetch(tools()), contains('error'));
      expect(
        await fetch(
          AssistantWebTools(
            hosted: true,
            authority: authority,
            resolver: dns,
            transport: transport,
          ),
        ),
        contains('error'),
      );
      expect([dnsCalls, sends], [0, 0]);
      expect(states(), isEmpty);
      expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
    });
    test('missing bridge fails closed but restored extract/product rows stay local', () async {
      final source = AssistantWebSnapshot.capture(
        url: 'https://example.com/a',
        title: '',
        fetchedAt: '2026-10-05T00:00:00Z',
        text: 'bounded fixture',
        truncated: false,
        jsonLd: [],
      );
      final web = AssistantWebTools(
        hosted: true,
        resolver: dns,
        transport: transport,
        restoredSnapshots: [source],
      );
      expect(await fetch(web), contains('error'));
      final extracted = jsonDecode(
        await web.execute(
          'web_extract',
          {
            'url': source.url,
            'keywords': ['bounded'],
          },
          callId: 'local',
          cancellation: AiCancellation(),
        ),
      );
      expect(extracted['text'], contains('bounded'));
      final rows = jsonDecode(
        await web.execute(
          'web_product_rows',
          {'source_id': source.id},
          callId: 'rows',
          cancellation: AiCancellation(),
        ),
      );
      expect(rows['source_id'], source.id);
      expect([dnsCalls, sends], [0, 0]);
      expect(states(), isEmpty);
    });
    test(
      'repeated calls need separate exact one-use approvals and receipts',
      () async {
        final web = tools();
        expect(await fetch(web), contains('source_id'));
        expect(await fetch(web), contains('source_id'));
        expect([dnsCalls, sends], [2, 2]);
        expect(states(), ['succeeded', 'succeeded']);
        expect(reviews.map((p) => p.invocationId).toSet(), hasLength(2));
        expect(
          reviews.map((p) => p.destination.toString()),
          everyElement('https://example.com/a'),
        );
        expect(
          db.raw
              .select('SELECT state FROM tool_approvals')
              .map((r) => r['state']),
          everyElement('consumed'),
        );
        expect(registry.history(), hasLength(2));
      },
    );
    for (final allow in [false, true]) {
      test(
        'redirect requires different exact destination approval: $allow',
        () async {
          transport = (uri, addresses, cancel) async {
            sends++;
            receiptBeforeEffect(uri);
            return uri.host == 'example.com'
                ? response(
                    status: 302,
                    location: 'https://other.example/b?q=changed',
                  )
                : response();
          };
          review = (p, c) async {
            reviews.add(p);
            return reviews.length == 1 || allow;
          };
          expect(await fetch(tools()), contains(allow ? 'source_id' : 'error'));
          expect(reviews.map((p) => p.destination.toString()), [
            'https://example.com/a',
            'https://other.example/b?q=changed',
          ]);
          expect(reviews.map((p) => p.parameterDigest).toSet(), hasLength(2));
          expect([dnsCalls, sends], allow ? [2, 2] : [1, 1]);
          expect(states(), allow ? ['succeeded', 'succeeded'] : ['succeeded']);
        },
      );
    }

    test('human review wait is excluded from cumulative I/O timeout', () async {
      final entered = Completer<void>();
      final confirmed = Completer<bool>();
      review = (p, c) {
        reviews.add(p);
        entered.complete();
        return confirmed.future;
      };
      final pending = fetch(tools(timeout: const Duration(milliseconds: 80)));
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect([dnsCalls, sends], [0, 0]);
      expect(states(), isEmpty);
      confirmed.complete(true);
      expect(await pending, contains('source_id'));
      expect(states(), ['succeeded']);
    });
    test('redirect hops share one total active I/O budget', () async {
      transport = (uri, addresses, cancel) async {
        sends++;
        receiptBeforeEffect(uri);
        await Future<void>.delayed(const Duration(milliseconds: 90));
        return uri.host == 'example.com'
            ? response(status: 302, location: 'https://other.example/b')
            : response();
      };
      final result = await fetch(
        tools(timeout: const Duration(milliseconds: 150)),
      );
      expect(result, contains('error'));
      expect(result['error'], contains('超时'));
      expect([dnsCalls, sends], [2, 2]);
      expect(states(), ['succeeded', 'interrupted']);
      // Let the deliberately uncancellable scripted transport settle.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    testWidgets('trusted host dialog binds exact destination for every call', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold(body: Text('fixture'));
            },
          ),
        ),
      );
      review = (p, c) {
        reviews.add(p);
        return confirmAssistantWebHostRequest(context, p, c);
      };
      late Future<Map<String, dynamic>> pending;
      await tester.runAsync(() async {
        pending = fetch(tools());
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('宿主确认本次网页请求'), findsOneWidget);
      expect(find.textContaining('GET https://example.com/a'), findsOneWidget);
      expect(states(), isEmpty);
      expect([dnsCalls, sends], [0, 0]);
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => pending), contains('error'));
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(() async {
          pending = fetch(tools());
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(find.text('宿主确认本次网页请求'), findsOneWidget);
        expect(sends, i);
        await tester.tap(find.text('允许此次请求'));
        await tester.pumpAndSettle();
        expect(await tester.runAsync(() => pending), contains('source_id'));
      }
      expect(reviews, hasLength(3));
      expect(states(), ['succeeded', 'succeeded']);
      await tester.pumpWidget(const SizedBox());
    });
    test('grant and receipt persistence failure means zero DNS/send', () async {
      db.raw.execute(
        "CREATE TRIGGER fail_grant BEFORE INSERT ON tool_approvals "
        "BEGIN SELECT RAISE(ABORT, 'fixture grant failure'); END",
      );
      expect(await fetch(tools()), contains('error'));
      expect([dnsCalls, sends], [0, 0]);
      db.raw.execute('DROP TRIGGER fail_grant');
      db.raw.execute(
        "CREATE TRIGGER fail_receipt BEFORE INSERT ON tool_invocation_receipts "
        "BEGIN SELECT RAISE(ABORT, 'fixture receipt failure'); END",
      );
      expect(await fetch(tools()), contains('error'));
      expect([dnsCalls, sends], [0, 0]);
      expect(states(), isEmpty);
      expect(
        db.raw.select('SELECT state FROM tool_approvals').single['state'],
        'issued',
      );
    });

    test('final receipt persistence failure stops redirect and reports uncertain outcome', () async {
      db.raw.execute(
        "CREATE TRIGGER fail_finish BEFORE UPDATE OF state ON tool_invocation_receipts "
        "BEGIN SELECT RAISE(ABORT, 'fixture final receipt failure'); END",
      );
      transport = (uri, addresses, cancel) async {
        sends++;
        receiptBeforeEffect(uri);
        return response(status: 302, location: 'https://other.example/b');
      };
      final result = await fetch(tools());
      expect(result['network_outcome'], 'interrupted');
      expect([dnsCalls, sends], [1, 1]);
      expect(reviews, hasLength(1));
      expect(states(), ['running']);
    });
    test('permission revocation while reading body stops cache and records interruption', () async {
      final chunks = StreamController<List<int>>();
      final entered = Completer<void>();
      var closed = false;
      transport = (uri, addresses, cancel) async {
        sends++;
        entered.complete();
        return response(
          body: chunks.stream,
          close: () {
            closed = true;
            chunks.close();
          },
        );
      };
      final web = tools();
      final pending = fetch(web);
      await entered.future;
      valid = false;
      chunks.add(utf8.encode('revoked body'));
      expect((await pending)['network_outcome'], 'interrupted');
      expect(web.snapshots, isEmpty);
      expect(states(), ['interrupted']);
      expect(closed, isTrue);
    });
    test('revocation during review means zero grants/DNS/send', () async {
      review = (p, c) async {
        valid = false;
        return true;
      };
      expect(await fetch(tools()), contains('error'));
      expect([dnsCalls, sends], [0, 0]);
      expect(states(), isEmpty);
    });
    for (final kind in ['session', 'expiry', 'provider']) {
      test('$kind revoked after asynchronous DNS prevents send', () async {
        dns = (host) async {
          dnsCalls++;
          await Future<void>.delayed(Duration.zero);
          if (kind == 'session') valid = false;
          if (kind == 'expiry') now = now.add(const Duration(minutes: 3));
          if (kind == 'provider') {
            registry.setAvailability(
              InquiryWebAuthority.toolId,
              available: false,
            );
          }
          return [InternetAddress('93.184.216.34')];
        };
        expect(await fetch(tools()), contains('error'));
        expect([dnsCalls, sends], [1, 0]);
        expect(states(), ['interrupted']);
        expect(registry.history().single.summary, contains('not undone'));
      });
    }
    test('cancel during DNS waits for durable interrupted receipt', () async {
      final entered = Completer<void>(),
          result = Completer<List<InternetAddress>>();
      final cancel = AiCancellation();
      dns = (host) {
        dnsCalls++;
        entered.complete();
        return result.future;
      };
      final rejected = expectLater(
        fetch(tools(), cancel: cancel),
        throwsA(isA<LlmException>()),
      );
      await entered.future;
      cancel.cancel();
      await rejected;
      expect([dnsCalls, sends], [1, 0]);
      expect(states(), ['interrupted']);
      result.complete([InternetAddress('93.184.216.34')]);
    });
    test(
      'receipt running through entire body; closes before success',
      () async {
        final chunks = StreamController<List<int>>(),
            entered = Completer<void>();
        var closed = false;
        transport = (uri, addresses, cancel) async {
          sends++;
          entered.complete();
          return response(body: chunks.stream, close: () => closed = true);
        };
        final pending = fetch(tools());
        await entered.future;
        expect(states(), ['running']);
        chunks.add(utf8.encode('whole body'));
        await chunks.close();
        expect(await pending, contains('source_id'));
        expect(states(), ['succeeded']);
        expect(closed, isTrue);
      },
    );
    for (final kind in ['timeout', 'body_error', 'body_limit', 'private_dns']) {
      test('truthful interrupted receipt: $kind', () async {
        var closed = false;
        final chunks = StreamController<List<int>>();
        if (kind == 'private_dns') {
          dns = (host) async {
            dnsCalls++;
            return [InternetAddress('127.0.0.1')];
          };
        } else {
          transport = (uri, addresses, cancel) async {
            sends++;
            return response(
              body: kind == 'timeout'
                  ? chunks.stream
                  : kind == 'body_error'
                  ? Stream.error(StateError('fixture body error'))
                  : Stream.value(
                      List.filled(AssistantWebTools.maxBodyBytes + 1, 65),
                    ),
              close: () {
                closed = true;
                if (kind == 'timeout') chunks.close();
              },
            );
          };
        }
        expect(
          await fetch(
            tools(
              timeout: kind == 'timeout'
                  ? const Duration(milliseconds: 40)
                  : null,
            ),
          ),
          contains('error'),
        );
        expect(states(), ['interrupted']);
        expect(sends, kind == 'private_dns' ? 0 : 1);
        if (kind != 'private_dns') expect(closed, isTrue);
        expect(
          registry.history().single.summary,
          contains('may already have happened'),
        );
        unawaited(chunks.close());
      });
    }
  });
}

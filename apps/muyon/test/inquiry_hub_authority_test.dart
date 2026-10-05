import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:muyon/app/inquiry_hub_authority.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  channelTests();
  test(
    'host activation registers an external hub publication channel',
    () async {
      final root = Directory.systemTemp.createTempSync('g3-host-');
      final host = await MuyonHost.open(root.path);
      try {
        await host.activateInquiry();
        expect(host.inquiryError, isNull);
        final channel = host.tools.inspect('inquiry.hub.request');
        expect(channel, isNotNull);
        expect(channel!.descriptor.effect, ToolEffect.network);
        expect(channel.descriptor.description, contains('write'));
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}

void channelTests() {
  group('actual registry and file SQLite hub', () {
    late Directory root;
    late ManagedConnection ledger, business;
    late ToolRegistry registry;
    late InquiryHubAuthority authority;
    late HubPublicationJournal journal;
    late HubTransport transport;
    late HubReview review;
    late List<HubApprovalPreview> reviews;
    late int effects, posts;
    late bool valid;
    final base = Uri.parse('https://hub.invalid');
    Map<String, Object?> draft() => {
      'publication_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'revision': 1,
      'withdrawn': false,
      'root': {'entity_type': 'supplier', 'entity_id': 'root'},
      'records': [
        {
          'entity_type': 'supplier',
          'entity_id': 'root',
          'source_version': 1,
          'data': {'name': 'private supplier', 'phone': 'private contact'},
        },
      ],
    };
    HubResponse response(Object value, [int status = 200]) =>
        HubResponse(status, utf8.encode(jsonEncode(value)));
    List<String> states() => [
      for (final r in ledger.raw.select(
        'SELECT state FROM tool_invocation_receipts ORDER BY rowid',
      ))
        r['state'] as String,
    ];
    void beforeEffect(HubRequest request) {
      final rows = ledger.raw.select(
        "SELECT r.state,a.state grant_state,a.destination,a.input_digest FROM tool_invocation_receipts r JOIN tool_approvals a ON a.identity_digest=r.identity_digest WHERE r.state='running'",
      );
      expect(rows, hasLength(1));
      expect(rows.single['grant_state'], 'consumed');
      expect(rows.single['destination'], request.destination.toString());
      expect(rows.single['input_digest'], reviews.last.parameterDigest);
      if (request.publishes) {
        expect(
          journal.read(
            base.toString(),
            draft()['publication_id']! as String,
          )!['state'],
          'pending',
        );
      }
    }

    HubClient client({AiCancellation? cancel, HubReview? decision}) =>
        HubClient(
          base,
          hosted: true,
          authority: authority,
          journal: journal,
          review: decision ?? (p, c) => review(p, c),
          cancellation: cancel,
          validateSession: () {
            if (!valid) throw StateError('revoked');
          },
          transport: (r, t, d, c, g, s) => transport(r, t, d, c, g, s),
        );
    Future<HubClient> ready({AiCancellation? cancel}) async {
      final c = client(cancel: cancel);
      await c.status();
      return c;
    }

    setUp(() {
      root = Directory.systemTemp.createTempSync('g3-sqlite-');
      ledger = ManagedConnection(sqlite3.open('${root.path}/host.sqlite'));
      business = ManagedConnection(sqlite3.open('${root.path}/hub.sqlite'));
      installToolRegistrySchema(ledger.raw);
      HubPublicationJournal.initializeSchema(business.raw);
      journal = HubPublicationJournal(business.raw, write: business.write);
      registry = ToolRegistry(
        database: ledger,
        resolveScope: (s) async =>
            ResolvedAssistantScope(requested: s, objects: []),
      );
      authority = InquiryHubAuthority(registry);
      reviews = [];
      effects = 0;
      posts = 0;
      valid = true;
      review = (p, c) async {
        reviews.add(p);
        return true;
      };
      transport = (r, t, d, c, g, s) async {
        g();
        beforeEffect(r);
        effects++;
        s();
        if (r.publishes) {
          posts++;
          return response({'revision': 1});
        }
        if (r.destination.path.endsWith('/status')) {
          return response({'center_id': 'center'});
        }
        return response({}, 404);
      };
    });
    tearDown(() async {
      await business.close();
      await ledger.close();
      root.deleteSync(recursive: true);
    });

    test('missing bridge or journal fails closed before transport', () async {
      for (final withJournal in [false, true]) {
        final c = HubClient(
          base,
          hosted: true,
          journal: withJournal ? journal : null,
          authority: withJournal ? null : authority,
          transport: transport,
        );
        await expectLater(c.status(), throwsA(isA<HubException>()));
      }
      expect(effects, 0);
      expect(states(), isEmpty);
    });
    test(
      'denied and missing trusted review create no grant or effect',
      () async {
        review = (p, c) async => false;
        await expectLater(client().status(), throwsA(isA<HubException>()));
        final c = HubClient(
          base,
          hosted: true,
          authority: authority,
          journal: journal,
          transport: transport,
        );
        await expectLater(c.status(), throwsA(isA<HubException>()));
        expect(effects, 0);
        expect(states(), isEmpty);
        expect(ledger.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      },
    );
    test(
      'exact frozen body approved; only digest enters durable host log',
      () async {
        final c = await ready();
        final payload = draft();
        review = (p, c) async {
          reviews.add(p);
          if (p.request.publishes) {
            expect(p.payloadDigest, await hubDigest(draft()));
            expect(
              () => (p.request.body as Map)['revision'] = 9,
              throwsUnsupportedError,
            );
            payload['revision'] = 9;
          }
          return true;
        };
        transport = (r, t, d, c, g, s) async {
          g();
          beforeEffect(r);
          s();
          posts++;
          expect((r.body as Map)['revision'], 1);
          expect(r.encodedBody, hubCanonical(draft()));
          return response({'revision': 1});
        };
        expect((await c.publish(payload))['revision'], 1);
        expect(posts, 1);
        expect(states(), ['succeeded', 'succeeded']);
        final dump = ledger.raw
            .select('SELECT * FROM tool_invocation_receipts')
            .toString();
        expect(dump, isNot(contains('private contact')));
        expect(dump, isNot(contains('private supplier')));
        expect(
          journal.read(
            base.toString(),
            draft()['publication_id']! as String,
          )!['state'],
          'applied',
        );
      },
    );
    for (final failure in [
      'timeout',
      'reset',
      'parse',
      'revision',
      'cancel',
      'receipt',
      'journal',
    ]) {
      test(
        'after send $failure is durable uncertain and blocks new client',
        () async {
          final cancel = AiCancellation();
          final c = await ready(cancel: cancel);
          transport = (r, t, d, k, g, s) async {
            g();
            beforeEffect(r);
            s();
            posts++;
            if (failure == 'timeout') throw TimeoutException('fixture');
            if (failure == 'reset') throw const SocketException('fixture');
            if (failure == 'parse') return HubResponse(200, [0xff]);
            if (failure == 'revision') return response({'revision': 2});
            if (failure == 'cancel') {
              cancel.cancel();
              return response({'revision': 1});
            }
            if (failure == 'receipt') {
              ledger.raw.execute(
                "CREATE TRIGGER fail_finish BEFORE UPDATE OF state ON tool_invocation_receipts BEGIN SELECT RAISE(ABORT,'fixture'); END",
              );
            }
            if (failure == 'journal') {
              business.raw.execute(
                "CREATE TRIGGER fail_finish BEFORE UPDATE OF state ON hub_attempts BEGIN SELECT RAISE(ABORT,'fixture'); END",
              );
            }
            return response({'revision': 1});
          };
          await expectLater(
            c.publish(draft()),
            throwsA(
              isA<HubException>().having(
                (e) => e.message,
                'truthful',
                contains('不代表远端撤回'),
              ),
            ),
          );
          expect(
            journal.read(
              base.toString(),
              draft()['publication_id']! as String,
            )!['state'],
            'pending',
          );
          if (failure == 'receipt') {
            ledger.raw.execute('DROP TRIGGER fail_finish');
          }
          if (failure == 'journal') {
            business.raw.execute('DROP TRIGGER fail_finish');
          }
          await business.close();
          business = ManagedConnection(sqlite3.open('${root.path}/hub.sqlite'));
          journal = HubPublicationJournal(business.raw, write: business.write);
          transport = (r, t, d, c, g, s) async {
            g();
            effects++;
            if (r.publishes) {
              s();
              posts++;
            }
            return response({'center_id': 'center'});
          };
          final next = await ready();
          await expectLater(
            next.publish(draft()),
            throwsA(isA<HubException>()),
          );
          expect(posts, 1);
        },
      );
    }
    test('lost success reconciles exact business data after reopen and never reposts', () async {
      final c = await ready();
      transport = (r, t, d, c, g, s) async {
        g();
        s();
        posts++;
        throw TimeoutException('lost response');
      };
      await expectLater(c.publish(draft()), throwsA(isA<HubException>()));
      await business.close();
      business = ManagedConnection(sqlite3.open('${root.path}/hub.sqlite'));
      journal = HubPublicationJournal(business.raw, write: business.write);
      transport = (r, t, d, c, g, s) async {
        g();
        beforeEffect(r);
        expect(r.method, 'GET');
        return response(
          r.destination.path.endsWith('/status')
              ? {'center_id': 'center'}
              : {
                  'origin': 'center',
                  ...draft(),
                  'server_received_at': 'metadata ignored',
                },
        );
      };
      final next = await ready();
      expect(
        await next.reconcile(draft()['publication_id']! as String),
        isTrue,
      );
      expect((await next.publish(draft()))['already_applied'], isTrue);
      expect(posts, 1);
      expect(states().last, 'succeeded');
    });
    for (final result in [
      'absent',
      'different',
      'newer',
      'origin',
      'denied',
      'query failure',
    ]) {
      test(
        'reconciliation $result never unlocks unresolved publication',
        () async {
          final c = await ready();
          transport = (r, t, d, c, g, s) async {
            g();
            s();
            posts++;
            throw TimeoutException('lost');
          };
          await expectLater(c.publish(draft()), throwsA(isA<HubException>()));
          transport = (r, t, d, c, g, s) async {
            g();
            beforeEffect(r);
            if (result == 'query failure') {
              throw const SocketException('offline');
            }
            if (result == 'absent') return response({}, 404);
            final remote = {'origin': 'center', ...draft()};
            if (result == 'different') {
              remote['records'] = [
                {'same_revision': 'different content'},
              ];
            }
            if (result == 'newer') remote['revision'] = 2;
            if (result == 'origin') remote['origin'] = 'other';
            return response(remote);
          };
          if (result == 'denied') review = (p, c) async => false;
          await expectLater(
            c.reconcile(draft()['publication_id']! as String),
            throwsA(isA<HubException>()),
          );
          await expectLater(
            c.publish({...draft(), 'revision': 2}),
            throwsA(isA<HubException>()),
          );
          expect(posts, 1);
          expect(
            journal.read(
              base.toString(),
              draft()['publication_id']! as String,
            )!['state'],
            isNot('applied'),
          );
        },
      );
    }
    test(
      'concurrent clients reserve one attempt before any async review',
      () async {
        final a = await ready(), b = await ready();
        final entered = Completer<void>(), release = Completer<void>();
        transport = (r, t, d, c, g, s) async {
          g();
          beforeEffect(r);
          s();
          posts++;
          entered.complete();
          await release.future;
          g();
          return response({'revision': 1});
        };
        final pending = a.publish(draft());
        await entered.future;
        await expectLater(b.publish(draft()), throwsA(isA<HubException>()));
        release.complete();
        await pending;
        expect(posts, 1);
      },
    );
    for (final boundary in ['review', 'wait', 'closed']) {
      test('revocation at $boundary blocks next effect', () async {
        if (boundary == 'review') {
          review = (p, c) async {
            valid = false;
            return true;
          };
        }
        if (boundary == 'closed') authority.disable();
        if (boundary == 'wait') {
          transport = (r, t, d, c, g, s) async {
            await Future<void>.value();
            valid = false;
            g();
            s();
            effects++;
            return response({});
          };
        }
        await expectLater(client().status(), throwsA(isA<HubException>()));
        expect(effects, 0);
      });
    }
    for (final table in [
      'tool_approvals',
      'tool_invocation_receipts',
      'hub_attempts',
    ]) {
      test('$table persistence failure prevents publication send', () async {
        final c = await ready();
        final db = table == 'hub_attempts' ? business : ledger;
        db.raw.execute(
          "CREATE TRIGGER fail_start BEFORE INSERT ON $table BEGIN SELECT RAISE(ABORT,'fixture'); END",
        );
        await expectLater(c.publish(draft()), throwsA(anything));
        expect(posts, 0);
        expect(
          journal.read(base.toString(), draft()['publication_id']! as String),
          isNull,
        );
      });
    }
    test(
      'known no-send denial releases reservation for separately reviewed retry',
      () async {
        final c = await ready();
        review = (p, c) async => false;
        await expectLater(c.publish(draft()), throwsA(isA<HubException>()));
        expect(posts, 0);
        expect(
          journal.read(base.toString(), draft()['publication_id']! as String),
          isNull,
        );
        review = (p, c) async {
          reviews.add(p);
          return true;
        };
        await c.publish(draft());
        expect(posts, 1);
      },
    );
    for (final failure in ['503', 'reset', 'timeout']) {
      test(
        'native loopback $failure blocks a second POST and reconciles exact state',
        () async {
          var nativePosts = 0;
          Map<String, Object?>? remote;
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            final bytes = await request.fold<List<int>>(
              [],
              (a, b) => a..addAll(b),
            );
            request.response.headers.contentType = ContentType.json;
            if (request.uri.path.endsWith('/status')) {
              request.response.write(jsonEncode({'center_id': 'center'}));
            } else if (request.method == 'POST') {
              nativePosts++;
              remote = {
                'origin': 'center',
                ...(jsonDecode(utf8.decode(bytes)) as Map)
                    .cast<String, Object?>(),
              };
              if (failure == 'reset') {
                final socket = await request.response.detachSocket();
                socket.destroy();
                return;
              }
              if (failure == 'timeout') {
                await Future<void>.delayed(const Duration(milliseconds: 120));
              }
              request.response.statusCode = 503;
              request.response.write('{}');
            } else {
              request.response.write(jsonEncode(remote));
            }
            await request.response.close();
          });
          final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
          HubClient native() => HubClient(
            endpoint,
            hosted: true,
            authority: authority,
            journal: journal,
            review: (p, c) => review(p, c),
            timeout: const Duration(milliseconds: 80),
          );
          try {
            final c = native();
            await c.status();
            await expectLater(c.publish(draft()), throwsA(isA<HubException>()));
            final next = native();
            await next.status();
            await expectLater(
              next.publish(draft()),
              throwsA(isA<HubException>()),
            );
            expect(nativePosts, 1);
            expect(
              await next.reconcile(draft()['publication_id']! as String),
              isTrue,
            );
            expect((await next.publish(draft()))['already_applied'], isTrue);
            expect(nativePosts, 1);
          } finally {
            await server.close(force: true);
          }
        },
      );
    }
    test(
      'native redirects are rejected without following or leaking credentials',
      () async {
        var redirected = 0;
        final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        target.listen((r) async {
          redirected++;
          await r.response.close();
        });
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((r) async {
          await r.drain<void>();
          r.response.statusCode = 302;
          r.response.headers.set(
            'location',
            'http://127.0.0.1:${target.port}/stolen',
          );
          await r.response.close();
        });
        try {
          final c = HubClient(
            Uri.parse('http://127.0.0.1:${server.port}'),
            token: 'fixture-secret',
            hosted: true,
            authority: authority,
            journal: journal,
            review: (p, c) => review(p, c),
          );
          await expectLater(c.status(), throwsA(isA<HubException>()));
          expect(redirected, 0);
          expect(reviews, hasLength(1));
          expect(
            ledger.raw
                .select('SELECT * FROM tool_invocation_receipts')
                .toString(),
            isNot(contains('fixture-secret')),
          );
        } finally {
          await server.close(force: true);
          await target.close(force: true);
        }
      },
    );
    test('reconciliation query cancellation retains pending and same revision is insufficient', () async {
      final c = await ready();
      transport = (r, t, d, c, g, s) async {
        g();
        s();
        posts++;
        throw TimeoutException('lost');
      };
      await expectLater(c.publish(draft()), throwsA(isA<HubException>()));
      transport = (r, t, d, c, g, s) async {
        g();
        c.cancel();
        return response({'origin': 'center', ...draft()});
      };
      await expectLater(
        c.reconcile(draft()['publication_id']! as String),
        throwsA(isA<HubException>()),
      );
      expect(
        journal.read(
          base.toString(),
          draft()['publication_id']! as String,
        )!['state'],
        'pending',
      );
    });
    test('changed origin cannot reuse a prepared origin binding', () async {
      final c = await ready();
      await expectLater(
        c.publish(draft(), origin: 'different-center'),
        throwsA(isA<HubException>()),
      );
      expect(posts, 0);
    });
    test('changing endpoint cannot bypass an unresolved publication', () async {
      await journal.reserve(
        base.toString(),
        'center',
        draft(),
        await hubDigest(draft()),
      );
      final other = HubClient(
        Uri.parse('https://other.invalid'),
        hosted: true,
        authority: authority,
        journal: journal,
        review: (p, c) => review(p, c),
        transport: (r, t, d, c, g, s) async {
          g();
          if (r.publishes) {
            s();
            posts++;
          }
          return response({'center_id': 'other-center'});
        },
      );
      await other.status();
      await expectLater(
        other.reconcile(draft()['publication_id']! as String),
        throwsA(isA<HubException>()),
      );
      await expectLater(other.publish(draft()), throwsA(isA<HubException>()));
      expect(posts, 0);
    });
    test('search history publication and preview each require a distinct recorded approval', () async {
      final c = client();
      transport = (r, t, d, c, g, s) async {
        g();
        beforeEffect(r);
        s();
        effects++;
        return response({'items': []});
      };
      await c.search(q: 'fixture');
      await c.history('center', 'id');
      await c.publication('center', 'id');
      await c.preview(draft());
      expect(reviews.map((p) => p.invocationId).toSet(), hasLength(4));
      expect(reviews.map((p) => p.request.method), [
        'GET',
        'GET',
        'GET',
        'POST',
      ]);
      expect(reviews.last.request.body, draft());
      expect(states(), everyElement('succeeded'));
      expect(effects, 4);
    });
    test(
      'untrusted direct registry call cannot create an application operation',
      () async {
        final request = ToolCallRequest(
          invocationId: 'untrusted',
          toolId: InquiryHubAuthority.toolId,
          scope: const AssistantScope.global(),
          destination: 'https://hub.invalid/v1/status',
          parameters: {
            'method': 'GET',
            'url': 'https://hub.invalid/v1/status',
            'payloadDigest': await hubDigest(null),
            'publishes': false,
          },
        );
        final prepared = await registry.prepare(request);
        final grant = await registry.approve(prepared);
        final result = await registry.invoke(request.withApproval(grant));
        expect(result.status, isNot(ToolCallStatus.succeeded));
        expect(effects, 0);
      },
    );
    test('a past applied receipt cannot claim current success after remote disappears', () async {
      final c = await ready();
      final attempt = await journal.reserve(
        base.toString(),
        'center',
        draft(),
        await hubDigest(draft()),
      );
      await journal.applied(attempt);
      await expectLater(c.publish(draft()), throwsA(isA<HubException>()));
      expect(posts, 0);
      expect(reviews.last.request.method, 'GET');
      expect(
        reviews.last.request.destination.path,
        contains('/v1/publications/'),
      );
    });
    for (final outcome in ['different', 'denied', 'failure']) {
      test(
        'past applied receipt with $outcome actual query never succeeds or POSTs',
        () async {
          final c = await ready();
          final attempt = await journal.reserve(
            base.toString(),
            'center',
            draft(),
            await hubDigest(draft()),
          );
          await journal.applied(attempt);
          if (outcome == 'denied') review = (p, c) async => false;
          transport = (r, t, d, c, g, s) async {
            g();
            expect(r.method, 'GET');
            if (outcome == 'failure') throw const SocketException('fixture');
            return response({'origin': 'center', ...draft(), 'records': []});
          };
          await expectLater(c.publish(draft()), throwsA(isA<HubException>()));
          expect(posts, 0);
          expect(
            journal.read(
              base.toString(),
              draft()['publication_id']! as String,
            )!['state'],
            'applied',
            reason: 'historical acceptance evidence is retained',
          );
        },
      );
    }
    test('prepared crash window remains blocked across restart', () async {
      await journal.reserve(
        base.toString(),
        'center',
        draft(),
        await hubDigest(draft()),
      );
      await business.close();
      business = ManagedConnection(sqlite3.open('${root.path}/hub.sqlite'));
      journal = HubPublicationJournal(business.raw, write: business.write);
      final c = await ready();
      await expectLater(c.publish(draft()), throwsA(isA<HubException>()));
      expect(posts, 0);
    });
  });
}

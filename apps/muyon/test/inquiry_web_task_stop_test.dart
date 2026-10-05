import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/app/app_state.dart';
import 'package:inquiry_module/src/app/theme.dart';
import 'package:inquiry_module/src/features/ai/ask_page.dart';
import 'package:muyon/app/inquiry_web_authority.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';

// Actual AskPage/conversation and host registry/file SQLite. Model, DNS and
// HTTP transport are scripted application-owned fixtures; no native TLS proof.
class ConversationState extends AppState {
  ConversationState(
    super.store,
    super.dataDir,
    this.authority, {
    this.redirect = false,
    this.stallBody = false,
    this.requestTimeout = const Duration(seconds: 20),
  }) : super.test();
  final InquiryWebAuthority authority;
  final bool redirect;
  final bool stallBody;
  final Duration requestTimeout;
  StreamController<List<int>>? body;
  AiCancellation? owningCancellation;
  final reviews = <AssistantWebApprovalPreview>[];
  final reviewTokens = <AiCancellation>[];
  int modelCalls = 0, dnsCalls = 0, sends = 0;

  @override
  Future<LlmClient?> llm({AiCancellation? cancellation}) async {
    owningCancellation = cancellation;
    return LlmClient(
      const LlmConfig(apiKey: 'fixture'),
      transport: (_) async {
        modelCalls++;
        return {
          'choices': [
            {
              'message': modelCalls == 1
                  ? {
                      'tool_calls': [
                        {
                          'id': 'fetch',
                          'type': 'function',
                          'function': {
                            'name': 'web_fetch',
                            'arguments': jsonEncode({
                              'url': 'https://one.example/a',
                            }),
                          },
                        },
                        {
                          'id': 'after-stop',
                          'type': 'function',
                          'function': {
                            'name': 'open_page',
                            'arguments': jsonEncode({'page': 'data'}),
                          },
                        },
                      ],
                    }
                  : {'content': 'continued after tool'},
            },
          ],
        };
      },
    );
  }

  @override
  AssistantWebTools createAssistantWebTools(
    String jobId, {
    AssistantWebReview? review,
  }) => AssistantWebTools(
    timeout: requestTimeout,
    hosted: true,
    sessionId: jobId,
    authority: authority,
    validateSession: () => validateAssistantSession(jobId),
    review: (preview, child) {
      reviews.add(preview);
      reviewTokens.add(child);
      return review!(preview, child);
    },
    resolver: (_) async {
      dnsCalls++;
      return [InternetAddress('93.184.216.34')];
    },
    transport: (uri, addresses, child) async {
      sends++;
      return AssistantWebResponse(
        statusCode: redirect ? 302 : 200,
        contentType: 'text/plain',
        location: redirect ? 'https://two.example/b' : null,
        body: stallBody
            ? (body = StreamController<List<int>>()).stream
            : Stream.value(utf8.encode('fixture body')),
        close: () => body?.close(),
      );
    },
    restoredSnapshots: assistantWebSnapshots(jobId),
    onSnapshot: (source) => saveAssistantWebSnapshot(jobId, source),
  );
}

Future<void> advance(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  for (final redirect in [false, true]) {
    testWidgets(
      'AskPage host Stop task cancels owner and blocks later tools/model; redirect=$redirect',
      (tester) async {
        final root = Directory.systemTemp.createTempSync('g2-task-stop-');
        final db = ManagedConnection(sqlite3.open('${root.path}/host.sqlite'));
        installToolRegistrySchema(db.raw);
        final registry = ToolRegistry(
          database: db,
          resolveScope: (scope) async =>
              ResolvedAssistantScope(requested: scope, objects: []),
        );
        final store = Store.open(
          '${root.path}/business.sqlite',
          device: 'fixture',
        );
        final state = ConversationState(
          store,
          root,
          InquiryWebAuthority(registry),
          redirect: redirect,
        );
        state.assistantWebEnabled = true;
        state.assistantPermission = AssistantPermission.bypass;
        var laterToolCalls = 0;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(),
              home: Scaffold(
                body: AskPage(
                  state: state,
                  onOpenPage: (_) => laterToolCalls++,
                ),
              ),
            ),
          );
          await tester.enterText(find.byType(TextField), 'fixture web request');
          await tester.pump();
          await tester.tap(find.byTooltip('发送'));
          await advance(tester);
          expect(find.text('宿主确认本次网页请求'), findsOneWidget);
          expect(state.owningCancellation?.isCancelled, isFalse);
          if (redirect) {
            await tester.tap(find.text('允许此次请求'));
            await advance(tester);
            expect(
              find.textContaining('GET https://two.example/b'),
              findsOneWidget,
            );
            expect(registry.history().single.status, ToolCallStatus.succeeded);
            expect([state.dnsCalls, state.sends], [1, 1]);
          }
          await tester.tap(find.text('停止任务'));
          await advance(tester);
          expect(
            state.owningCancellation?.isCancelled,
            isTrue,
            reason: 'Explicit host-dialog Stop must cancel the owning AskPage conversation',
          );
          expect(state.modelCalls, 1);
          expect(laterToolCalls, 0);
          expect(state.reviews, hasLength(redirect ? 2 : 1));
          expect([state.dnsCalls, state.sends], redirect ? [1, 1] : [0, 0]);
          expect(
            db.raw.select('SELECT * FROM tool_approvals'),
            hasLength(redirect ? 1 : 0),
          );
          expect(
            db.raw.select('SELECT * FROM tool_invocation_receipts'),
            hasLength(redirect ? 1 : 0),
          );
          if (redirect) {
            expect(registry.history().single.status, ToolCallStatus.succeeded);
          }
          expect(state.aiTasks.single.status, 'paused');
          expect(find.text('宿主确认本次网页请求'), findsNothing);
          expect(find.byType(AskPage), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          state.owningCancellation?.cancel();
          await tester.pumpWidget(const SizedBox());
          await advance(tester);
          await tester.runAsync(state.shutdown);
          state.dispose();
          store.close();
          await tester.runAsync(db.close);
          root.deleteSync(recursive: true);
        }
      },
    );
  }
  for (final outcome in [
    'success_cleanup',
    'request_timeout',
    'stale_request',
  ]) {
    testWidgets('AskPage child $outcome stays isolated from owning task', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('g2-child-isolation-');
      final db = ManagedConnection(sqlite3.open('${root.path}/host.sqlite'));
      installToolRegistrySchema(db.raw);
      final registry = ToolRegistry(
        database: db,
        resolveScope: (scope) async =>
            ResolvedAssistantScope(requested: scope, objects: []),
      );
      final store = Store.open(
        '${root.path}/business.sqlite',
        device: 'fixture',
      );
      final state = ConversationState(
        store,
        root,
        InquiryWebAuthority(registry),
        stallBody: outcome == 'request_timeout',
        requestTimeout: outcome == 'request_timeout'
            ? const Duration(milliseconds: 40)
            : const Duration(seconds: 20),
      );
      state.assistantWebEnabled = true;
      state.assistantPermission = AssistantPermission.bypass;
      var laterToolCalls = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: AskPage(state: state, onOpenPage: (_) => laterToolCalls++),
            ),
          ),
        );
        await tester.enterText(
          find.byType(TextField),
          'fixture child isolation',
        );
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await advance(tester);
        expect(find.text('宿主确认本次网页请求'), findsOneWidget);
        if (outcome == 'stale_request') {
          state.reviewTokens.single.cancel('fixture stale request');
        } else {
          await tester.tap(find.text('允许此次请求'));
        }
        await advance(tester);
        expect(state.owningCancellation?.isCancelled, isFalse);
        expect(state.reviewTokens.single.isCancelled, isTrue);
        expect(state.modelCalls, 2);
        expect(laterToolCalls, 1);
        expect(state.aiTasks.single.status, 'finished');
        expect(find.text('宿主确认本次网页请求'), findsNothing);
        expect(find.byType(AskPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (outcome == 'stale_request') {
          expect([state.dnsCalls, state.sends], [0, 0]);
          expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
          expect(registry.history(), isEmpty);
        } else {
          expect([state.dnsCalls, state.sends], [1, 1]);
          expect(
            registry.history().single.status,
            outcome == 'request_timeout'
                ? ToolCallStatus.interrupted
                : ToolCallStatus.succeeded,
          );
        }
      } finally {
        state.owningCancellation?.cancel();
        await tester.pumpWidget(const SizedBox());
        await advance(tester);
        await tester.runAsync(state.shutdown);
        state.dispose();
        store.close();
        await tester.runAsync(db.close);
        root.deleteSync(recursive: true);
      }
    });
  }
}

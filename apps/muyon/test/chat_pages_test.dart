import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/chat/chat_list_page.dart';
import 'package:muyon/screens/chat/chat_models.dart';
import 'package:muyon/screens/chat/chat_thread_page.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/fake_chat_backend.dart';

const peer = 'AA:BB:CC';

void main() {
  late FakeChatBackend backend;
  setUp(() => backend = FakeChatBackend()..addThread(peer));

  Widget wrap(Widget child, {double scale = 1}) => MaterialApp(
    theme: muyonTheme(Brightness.light),
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: c!,
    ),
    home: Scaffold(body: child),
  );

  Widget list() => wrap(ChatListPage(backend: backend));
  Widget thread({double scale = 1}) => wrap(
    ChatThreadPage(backend: backend, peerFingerprint: peer),
    scale: scale,
  );

  void size(WidgetTester tester, double w) {
    tester.view.physicalSize = Size(w, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text).first;
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('list', () {
    testWidgets('empty state explains pairing', (tester) async {
      backend = FakeChatBackend();
      await tester.pumpWidget(list());
      expect(find.textContaining('还没有对话'), findsOneWidget);
    });

    testWidgets('shows status, unread badge and last message', (tester) async {
      backend.add(peer, direction: ChatDirection.incoming, body: '你好');
      await tester.pumpWidget(list());
      expect(find.text('我的笔记本'), findsOneWidget);
      expect(find.text('在线\n你好'), findsOneWidget);
      expect(find.byType(Badge), findsOneWidget);
      backend.setPeer(peer, online: false);
      await tester.pump();
      expect(find.textContaining('离线'), findsOneWidget);
      backend.setPeer(peer, paired: false);
      await tester.pump();
      expect(find.textContaining('未配对'), findsOneWidget);
    });
  });

  group('thread', () {
    for (final w in [320.0, 390.0, 430.0, 1280.0]) {
      testWidgets('all message states fit at $w and 200% text', (tester) async {
        size(tester, w);
        backend.add(peer, direction: ChatDirection.incoming, body: '收到请回复');
        for (final s in SendState.values) {
          backend.add(
            peer,
            direction: ChatDirection.outgoing,
            body: '状态 ${s.name}',
            state: s,
            error: s == SendState.failed ? '连接被重置' : null,
          );
        }
        await tester.pumpWidget(thread(scale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('states are words plus icons, sent means unknown', (
      tester,
    ) async {
      size(tester, 390);
      for (final s in SendState.values) {
        backend.add(
          peer,
          direction: ChatDirection.outgoing,
          body: 'm-${s.name}',
          state: s,
          error: s == SendState.failed ? '超时' : null,
        );
      }
      await tester.pumpWidget(thread());
      expect(find.text('等待发送'), findsOneWidget);
      expect(find.text('已发出，对方是否收到未知'), findsOneWidget);
      expect(find.text('对方已收到'), findsOneWidget);
      expect(find.text('发送失败：超时'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });

    testWidgets('opening marks inbound read; unread marker disappears', (
      tester,
    ) async {
      size(tester, 390);
      backend.add(peer, direction: ChatDirection.incoming, body: '新消息');
      expect(backend.thread(peer)!.unread, 1);
      await tester.pumpWidget(thread());
      await tester.pumpAndSettle();
      expect(backend.thread(peer)!.unread, 0);
      expect(find.text('未读'), findsNothing);
    });

    testWidgets('a message arriving while open is shown and marked read', (
      tester,
    ) async {
      size(tester, 390);
      await tester.pumpWidget(thread());
      backend.add(peer, direction: ChatDirection.incoming, body: '实时来的');
      await tester.pumpAndSettle();
      expect(find.text('实时来的'), findsOneWidget);
      expect(backend.thread(peer)!.unread, 0);
    });

    testWidgets('send clears the input and appends an unconfirmed message', (
      tester,
    ) async {
      size(tester, 390);
      await tester.pumpWidget(thread());
      await tester.enterText(find.byType(TextField), '  你好  ');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.textContaining('目的地：192.168.1.8:47825'), findsOneWidget);
      expect(find.textContaining('核对指纹：$peer'), findsOneWidget);
      expect(
        backend.sentBodies,
        isEmpty,
        reason: 'nothing sent before confirm',
      );
      await tester.tap(find.text('发送这一次'));
      await tester.pumpAndSettle();
      expect(backend.sentBodies, ['你好']);
      expect(find.text('已发出，对方是否收到未知'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('send button is disabled for empty or over-long text', (
      tester,
    ) async {
      size(tester, 390);
      await tester.pumpWidget(thread());
      bool enabled() =>
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
              .onPressed !=
          null;
      expect(enabled(), isFalse);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(enabled(), isFalse);
      await tester.enterText(
        find.byType(TextField),
        'x' * (ChatBackend.maxBodyLength + 1),
      );
      await tester.pump();
      expect(enabled(), isFalse);
      expect(find.textContaining('超过'), findsOneWidget);
    });

    testWidgets('offline blocks sending but keeps history readable', (
      tester,
    ) async {
      size(tester, 390);
      backend.add(peer, direction: ChatDirection.incoming, body: '旧消息');
      backend.setPeer(peer, online: false);
      await tester.pumpWidget(thread());
      expect(find.text('旧消息'), findsOneWidget);
      expect(find.textContaining('没有中继，也不会排队'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('revoked pairing is explained and cannot send', (tester) async {
      size(tester, 390);
      backend.setPeer(peer, paired: false);
      await tester.pumpWidget(thread());
      expect(find.textContaining('已撤销配对'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('a send error from the backend is shown, input kept', (
      tester,
    ) async {
      size(tester, 390);
      backend.sendError = StateError('连接失败');
      await tester.pumpWidget(thread());
      await tester.enterText(find.byType(TextField), '内容');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送这一次'));
      await tester.pumpAndSettle();
      expect(find.textContaining('连接失败'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '内容',
      );
    });

    testWidgets('cancelling the send confirmation sends nothing', (
      tester,
    ) async {
      size(tester, 390);
      await tester.pumpWidget(thread());
      await tester.enterText(find.byType(TextField), '不发');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(backend.sentBodies, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '不发',
      );
    });

    testWidgets('a fresh unconfirmed message offers no retry yet', (
      tester,
    ) async {
      size(tester, 390);
      backend.add(
        peer,
        direction: ChatDirection.outgoing,
        body: 'x',
        state: SendState.sent,
      );
      await tester.pumpWidget(thread());
      expect(find.text('重发'), findsNothing);
      expect(find.textContaining('分钟后可重发'), findsOneWidget);
    });

    testWidgets('retry of an old unconfirmed message asks first', (
      tester,
    ) async {
      size(tester, 390);
      backend.add(
        peer,
        direction: ChatDirection.outgoing,
        body: 'x',
        state: SendState.sent,
        sentAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      await tester.pumpWidget(thread());
      await tapText(tester, '重发');
      expect(find.textContaining('对方可能已经收到'), findsOneWidget);
      await tapText(tester, '取消');
      expect(backend.retried, isEmpty);
      await tapText(tester, '重发');
      await tester.tap(find.widgetWithText(FilledButton, '重发'));
      await tester.pumpAndSettle();
      expect(backend.retried, hasLength(1));
    });

    testWidgets('retry of a failed message needs no extra warning', (
      tester,
    ) async {
      size(tester, 390);
      backend.add(
        peer,
        direction: ChatDirection.outgoing,
        body: 'x',
        state: SendState.failed,
        error: 'e',
      );
      await tester.pumpWidget(thread());
      await tapText(tester, '重发');
      expect(backend.retried, hasLength(1));
    });

    testWidgets('accept/reject are separate from read and say nothing runs', (
      tester,
    ) async {
      size(tester, 390);
      backend.add(peer, direction: ChatDirection.incoming, body: '合同号 123');
      await tester.pumpWidget(thread());
      await tester.pumpAndSettle();
      expect(find.text('未读'), findsNothing, reason: 'read, yet not accepted');
      await tapText(tester, '标记为已接纳');
      expect(find.textContaining('不会导入或执行'), findsOneWidget);
      expect(backend.messages(peer).single.acceptance, Acceptance.accepted);
      expect(backend.acceptedKeys, [
        '$peer/m1',
      ], reason: 'addressed by peer and message id');
      expect(find.text('标记为已接纳'), findsNothing);
    });

    testWidgets('delete message is local-only and asks first', (tester) async {
      size(tester, 390);
      backend.add(peer, direction: ChatDirection.incoming, body: '删我');
      await tester.pumpWidget(thread());
      await tapText(tester, '删除（仅本机）');
      expect(find.textContaining('对方设备上的不受影响'), findsOneWidget);
      await tapText(tester, '取消');
      expect(backend.messages(peer), hasLength(1));
      await tapText(tester, '删除（仅本机）');
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(backend.messages(peer), isEmpty);
    });

    testWidgets('delete thread confirms, removes locally, leaves the page', (
      tester,
    ) async {
      size(tester, 390);
      backend.add(peer, direction: ChatDirection.incoming, body: 'a');
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ChatThreadPage(backend: backend, peerFingerprint: peer),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除对话（仅本机）'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(backend.thread(peer), isNull);
      expect(find.text('open'), findsOneWidget);
    });
  });
}

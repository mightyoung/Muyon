import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/services/models/tool_names.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  test('actual inquiry store model→granted quantity write→verified cited answer without extra cards', () async {
    final loop = await LoopFixture.open();
    final root = Directory.systemTemp.createTempSync('auth-usable-inquiry-');
    final host = await MuyonHost.open(root.path);
    addTearDown(() async {
      await host.close();
      root.deleteSync(recursive: true);
    });
    await host.activateInquiry();
    final store = host.inquiry!.runtime.state.store;
    final project = store.save('project', {
      'code': 'AUTH',
      'name': 'actual inquiry',
      'status': 'active',
      'type': 'market',
      'level': 'A',
      'customer': null,
      'contract_no': null,
      'contract_amount': null,
      'department': null,
      'leader': null,
      'start_date': null,
      'end_date': null,
      'currency': 'CNY',
      'tax_mode': 'included',
      'markup_rate': '0',
      'notes': null,
    });
    final item = store.save('project_item', {
      'project_id': project,
      'category': 'material',
      'product_id': null,
      'name': 'actual item',
      'qty': '10',
      'unit': '米',
      'quotation_id': null,
      'unit_cost': '0',
      'unit_price': null,
      'notes': null,
    });
    final resolved = await resolveAssistantScope(
      host,
      const AssistantScope.global(),
    );
    final scope = AssistantScope.selectedObjects([
      resolved.objects.singleWhere((r) => r.objectId == item),
    ]);
    final c = await host.foundation.createConversation(scope: scope);
    final grant = await withConfirmedHostUiGrant(
      (token) => host.assistantGrants.create(
        token: token,
        now: DateTime.now().toUtc(),
        draft: GrantDraft(
          category: 'write',
          toolId: 'inquiry.set_item_qty',
          scopeDigest: toolGrantScopeDigest(scope, {'inquiry'}),
          destination: null,
          duration: GrantDuration.conversation,
          conversationId: c.id,
          maxUses: 1,
        ),
      ),
    );
    loop.replies.addAll([
      LoopReply.sse(
        sseCalls([
          (
            'qty',
            encodeToolName('inquiry.set_item_qty'),
            jsonEncode({'item_id': item, 'from_qty': '10', 'to_qty': '12'}),
          ),
        ]),
      ),
      LoopReply.sse(sseText('数量已由真实回执核实为 12 [r1]')),
    ]);
    final task = await host.personalAgent.start(
      conversationId: c.id,
      prompt: '将所选询价项目项数量从10改为12，然后核实结果',
      profile: loop.profile(),
    );
    expect(task.state, PersonalTaskState.succeeded, reason: task.error);
    expect(store.get('project_item', item)!.data['qty'], '12');
    expect(host.assistantGrants.list().single.uses, 1);
    final receipts = host.foundation.database.raw.select(
      'SELECT * FROM tool_invocation_receipts',
    );
    expect(receipts, hasLength(1));
    expect(receipts.single['grant_id'], grant.id);
    expect(
      (jsonDecode(receipts.single['result_json'] as String) as Map)['status'],
      'succeeded',
    );
    expect(loop.bodies, hasLength(2));
    expect(host.outbound.recent().map((r) => r['authorization_source']), [
      'mode_auto',
      'mode_auto',
    ]);
    expect(
      host.outbound.recent().map((r) => r['grant_id']),
      everyElement(isNull),
    );
    expect(task.summary, contains('[r1]'));
    expect(
      host.foundation.taskEvents(task.id).where((e) => e.type == 'wait'),
      isEmpty,
    );
  });
  test(
    'actual research import→scoped read→verified citation without model cards',
    () async {
      final loop = await LoopFixture.open();
      final root = Directory.systemTemp.createTempSync('auth-usable-research-');
      final source = Directory.systemTemp.createTempSync('auth-usable-paper-');
      File('${source.path}/paper.md')
          .writeAsStringSync('actual imported research document');
      final host = await MuyonHost.open(root.path);
      addTearDown(() async {
        await host.close();
        root.deleteSync(recursive: true);
        source.deleteSync(recursive: true);
      });
      await host.activateResearch();
      final w = await host.workspaces.create('actual research');
      final binding = WorkspaceBinding(
        workspaceId: w.id,
        moduleId: 'research',
        nativeProjectId: 'R',
      );
      final prepared = await host.research!.prepareImport(
        SelectedInput(path: source.path, displayName: 'R'),
        ImportTarget.create(binding),
      );
      final imports = ImportCoordinator(host.workspaces);
      await imports.commit(
        host.research!,
        prepared,
        await imports.record(prepared),
      );
      final document = host.research!.store.documents('R').single;
      final scope = AssistantScope.selectedObjects([
        ObjectRef(
          moduleId: 'research',
          nativeProjectId: 'R',
          objectType: 'document',
          objectId: document.id,
        ),
      ], workspaceId: w.id);
      final c = await host.foundation.createConversation(scope: scope);
      loop.replies.addAll([
        LoopReply.sse(
          sseCalls([
            (
              'research',
              encodeToolName('research.objects'),
              '{"query":"paper.md"}',
            ),
          ]),
        ),
        LoopReply.sse(sseText('已检索到实际导入的 paper.md [r1]')),
      ]);
      final task = await host.personalAgent.start(
        conversationId: c.id,
        prompt: '检索科研对象 paper.md 并给出带真实引用的结果',
        profile: loop.profile(),
      );
      expect(task.state, PersonalTaskState.succeeded, reason: task.error);
      final receipts = host.foundation.database.raw.select(
        'SELECT * FROM tool_invocation_receipts',
      );
      expect(receipts, hasLength(1));
      expect(receipts.single['tool_id'], 'research.objects');
      expect(
        (jsonDecode(receipts.single['result_json'] as String) as Map)['status'],
        'succeeded',
      );
      expect(loop.bodies, hasLength(2));
      expect(
        (loop.bodies.last['messages'] as List)
            .where((m) => m['role'] == 'tool')
            .single['content'],
        contains(document.id),
      );
      expect(task.summary, contains('[r1]'));
      expect(host.outbound.recent().map((r) => r['authorization_source']), [
        'mode_auto',
        'mode_auto',
      ]);
      expect(
        host.foundation.taskEvents(task.id).where((e) => e.type == 'wait'),
        isEmpty,
      );
      expect(host.assistantGrants.list(), isEmpty);
    },
  );
}

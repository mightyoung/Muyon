import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  for (final mode in [
    'grant',
    'manual',
    'revoked',
    'unknown-history',
    'tainted-source',
    'wrong-scope',
    'invalid-after-sign',
    'approval-insert-fails',
    'exhausted',
    'forged-params',
    'uncovered-files',
  ]) {
    final granted = mode != 'manual';
    final signed = ['grant', 'invalid-after-sign', 'exhausted'].contains(mode);
    test('actual host local quantity write / $mode', () async {
      final root = Directory.systemTemp.createTempSync('auth-auto-host-');
      final host = await MuyonHost.open(root.path);
      addTearDown(() async {
        await host.close();
        root.deleteSync(recursive: true);
      });
      await host.activateInquiry();
      final store = host.inquiry!.runtime.state.store;
      final projectId = store.save('project', {
        'code': 'AUTH',
        'name': 'actual project',
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
      final itemId = store.save('project_item', {
        'project_id': projectId,
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
        for (final ref in resolved.objects)
          if (ref.objectId == itemId) ref,
      ]);
      expect(scope.objects, hasLength(1));
      final c = await host.foundation.createConversation(scope: scope);
      final grants = GrantStore(host.foundation.database);
      String? grantId;
      if (granted) {
        final grant = await withConfirmedHostUiGrant(
          (token) => grants.create(
            token: token,
            draft: GrantDraft(
              category: 'write',
              toolId: 'inquiry.set_item_qty',
              scopeDigest: toolGrantScopeDigest(
                mode == 'wrong-scope' ? const AssistantScope.global() : scope,
                {'inquiry'},
              ),
              destination: null,
              duration: mode == 'exhausted'
                  ? GrantDuration.always
                  : GrantDuration.conversation,
              conversationId: c.id,
              maxUses: 1,
            ),
            now: DateTime.now(),
          ),
        );
        grantId = grant.id;
      }
      if (mode == 'revoked') {
        await host.assistantGrants.revoke(grantId!, now: DateTime.now());
      }
      if (mode == 'unknown-history') {
        await host.foundation.appendMessage(
          c.id,
          'assistant',
          'unproven old context',
        );
      }
      if (mode == 'tainted-source') {
        await host.foundation.authorizationFacts.markSourceExternal(
          HostSourceFact.project('inquiry', projectId),
        );
      }
      if (mode == 'approval-insert-fails') {
        await host.foundation.database.write(
          (db) => db.execute(
            "CREATE TEMP TRIGGER reject_auto BEFORE INSERT ON tool_approvals BEGIN SELECT RAISE(ABORT,'deny approval'); END",
          ),
        );
      }
      if (mode == 'uncovered-files') {
        File('${host.inquiry!.runtime.state.dataDir.path}/over-cap.bin')
            .writeAsBytesSync(List.filled(8 * 1024 * 1024 + 1, 0));
      }
      final task = await host.personalAgent.startTool(
        conversationId: c.id,
        toolId: 'inquiry.set_item_qty',
        parameters: {
          if (mode == 'forged-params') ...{'clean': true, 'grantId': grantId},
          'item_id': itemId,
          'from_qty': '10',
          'to_qty': mode == 'invalid-after-sign' ? 'invalid quantity' : '12',
        },
      );
      expect(
        task.state,
        [
              'invalid-after-sign',
              'approval-insert-fails',
              'forged-params',
            ].contains(mode)
            ? PersonalTaskState.failed
            : signed
            ? PersonalTaskState.succeeded
            : PersonalTaskState.waitingConfirmation,
      );
      expect(
        store.get('project_item', itemId)!.data['qty'],
        signed && mode != 'invalid-after-sign' ? '12' : '10',
      );
      final db = host.foundation.database.raw;
      if (signed) {
        final approval = db.select('SELECT * FROM tool_approvals').single;
        expect(approval['authorization_source'], 'grant');
        expect(approval['grant_id'], grantId);
        expect(approval['review_decision_id'], isNotNull);
        expect(
          db.select('SELECT uses FROM assistant_grants WHERE grant_id=?', [
            grantId,
          ]).single['uses'],
          1,
        );
        final review = db
            .select('SELECT * FROM assistant_review_decisions')
            .single;
        expect(review['reviewed'], 0);
        expect(review['task_id'], task.id);
        expect(review['destination_identity_digest'], isNull);
        expect(db.select('SELECT * FROM outbound_requests'), isEmpty);
        if (mode == 'exhausted') {
          final current = await resolveAssistantScope(
            host,
            const AssistantScope.global(),
          );
          final secondScope = AssistantScope.selectedObjects([
            for (final ref in current.objects)
              if (ref.objectId == itemId) ref,
          ]);
          final secondConversation = await host.foundation.createConversation(
            scope: secondScope,
          );
          final second = await host.personalAgent.startTool(
            conversationId: secondConversation.id,
            toolId: 'inquiry.set_item_qty',
            parameters: {'item_id': itemId, 'from_qty': '12', 'to_qty': '13'},
          );
          expect(second.state, PersonalTaskState.waitingConfirmation);
          expect(store.get('project_item', itemId)!.data['qty'], '12');
          expect(db.select('SELECT * FROM tool_approvals'), hasLength(1));
          expect(
            db.select('SELECT uses FROM assistant_grants WHERE grant_id=?', [
              grantId,
            ]).single['uses'],
            1,
          );
        }
      } else {
        expect(db.select('SELECT * FROM tool_approvals'), isEmpty);
        if (granted) {
          expect(
            db.select('SELECT uses FROM assistant_grants WHERE grant_id=?', [
              grantId,
            ]).single['uses'],
            0,
          );
        }
        if (mode == 'approval-insert-fails') {
          expect(db.select('SELECT * FROM tool_invocation_receipts'), isEmpty);
          expect(
            db.select(
              "SELECT * FROM assistant_grant_audit WHERE action='used'",
            ),
            isEmpty,
          );
        }
        if (mode == 'manual') {
          await host.personalAgent.confirm(
            task.id,
            requestDigest: task.payload['requestDigest'] as String,
          );
          expect(
            host.foundation.task(task.id)!.state,
            PersonalTaskState.succeeded,
          );
          expect(store.get('project_item', itemId)!.data['qty'], '12');
          final approval = db.select('SELECT * FROM tool_approvals').single;
          expect(approval['authorization_source'], 'manual');
          expect(approval['grant_id'], isNull);
          expect(approval['review_decision_id'], isNotNull);
        }
      }
    });
  }
}

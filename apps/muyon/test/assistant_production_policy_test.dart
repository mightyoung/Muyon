import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  for (final mode in [
    'readOnly',
    'write-off',
    'malformed',
    'model-off',
    'read-off',
    'read-allowed',
    'outbound-off',
    'manual-then-write-off',
  ]) {
    test('actual host category policy denies local quantity / $mode', () async {
      final root = Directory.systemTemp.createTempSync('auth-policy-');
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
      final c = await host.foundation.createConversation(
        scope: mode.startsWith('read-') ? const AssistantScope.global() : scope,
      );

      final grant = await withConfirmedHostUiGrant(
        (token) => host.assistantGrants.create(
          token: token,
          draft: GrantDraft(
            category: 'write',
            toolId: 'inquiry.set_item_qty',
            scopeDigest: toolGrantScopeDigest(scope, {'inquiry'}),
            destination: null,
            duration: GrantDuration.conversation,
            conversationId: c.id,
            maxUses: 1,
          ),
          now: DateTime.now(),
        ),
      );
      final policy = mode == 'malformed'
          ? '{invalid'
          : jsonEncode({
              'version': 1,
              'revision': 1,
              'mode': mode == 'readOnly' ? 'readOnly' : 'standard',
              'read': mode != 'read-off',
              'model': mode != 'model-off',
              'write': mode != 'write-off',
              'outbound': mode != 'outbound-off',
            });
      // Actual private host settings fixture, never model parameters.
      await host.foundation.database.write(
        (db) => db.execute(
          'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          ['auth1b:policy', policy],
        ),
      );
      var outboundEffects = 0;
      if (mode == 'outbound-off') {
        host.tools.register(
          providerId: 'host.policy.fixture',
          descriptor: ToolDescriptor(
            toolId: 'host.disabled_outbound',
            moduleId: 'inquiry',
            effect: ToolEffect.network,
            parameterSchema: {
              'type': 'object',
              'properties': <String, Object?>{},
              'additionalProperties': false,
            },
          ),
          supportedScopes: {AssistantScopeKind.selectedObjects},
          dataModuleIds: {'inquiry'},
          handler: (call) async {
            call.checkBeforeEffect();
            outboundEffects++;
            return ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: 'fixture effect',
            );
          },
        );
      }
      if (mode == 'manual-then-write-off') {
        await host.foundation.appendMessage(
          c.id,
          'assistant',
          'actual old unproven input requires manual',
        );
      }
      final loop = await LoopFixture.open();
      var task = mode == 'model-off'
          ? await host.personalAgent.start(
              conversationId: c.id,
              prompt: 'host model category off',
              profile: loop.profile(),
            )
          : await host.personalAgent.startTool(
              conversationId: c.id,
              toolId: mode.startsWith('read-')
                  ? 'inquiry.get'
                  : mode == 'outbound-off'
                  ? 'host.disabled_outbound'
                  : 'inquiry.set_item_qty',
              destination: mode == 'outbound-off'
                  ? 'https://fixture.invalid/send'
                  : null,
              parameters: mode.startsWith('read-')
                  ? {'type': 'project_item', 'id': itemId}
                  : mode == 'outbound-off'
                  ? <String, Object?>{}
                  : {'item_id': itemId, 'from_qty': '10', 'to_qty': '12'},
            );
      if (mode == 'manual-then-write-off') {
        expect(task.state, PersonalTaskState.waitingConfirmation);
        await withConfirmedHostUiGrant(
          (token) => host.authorizationPolicy.update(
            token: token,
            mode: AssistantAuthorizationMode.standard,
            enabled: Set.of(AssistantAuthorizationCategory.values)
              ..remove(AssistantAuthorizationCategory.write),
          ),
        );
        await host.personalAgent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        );
        task = host.foundation.task(task.id)!;
      }
      expect(outboundEffects, 0);
      expect(loop.bodies, isEmpty);
      expect(host.outbound.recent(), isEmpty);
      expect(
        task.state,
        mode == 'read-allowed'
            ? PersonalTaskState.succeeded
            : PersonalTaskState.failed,
        reason:
            'closed category must not propose or execute, even with real grant',
      );
      expect(store.get('project_item', itemId)!.data['qty'], '10');
      expect(
        host.foundation.database.raw.select(
          'SELECT uses FROM assistant_grants WHERE grant_id=?',
          [grant.id],
        ).single['uses'],
        0,
      );
      expect(
        host.foundation.database.raw.select('SELECT * FROM tool_approvals'),
        isEmpty,
      );
      expect(
        host.foundation.database.raw.select(
          'SELECT * FROM tool_invocation_receipts',
        ),
        mode == 'read-allowed' ? hasLength(1) : isEmpty,
      );
    });
  }
}

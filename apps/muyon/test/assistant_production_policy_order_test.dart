import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/services/models/tool_names.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';
import 'support/confirm_model_reviewer.dart';

class _PolicyBoundary implements OutboundContentReviewer {
  _PolicyBoundary(this.mode);
  final String mode;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    if (mode.endsWith('-review') && request.toolId == 'inquiry.auto_first') {
      expect(request.endpoint, isNull);
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return const ReviewDecision.allow();
  }
}

void main() {
  for (final mode in [
    'revision-review',
    'disable-review',
    'revision-effect',
    'disable-effect',
  ]) {
    test('actual host policy change at automatic boundary / $mode', () async {
      final loop = await LoopFixture.open();
      final root = Directory.systemTemp.createTempSync('auth-auto-order-');
      final reviewer = _PolicyBoundary(mode);
      final host = await MuyonHost.open(
        root.path,
        localToolReviewer: reviewer,
        localModelReviewer: const ConfirmModelReviewer(),
      );
      addTearDown(() async {
        if (!reviewer.release.isCompleted) reviewer.release.complete();
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
      final actual = await resolveAssistantScope(
        host,
        const AssistantScope.global(),
      );
      final scope = AssistantScope.selectedObjects([
        for (final r in actual.objects)
          if (r.objectId == itemId) r,
      ]);
      final effects = <String>[];
      final effectEntered = Completer<void>();
      final effectRelease = Completer<void>();
      addTearDown(() {
        if (!effectRelease.isCompleted) effectRelease.complete();
      });
      final external = mode == 'external-union';
      final middleId = external
          ? 'public.fixture_external'
          : 'prototype.fixture_manual';
      for (final id in ['inquiry.auto_first', middleId, 'inquiry.auto_last']) {
        final local = id.startsWith('inquiry.');
        host.tools.register(
          providerId: 'host.order.fixture',
          descriptor: ToolDescriptor(
            toolId: id,
            moduleId: local
                ? 'inquiry'
                : external
                ? 'public'
                : 'prototype',
            effect: external && id == middleId
                ? ToolEffect.network
                : ToolEffect.write,
            parameterSchema: {
              'type': 'object',
              'properties': external && id == middleId
                  ? {
                      'destination': {'type': 'string'},
                    }
                  : <String, Object?>{},
              'additionalProperties': false,
            },
          ),
          dataModuleIds: {'inquiry'},
          effectIntent: local
              ? (request, resolved) => HostEffectIntent.localWrite(
                  toolId: id,
                  invocationId: request.invocationId,
                  content: [123, 125],
                  sourceObjects: resolved.objects,
                )
              : null,
          handler: (call) async {
            if (mode.endsWith('-effect') && id == 'inquiry.auto_first') {
              effectEntered.complete();
              await effectRelease.future;
            }
            if (local) {
              expect(
                () => host.tools.authorizationLink(call.request),
                throwsA(isA<ToolPlatformException>()),
              );
            }
            call.checkBeforeEffect();
            // Order probes are fixture counters; real domain writes are
            // independently covered in assistant_production_auto_write_test.
            effects.add(id);
            return ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: 'fixture $id completed',
            );
          },
        );
      }
      final c = await host.foundation.createConversation(scope: scope);
      final grantIds = <String>[];
      for (final id in ['inquiry.auto_first', 'inquiry.auto_last']) {
        final grant = await withConfirmedHostUiGrant(
          (token) => host.assistantGrants.create(
            token: token,
            draft: GrantDraft(
              category: 'write',
              toolId: id,
              scopeDigest: toolGrantScopeDigest(scope, {'inquiry'}),
              destination: null,
              duration: GrantDuration.conversation,
              conversationId: c.id,
              maxUses: 1,
            ),
            now: DateTime.now(),
          ),
        );
        grantIds.add(grant.id);
      }
      final order = mode == 'manual-first'
          ? [middleId, 'inquiry.auto_first', 'inquiry.auto_last']
          : ['inquiry.auto_first', middleId, 'inquiry.auto_last'];
      loop.replies
        ..add(
          LoopReply.sse(
            sseCalls([
              for (var i = 0; i < order.length; i++)
                (
                  'c$i',
                  encodeToolName(order[i]),
                  external && order[i] == middleId
                      ? '{"destination":"https://fixture.invalid/send"}'
                      : '{}',
                ),
            ]),
          ),
        )
        ..add(LoopReply.sse(sseText('fixture done')));
      var task = await host.personalAgent.start(
        conversationId: c.id,
        prompt: 'run selected fixture calls in order',
        profile: loop.profile(),
      );
      expect(task.state, PersonalTaskState.waitingConfirmation);
      final pending = host.personalAgent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      final afterSign = mode.endsWith('-effect');
      if (afterSign) {
        await effectEntered.future.timeout(const Duration(seconds: 10));
        expect(
          host.foundation.database.raw.select(
            'SELECT uses FROM assistant_grants WHERE grant_id=?',
            [grantIds.first],
          ).single['uses'],
          1,
        );
      } else {
        await reviewer.entered.future.timeout(const Duration(seconds: 10));
      }
      await withConfirmedHostUiGrant(
        (token) => host.authorizationPolicy.update(
          token: token,
          mode: mode.startsWith('disable')
              ? AssistantAuthorizationMode.readOnly
              : AssistantAuthorizationMode.standard,
          enabled: Set.of(AssistantAuthorizationCategory.values),
        ),
      );
      if (afterSign) {
        effectRelease.complete();
      } else {
        reviewer.release.complete();
      }
      await pending;
      task = host.foundation.task(task.id)!;
      final db = host.foundation.database.raw;
      List<int> uses() => [
        for (final id in grantIds)
          db.select('SELECT uses FROM assistant_grants WHERE grant_id=?', [
                id,
              ]).single['uses']
              as int,
      ];
      expect(effects, isEmpty);
      expect(uses(), afterSign ? [1, 0] : [0, 0]);
      expect(
        db.select('SELECT * FROM tool_approvals'),
        afterSign ? hasLength(1) : isEmpty,
      );
      expect(
        db.select('SELECT * FROM tool_invocation_receipts'),
        afterSign ? hasLength(1) : isEmpty,
      );
      expect(task.state, PersonalTaskState.failed);
    });
  }
}

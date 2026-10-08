import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/services/models/tool_names.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

class _ReviewBoundary implements OutboundContentReviewer {
  _ReviewBoundary(this.mode);
  final String mode;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    if (mode == 'late-block' && request.toolId == 'inquiry.auto_last') {
      return const ReviewDecision.block('fixture local block');
    }
    if ([
          'cancel-review',
          'revoke-review',
          'change-source-review',
        ].contains(mode) &&
        request.toolId == 'inquiry.auto_first') {
      expect(request.endpoint, isNull);
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return const ReviewDecision.allow();
  }
}

void main() {
  for (final mode in [
    'prefix',
    'manual-first',
    'external-union',
    'late-block',
    'cancel-review',
    'revoke-review',
    'change-source-review',
    'cancel-effect',
    'revoke-effect',
  ]) {
    test('actual host ordered automatic / $mode', () async {
      final loop = await LoopFixture.open();
      final root = Directory.systemTemp.createTempSync('auth-auto-order-');
      final reviewer = _ReviewBoundary(mode);
      final host = await MuyonHost.open(root.path, localToolReviewer: reviewer);
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
            if (['cancel-effect', 'revoke-effect'].contains(mode) &&
                id == 'inquiry.auto_first') {
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
      if ([
        'cancel-review',
        'revoke-review',
        'change-source-review',
      ].contains(mode)) {
        await reviewer.entered.future.timeout(const Duration(seconds: 10));
        if (mode == 'cancel-review') await host.personalAgent.cancel(task.id);
        if (mode == 'revoke-review') {
          await host.assistantGrants.revoke(
            grantIds.first,
            now: DateTime.now(),
          );
        }
        if (mode == 'change-source-review') {
          store.save('project_item', {
            ...store.get('project_item', itemId)!.data,
            'notes': 'actual changed source',
          }, id: itemId);
        }
        reviewer.release.complete();
      }
      if (['cancel-effect', 'revoke-effect'].contains(mode)) {
        await effectEntered.future.timeout(const Duration(seconds: 10));
        expect(
          host.foundation.database.raw.select(
            'SELECT uses FROM assistant_grants WHERE grant_id=?',
            [grantIds.first],
          ).single['uses'],
          1,
        );
        if (mode == 'cancel-effect') await host.personalAgent.cancel(task.id);
        if (mode == 'revoke-effect') {
          await host.assistantGrants.revoke(
            grantIds.first,
            now: DateTime.now(),
          );
        }
        effectRelease.complete();
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
      if (mode == 'prefix') {
        expect(effects, ['inquiry.auto_first']);
        expect(uses(), [1, 0]);
        expect(task.state, PersonalTaskState.waitingConfirmation);
        expect(task.payload['toolCalls'], hasLength(2));
        final first = db.select('SELECT * FROM tool_approvals').single;
        expect(first['authorization_source'], 'grant');
        expect(first['grant_id'], grantIds.first);
        await host.personalAgent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        );
        expect(effects, order);
        expect(uses(), [1, 0]);
        final approvals = db.select(
          'SELECT * FROM tool_approvals ORDER BY rowid',
        );
        expect(approvals.map((r) => r['authorization_source']), [
          'grant',
          'manual',
          'manual',
        ]);
        expect(approvals.skip(1).every((r) => r['grant_id'] == null), isTrue);
      } else {
        expect(effects, isEmpty);
        final signedThenWithdrawn = [
          'cancel-effect',
          'revoke-effect',
        ].contains(mode);
        expect(uses(), signedThenWithdrawn ? [1, 0] : [0, 0]);
        expect(
          db.select('SELECT * FROM tool_approvals'),
          signedThenWithdrawn ? hasLength(1) : isEmpty,
        );
        expect(
          db.select('SELECT * FROM tool_invocation_receipts'),
          signedThenWithdrawn ? hasLength(1) : isEmpty,
        );
        final state = switch (mode) {
          'late-block' ||
          'change-source-review' ||
          'revoke-effect' => PersonalTaskState.failed,
          'cancel-review' || 'cancel-effect' => PersonalTaskState.cancelled,
          _ => PersonalTaskState.waitingConfirmation,
        };
        expect(task.state, state);
        if (mode == 'external-union') {
          expect(
            host.foundation.authorizationFacts.readTask(task.id).taintState,
            HostTaintState.tainted,
          );
        }
      }
    });
  }
}

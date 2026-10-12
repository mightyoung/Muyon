import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/local_export_target.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'package:muyon/platform/foundation_repository.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

import 'support/confirm_model_reviewer.dart';

/// LE-05 through the assistant's own dispatch entry: the model cannot write a
/// local export stage, and the grant-path errors never surface as a crash.
void main() {
  late Directory root;
  late MuyonHost host;
  late LocalExportTargetIssuer issuer;
  late int runs;
  const scopeDigest =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

  setUp(() async {
    root = Directory.systemTemp.createTempSync('le05-dispatch-');
    host = await MuyonHost.open(
      root.path,
      localModelReviewer: const ConfirmModelReviewer(),
    );
    issuer = LocalExportTargetIssuer();
    runs = 0;
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  void register(String id, {required bool hostStaged}) {
    host.tools.register(
      providerId: 'test',
      descriptor: ToolDescriptor(
        toolId: id,
        moduleId: 'test',
        effect: ToolEffect.export,
        parameterSchema: const {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
      effectIntent: (request, _) => HostEffectIntent.localExport(
        toolId: request.toolId,
        call: LocalExportGenerateCall(
          exportId: 'export-1',
          invocationId: request.invocationId,
        ),
        phase: LocalExportPhase.generate,
        scopeDigest: scopeDigest,
        preparationDigest: 'd' * 64,
        preparationVersion: 1,
        fileName: 'report-1.md',
        format: 'text/markdown',
        content: const [1, 2, 3],
        sourceObjects: const [],
        targetIssuer: issuer,
        overwrite: LocalExportOverwrite.createNew,
        policyVersion: 'p1',
      ),
      handler: (_) async {
        runs++;
        return ToolCallResult(status: ToolCallStatus.succeeded, summary: 'ok');
      },
    );
    if (hostStaged) {
      host.tools.bindLocalExportStage(id, (_) => LocalExportPhase.generate);
    }
  }

  Future<String> conversation() async =>
      (await host.foundation.createConversation()).id;

  group('stage is written by the host, not the model', () {
    for (final proposed in ['local-export:save', 'local-export:generate']) {
      test(
        'a model destination "$proposed" is refused with zero execution',
        () async {
          register('test.export', hostStaged: true);
          final task = await host.personalAgent.startTool(
            conversationId: await conversation(),
            toolId: 'test.export',
            destination: proposed,
          );
          expect(task.state, PersonalTaskState.failed);
          expect(runs, 0);
          expect(
            host.foundation.database.raw.select('SELECT * FROM tool_approvals'),
            isEmpty,
          );
        },
      );
    }

    test(
      'a local-export destination is refused for any tool, staged or not',
      () async {
        register('test.unstaged', hostStaged: false);
        final task = await host.personalAgent.startTool(
          conversationId: await conversation(),
          toolId: 'test.unstaged',
          destination: 'local-export:save',
        );
        expect(task.state, PersonalTaskState.failed);
        expect(runs, 0);
      },
    );

    test(
      'a destination or stage smuggled into the parameters is refused',
      () async {
        register('test.export', hostStaged: true);
        for (final parameters in [
          {'destination': 'local-export:save'},
          {'stage': 'save'},
        ]) {
          final task = await host.personalAgent.startTool(
            conversationId: await conversation(),
            toolId: 'test.export',
            parameters: parameters,
          );
          expect(task.state, PersonalTaskState.failed, reason: '$parameters');
        }
        expect(runs, 0);
      },
    );
  });

  test('grant-path errors never crash the task: it waits for a person and then runs once', () async {
    register('test.export', hostStaged: true);
    final c = await conversation();
    final grants = GrantStore(host.foundation.database);
    final request = ToolCallRequest(
      invocationId: 'probe',
      toolId: 'test.export',
      scope: const AssistantScope.global(),
      destination: localExportDestination(LocalExportPhase.generate),
    );
    final once = await withConfirmedHostUiGrant(
      (token) => grants.create(
        token: token,
        draft: GrantDraft(
          category: 'outbound',
          toolId: 'test.export',
          scopeDigest: toolGrantScopeDigest(request.scope, const {'test'}),
          destination: sha256
              .convert(utf8.encode(jsonEncode(request.destination)))
              .toString(),
          duration: GrantDuration.once,
          conversationId: c,
        ),
        now: DateTime.now(),
      ),
    );
    final task = await host.personalAgent.startTool(
      conversationId: c,
      toolId: 'test.export',
    );
    expect(
      task.state,
      PersonalTaskState.waitingConfirmation,
      reason: '${task.error}',
    );
    expect(runs, 0);
    await host.personalAgent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    final done = host.foundation.task(task.id)!;
    expect(done.state, PersonalTaskState.succeeded, reason: '${done.error}');
    expect(runs, 1);
    final approval = host.foundation.database.raw
        .select('SELECT authorization_source, grant_id FROM tool_approvals')
        .single;
    expect(approval['authorization_source'], 'manual');
    expect(approval['grant_id'], isNull);
    expect(
      host.foundation.database.raw.select(
        'SELECT uses FROM assistant_grants WHERE grant_id=?',
        [once.id],
      ).single['uses'],
      0,
    );
  });
}

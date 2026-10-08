import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  for (final kind in [
    'selected-missing-project',
    'workspace-source-missing-project',
    'workspace-malformed-bound-project',
    'workspace-unclassifiable-source',
    'workspace-outside-project',
  ]) {
    final damaged =
        kind.contains('malformed') || kind.contains('unclassifiable');
    for (final phase
        in damaged
            ? ['before', 'reopen-before']
            : ['before', 'after', 'queued', 'reopen-before']) {
      test('$kind / $phase cannot invent source exclusion', () async {
        final f = await LoopFixture.open();
        var repo = f.repo;
        var tools = f.tools;
        late AssistantScope scope;
        final source = HostSourceFact.project(
          'inquiry',
          kind == 'workspace-source-missing-project'
              ? null
              : kind == 'workspace-outside-project'
              ? 'outside'
              : 'p',
        );
        if (kind == 'selected-missing-project') {
          scope = AssistantScope.selectedObjects([
            const ObjectRef(
              moduleId: 'inquiry',
              objectType: 'project_item',
              objectId: 'i',
            ),
          ]);
        } else {
          final wr = WorkspaceRepository(repo.database);
          final w = await wr.create('actual bound workspace');
          await wr.bind(
            WorkspaceBinding(
              workspaceId: w.id,
              moduleId: 'inquiry',
              nativeProjectId: 'p',
            ),
          );
          scope = AssistantScope.workspace(w.id);
        }
        if (damaged) {
          await repo.database.write(
            (db) => db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
              kind.contains('unclassifiable')
                  ? 'auth1b:source:unclassified'
                  : 'auth1b:source:${source.identityDigest}',
              kind.contains('malformed')
                  ? '{broken'
                  : jsonEncode({
                      'version': 1,
                      'taintState': 'tainted',
                      'sourceDigests': [source.identityDigest],
                    }),
            ]),
          );
        } else if (phase == 'before' || phase == 'reopen-before') {
          await repo.authorizationFacts.markSourceExternal(source);
        }
        if (phase == 'reopen-before') {
          await f.storage.close();
          final storage = StorageManager(f.root.path);
          final db = await storage.open('muyon', WorkspaceRepository.schema);
          addTearDown(storage.close);
          repo = FoundationRepository(db);
          tools = ToolRegistry(
            database: db,
            resolveScope: (scope) async =>
                ResolvedAssistantScope(requested: scope, objects: []),
          );
        }
        final c = await repo.createConversation(scope: scope);
        final agent = PersonalAgent(
          repository: repo,
          tools: tools,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        );
        var agentClosed = false;
        addTearDown(() async {
          if (!agentClosed) await agent.close();
        });
        final task = await agent.start(
          conversationId: c.id,
          prompt: 'fresh actual user request',
        );
        if (phase == 'after' || phase == 'queued') {
          expect(
            repo.authorizationFacts.readTask(task.id).taintState,
            HostTaintState.clean,
          );
          if (phase == 'queued') {
            final entered = Completer<void>();
            final release = Completer<void>();
            final blocker = (repo.database as ManagedConnection).exclusiveAsync(
              (_) async {
                entered.complete();
                await release.future;
              },
            );
            await entered.future;
            final marker = repo.authorizationFacts.markSourceExternal(source);
            final pending = repo.authorizationFacts.readTask(task.id);
            release.complete();
            await blocker;
            await marker;
            expect(
              pending.taintState,
              kind == 'workspace-outside-project'
                  ? HostTaintState.clean
                  : HostTaintState.tainted,
            );
          } else {
            await repo.authorizationFacts.markSourceExternal(source);
          }
        }
        final facts = repo.authorizationFacts.readTask(task.id);
        final expected = kind == 'workspace-outside-project'
            ? HostTaintState.clean
            : damaged
            ? HostTaintState.unknown
            : HostTaintState.tainted;
        expect(facts.taintState, expected);
        if (expected == HostTaintState.tainted) {
          expect(facts.sourceDigests, contains(source.identityDigest));
          final stored = repo.database.raw.select(
            'SELECT value FROM settings WHERE key=?',
            ['auth1b:task:${task.id}'],
          );
          expect(
            jsonDecode(stored.single['value'] as String)['taintState'],
            'tainted',
          );
          // Real owner reopen clears session latches; task authority remains.
          await agent.close();
          agentClosed = true;
          await (repo.database as ManagedConnection).close();
          final storage = StorageManager(f.root.path);
          final db = await storage.open('muyon', WorkspaceRepository.schema);
          addTearDown(storage.close);
          final reopened = FoundationRepository(db).authorizationFacts
              .readTask(task.id);
          expect(reopened.taintState, HostTaintState.tainted);
          expect(reopened.sourceDigests, contains(source.identityDigest));
        }
      });
    }
  }
}

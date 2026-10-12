import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScopeKind;
import 'package:muyon_ui/dynamic_ui.dart';

import '../app/bootstrap.dart';
import '../assistant/inquiry_snapshots/inquiry_readonly_snapshot.dart';
import '../assistant/ui_planning.dart';
import 'foundation_repository.dart';
import 'ui_workspace_store.dart';

/// Trusted selected-record projection. The model receives masked display facts,
/// not raw domain rows, guessed computations or an enlarged selection.
class InquiryUiPlanningSource {
  const InquiryUiPlanningSource(this.host);
  final MuyonHost host;
  Future<UiPlanningHostState?> read(PersonalTask supplied) async {
    final task = host.foundation.task(supplied.id);
    final conversation = task == null
        ? null
        : host.foundation.conversation(task.conversationId);
    if (task == null ||
        conversation == null ||
        task.payload['uiPlanningInternal'] == true ||
        // Cancellation revokes execution only. Failed and interrupted stay
        // unreadable, as do scope, authority and object-pin failures below.
        {
          PersonalTaskState.failed,
          PersonalTaskState.interrupted,
        }.contains(task.state) ||
        jsonEncode(task.scope.toJson()) !=
            jsonEncode(conversation.scope.toJson()) ||
        task.scope.kind != AssistantScopeKind.selectedObjects ||
        // The first slice has one host-selected target. Do not filter a
        // larger selection and silently choose one of its members.
        task.scope.objects.length != 1) {
      return null;
    }
    final target = task.scope.objects.single;
    if (target.moduleId != 'inquiry' ||
        !const {
          'inquiry',
          'quotation',
          'project_item',
        }.contains(target.objectType)) {
      return null;
    }
    final owner = host.inquiry;
    final lifecycle = host.modules.scopeAuthorityRevision('inquiry');
    final authority = host.workspaces.scopeAuthorityRevision;
    final selected = await InquiryReadonlySnapshots.read(
      host: host,
      scope: task.scope,
      object: target,
    );
    bool stillCurrent() {
      final live = host.foundation.task(task.id);
      return live != null &&
          live.conversationId == task.conversationId &&
          live.payload['uiPlanningInternal'] != true &&
          !{
            PersonalTaskState.failed,
            PersonalTaskState.interrupted,
          }.contains(live.state) &&
          jsonEncode(live.scope.toJson()) == jsonEncode(task.scope.toJson()) &&
          jsonEncode(
                host.foundation
                    .conversation(task.conversationId)
                    ?.scope
                    .toJson(),
              ) ==
              jsonEncode(task.scope.toJson()) &&
          lifecycle != null &&
          authority != null &&
          identical(host.inquiry, owner) &&
          host.modules.scopeAuthorityRevision('inquiry') == lifecycle &&
          host.workspaces.scopeAuthorityRevision == authority;
    }

    if (!stillCurrent()) return null;
    final stored = await HostUiWorkspaceStore(
      host.foundation,
      taskId: task.id,
    ).load('task-${task.id}');
    if (!stillCurrent()) return null;
    final object = selected.record.object;
    final facts = <String, SnapshotFact>{
      'saved-source': SnapshotFact(
        object: object,
        field: '来源对象及修订',
        value: selected.sourceLabel,
        state: FactState.verified,
      ),
      for (final field in selected.record.fields)
        'saved-${field.name}': SnapshotFact(
          object: object,
          field: field.label,
          value: field.value,
          // The fixed-card projection supplies a typed masking flag but
          // discards original fact state/null/type-validation evidence. Its
          // formatted placeholders cannot prove verified business values.
          state: field.masked ? FactState.notDisclosed : FactState.unverified,
        ),
    };
    final snapshot = DataSnapshot(
      ref: SnapshotRef(
        'saved-${sha256.convert(utf8.encode(jsonEncode([object.toJson(), lifecycle, authority])))}',
        selected.record.snapshotRef.revision,
      ),
      facts: facts,
      initialUiState: stored?.displayValues ?? const {},
    );
    const allowed = {'detail', 'back'};
    return UiPlanningHostState(
      snapshot: snapshot,
      intent: InteractionIntent(
        id: 'saved-selection-${task.id}',
        purpose: 'Display current selected locally saved facts; not a model/tool receipt. Suggestions never replace facts.',
        snapshotRef: snapshot.ref,
        requiredBindings: facts.keys.map(BindingRef.fact).toSet(),
        mandatoryStates: const {},
        allowedActionRefs: allowed,
      ),
      currentView: UiCurrentView(
        surfaceId: 'task-${task.id}',
        revision: stored?.planRevision ?? 0,
        values: stored?.displayValues ?? const {},
      ),
      catalog: library2UiCatalog,
      allowedActionRefs: allowed,
    );
  }
}

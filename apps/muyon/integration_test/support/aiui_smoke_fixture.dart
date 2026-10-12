import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

import 'aiui_smoke_config.dart';
import 'north_star_seed.dart';
import 'north_star_settings.dart'
    show EnvSecretStore, bindEnvSecretStore, unbindEnvSecretStore;

final class SmokePreflight {
  SmokePreflight(this.capabilities, this.failures);
  final Map<String, bool?> capabilities;
  final List<SmokeFailureCode> failures;
  bool get passed => failures.isEmpty;
  Map<String, Object?> toEvidence() => {
    'passed': passed,
    'failure_code': failures.firstOrNull?.code,
    'failure_codes': failures.map((failure) => failure.code).toList(),
    'capabilities': capabilities,
  };
  void requireReady() {
    if (!passed) throw SmokeFailure(failures.first);
  }
}

/// Checks existing production source/catalog/preference separately from missing
/// CF observation, frame, restricted-I/O and persistence owners. No private
/// switch is changed and no successful presentation is fabricated.
SmokePreflight inspectSmokeProduction(
  MuyonHost host,
  UiPlanningHostState? state,
) {
  final caps = <String, bool?>{
    // Source/preference/mode presence is structural wiring, not observation
    // of the actual selected provider or a production stream request.
    'production_stream': null,
    'library_2': state?.catalog.version == 'library-2',
    'presentation_policy': host.personalAgent.presentationPreference != null,
    // These observations need a production owner and data interface, neither
    // supplied by this foundation. Unknown is not an advertisement of absence
    // or success; in particular SN fallback/diagnostics already exist.
    'request_observability': null,
    'frame_observability': null,
    'conversation_fact_card': null,
    'production_fallback': null,
    'failure_diagnostics': null,
    'fault_io_boundary': null,
    'manual_checkpoint': null,
  };
  final failures = <SmokeFailureCode>[
    if (caps['production_stream'] == false || !caps['library_2']!)
      SmokeFailureCode.productionStreamWiringMissing,
    if (!caps['presentation_policy']!)
      SmokeFailureCode.presentationPolicyMissing,
    if (caps['request_observability'] != true ||
        caps['frame_observability'] != true)
      SmokeFailureCode.requestObservabilityMissing,
    if (caps['conversation_fact_card'] != true)
      SmokeFailureCode.conversationFactCardMissing,
    if (caps['production_fallback'] == false)
      SmokeFailureCode.productionFallbackMissing,
    if (caps['failure_diagnostics'] == false)
      SmokeFailureCode.failureDiagnosticsMissing,
    if (caps['fault_io_boundary'] != true)
      SmokeFailureCode.faultIoBoundaryMissing,
    if (caps['manual_checkpoint'] != true)
      SmokeFailureCode.manualCheckpointUnavailable,
  ];
  return SmokePreflight(Map.unmodifiable(caps), List.unmodifiable(failures));
}

final class AiuiSmokeFixture {
  AiuiSmokeFixture._(this.host, this.data, this.scope, this.conversation);
  final MuyonHost host;
  final NorthStarFixtureData data;
  final AssistantScope scope;
  final AssistantConversation conversation;
  bool _mounted = false, _secretBound = false;

  /// Caller owns root lifetime. Formal runs retain this isolation for handoff;
  /// a separate recovery owner is still required and is reported by preflight.
  static Future<AiuiSmokeFixture> open(String root) async {
    final host = await MuyonHost.open(root);
    try {
      await host.activateInquiry();
      final inquiry = host.inquiry;
      if (inquiry == null) {
        throw SmokeFailure(SmokeFailureCode.productionStreamWiringMissing);
      }
      final data = seedInquiry(inquiry.runtime.state.store);
      final resolved = await host.scopeResolver.resolve(
        AssistantScope.selectedObjects([
          ObjectRef(
            moduleId: 'inquiry',
            objectType: 'inquiry',
            objectId: data.firstInquiry,
            nativeProjectId: data.projectId,
          ),
        ]),
      );
      if (resolved.objects.length != 1 ||
          resolved.objects.single.revisionRef == null ||
          resolved.objects.single.contentDigest == null) {
        throw SmokeFailure(SmokeFailureCode.requestObservabilityMissing);
      }
      final scope = AssistantScope.selectedObjects(resolved.objects);
      final conversation = await host.foundation.createConversation(
        title: 'AIUI 冒烟只读验收',
        scope: scope,
      );
      return AiuiSmokeFixture._(host, data, scope, conversation);
    } catch (_) {
      await host.close();
      rethrow;
    }
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MuyonApp(host: host));
    _mounted = true;
    await tester.pump();
    final shell = find.byType(PlatformShell);
    if (shell.evaluate().length != 1) {
      throw SmokeFailure(SmokeFailureCode.requestObservabilityMissing);
    }
    final navigator = Navigator.of(tester.element(shell));
    // Enter the real production assistant route inside the real app. The
    // selected scope came from the actual module scope resolver above.
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: SafeArea(
            child: AssistantPage(
              host: host,
              repo: host.foundation,
              agent: host.personalAgent,
              profiles: ProfileRepository(host.workspaces),
              scope: scope,
              conversationId: conversation.id,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<UiPlanningHostState?> sourceForCurrentTask() async {
    final tasks = host.foundation.tasks(conversationId: conversation.id);
    if (tasks.length != 1) {
      throw SmokeFailure(SmokeFailureCode.requestObservabilityMissing);
    }
    return host.personalAgent.uiPlanningSource?.call(tasks.single);
  }

  /// Restricted to isolated test storage. The secret remains on the transient
  /// MethodChannelSecretStore binding; caller binds it only after preflight.
  Future<void> configureProfile(AiuiSmokeConfiguration configuration) async {
    if (configuration.secret != null) {
      bindEnvSecretStore(
        EnvSecretStore(
          AiuiSmokeConfiguration.credentialReference,
          configuration.secret,
        ),
      );
      _secretBound = true;
    }
    await ProfileRepository(host.workspaces).save(configuration.profile);
  }

  Future<void> close(WidgetTester tester) async {
    if (_mounted) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 250));
    }
    var settled = false;
    Object? failure;
    host.close().then(
      (_) => settled = true,
      onError: (Object error) {
        failure = error;
        settled = true;
      },
    );
    final watchdog = Stopwatch()..start();
    while (!settled && watchdog.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    if (_secretBound) {
      unbindEnvSecretStore();
      _secretBound = false;
    }
    if (!settled || failure != null) {
      throw SmokeFailure(SmokeFailureCode.unexpectedFailure);
    }
  }
}

/// An incomplete checkpoint is stored without secrets or paths; it is not a
/// restart proof or a fabricated 'ready for manual verification' checkpoint.
Future<void> writeSmokeCheckpointStatus(
  String root, {
  required bool complete,
}) => File(p.join(root, 'aiui-smoke-checkpoint-status.json')).writeAsString(
  '{"schema":1,"complete":$complete,"stage":"blocked_before_measurement"}',
  flush: true,
);

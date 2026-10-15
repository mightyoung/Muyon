import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/core_agent_process.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

import 'offline_model.dart';

String requiredBinary() {
  final binary = Platform.environment['MUYON_TEST_CORE_AGENT_BIN'];
  if (binary == null || !p.isAbsolute(binary) || !File(binary).existsSync()) {
    throw StateError('MUYON_TEST_CORE_AGENT_BIN must name the compiled absolute Rust binary');
  }
  return binary;
}

Directory repositoryRoot() {
  var directory = Directory.current.absolute;
  while (!File(p.join(directory.path, 'experiments/redesign/core-agent-lab/HOST-CONTRACT.md')).existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) throw StateError('repository_root_missing');
    directory = parent;
  }
  return directory;
}

class HostFixture {
  HostFixture._(this.root, this.transport, this.secrets);
  final Directory root;
  final OfflineModel transport;
  final FakeSecretStore secrets;
  late MuyonHost host;
  late String supplierId;
  late String otherId;
  late ObjectRef selected;
  late AssistantConversation conversation;
  bool closed = false;
  Directory get evidence => Directory(p.join(root.path, 'process'));
  String get stateRoot => p.join(root.path, 'core-state');
  String get launcher => p.join(root.path, 'launch-core');

  static Future<HostFixture> open({
    bool enabled = true,
    OutboundContentReviewer? modelReviewer,
    OutboundContentReviewer? toolReviewer,
  }) async {
    final f = HostFixture._(
      Directory.systemTemp.createTempSync('core-agent-host-'),
      OfflineModel(),
      FakeSecretStore(),
    );
    f.secrets.install();
    final recorder = p.join(repositoryRoot().path,
      'experiments/redesign/core-agent-lab/host-checks/record_process.py');
    File(f.launcher).writeAsStringSync([
      '#!/usr/bin/python3',
      'import runpy, sys',
      'sys.argv = ${jsonEncode([recorder, '--binary', requiredBinary(), '--evidence', f.evidence.path])} + sys.argv[1:]',
      'runpy.run_path(${jsonEncode(recorder)}, run_name="__main__")',
      '',
    ].join('\n'));
    final permission = await Process.run('/bin/chmod', ['700', f.launcher]);
    if (permission.exitCode != 0) throw StateError('launcher_not_executable');
    try {
      f.host = await MuyonHost.open(
        p.join(f.root.path, 'business'),
        coreAgentProcess: CoreAgentProcessConfig(
          enabled: enabled,
          executablePath: f.launcher,
          stateRoot: f.stateRoot,
        ),
        modelClientFactory: f.transport.client,
        localModelReviewer: modelReviewer,
        localToolReviewer: toolReviewer,
      );
      await f.host.activateInquiry();
      String save(String name, String notes) => f.host.inquiry!.runtime.state.store.save('supplier', {
        'name': name, 'notes': notes, 'aliases': <String>[],
        'categories': <String>[], 'address': null, 'merged_into': null,
        'rating': null, 'rating_note': null,
      });
      f.supplierId = save(privateName, privateNotes);
      f.otherId = save('SECOND_SYNTHETIC_SUPPLIER', 'SECOND_PRIVATE_NOTE');
      final scope = await resolveAssistantScope(f.host, const AssistantScope.global());
      f.selected = scope.objects.singleWhere((ref) =>
        ref.moduleId == 'inquiry' && ref.objectType == 'supplier' && ref.objectId == f.supplierId);
      f.conversation = await f.host.foundation.createConversation(
        scope: AssistantScope.selectedObjects([f.selected]),
      );
      return f;
    } catch (_) {
      f.secrets.uninstall();
      rethrow;
    }
  }

  ModelProfile profile({bool native = true, bool streaming = false, bool remote = false}) => ModelProfile(
    id: profileCanary,
    endpoint: Uri.parse(remote ? 'https://offline.invalid/v1/chat/completions' : 'http://127.0.0.1:9/v1/chat/completions'),
    location: remote ? ModelLocation.remote : ModelLocation.local,
    modelId: 'synthetic-model',
    endpointIdentity: endpointCanary,
    credentialRef: credentialRefCanary,
    capabilities: ModelCapabilities(nativeTools: native, streaming: streaming, source: CapabilitySource.userDeclared),
  );

  Map<String, Object?> get projection => {
    'found': true,
    'objectRefs': [
      {
        'moduleId': selected.moduleId, 'objectType': selected.objectType,
        'objectId': selected.objectId, 'revisionRef': selected.revisionRef,
        'contentDigest': selected.contentDigest,
      },
    ],
  };

  Future<PersonalTask> start({ModelProfile? withProfile, String prompt = 'Read the selected supplier metadata.'}) => host.personalAgent.start(
    conversationId: conversation.id, prompt: prompt, profile: withProfile ?? profile(),
  );

  List<Map<String, Object?>> get receiptRows => [
    for (final row in host.foundation.database.raw.select('SELECT * FROM tool_invocation_receipts')) Map<String, Object?>.from(row),
  ];

  List<Map<String, dynamic>> frames(String filename) {
    final bytes = File(p.join(evidence.path, filename)).readAsBytesSync();
    final frames = <Map<String, dynamic>>[];
    var offset = 0;
    while (offset < bytes.length) {
      expect(bytes.length - offset, greaterThanOrEqualTo(4));
      final size = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
      expect(size, inInclusiveRange(1, 65536));
      offset += 4;
      expect(bytes.length - offset, greaterThanOrEqualTo(size));
      frames.add(jsonDecode(utf8.decode(bytes.sublist(offset, offset + size))) as Map<String, dynamic>);
      offset += size;
    }
    return frames;
  }

  void assertReaped() {
    final exitFile = File(p.join(evidence.path, 'exit.json'));
    expect(exitFile.existsSync(), isTrue, reason: 'real child must be waited/reaped before facade settles');
    final exit = jsonDecode(exitFile.readAsStringSync()) as Map;
    expect(exit['reaped'], true);
    final launch = jsonDecode(File(p.join(evidence.path, 'launch.json')).readAsStringSync()) as Map;
    expect(launch['binary'], requiredBinary());
    expect(launch['arguments'], contains('host-session'));
    expect(Directory('/proc/${launch['pid']}').existsSync(), isFalse);
    final keys = (launch['environment_keys'] as List).cast<String>();
    expect(keys.where((key) => RegExp(r'(TOKEN|SECRET|API_KEY|PROXY|AGENT_EVAL)', caseSensitive: false).hasMatch(key)), isEmpty);
  }

  void assertPrivateBoundary() {
    final ipc = [
      File(p.join(evidence.path, 'host.bin')).readAsBytesSync(),
      File(p.join(evidence.path, 'core.bin')).readAsBytesSync(),
      File(p.join(evidence.path, 'stderr.bin')).readAsBytesSync(),
    ].map((bytes) => latin1.decode(bytes)).join();
    final messages = jsonEncode([for (final body in transport.bodies) body['messages']]);
    final errors = [
      for (final task in host.foundation.tasks()) task.error,
      for (final row in host.outbound.recent()) row['error'],
    ].join();
    for (final marker in [secretCanary, credentialRefCanary, profileCanary, endpointCanary, privateName, privateNotes, 'SECOND_PRIVATE_NOTE']) {
      expect(ipc.contains(marker), isFalse, reason: 'private marker escaped IPC');
      expect(messages.contains(marker), isFalse, reason: 'private marker escaped model messages');
      expect(errors.contains(marker), isFalse, reason: 'private marker escaped error logs');
    }
    expect(transport.authorizationHeaders.every((value) => value == 'Bearer $secretCanary'), isTrue,
      reason: 'only transport authorization header receives synthetic credential');
  }

  Future<void> closeHost() async {
    if (closed) return;
    closed = true;
    await host.close();
  }

  Future<void> dispose() async {
    await closeHost();
    secrets.uninstall();
    await transport.dispose();
    final destination = Platform.environment['MUYON_TEST_CORE_AGENT_EVIDENCE_DIR'];
    if (destination != null && evidence.existsSync()) {
      final retained = Directory(p.join(destination, p.basename(root.path)))..createSync(recursive: true);
      for (final file in evidence.listSync().whereType<File>()) {
        file.copySync(p.join(retained.path, p.basename(file.path)));
      }
    }
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

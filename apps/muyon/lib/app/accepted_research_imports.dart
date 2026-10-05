import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:uuid/uuid.dart';

import '../services/transfer/transfer_service.dart';
import '../workspace/import_coordinator.dart';
import 'bootstrap.dart';

enum ResearchImportCommitState { committed, notCommitted, unknown }

/// The receipt determines business truth independently of transfer bookkeeping.
class ResearchImportFailure implements Exception {
  const ResearchImportFailure({
    required this.itemId,
    required this.commitState,
    required this.error,
    this.receiptError,
  });
  final String itemId;
  final ResearchImportCommitState commitState;
  final Object error;
  final Object? receiptError;

  String get title => switch (commitState) {
    ResearchImportCommitState.committed => '研究数据已提交，后续状态待恢复',
    ResearchImportCommitState.notCommitted => '研究包未导入',
    ResearchImportCommitState.unknown => '研究导入结果未知',
  };

  String get description {
    final truth = switch (commitState) {
      ResearchImportCommitState.committed => '已确认持久导入回执；研究数据已提交，绑定或传输状态尚未完成。',
      ResearchImportCommitState.notCommitted => '未找到该接纳记录的导入回执；本次研究导入未提交。',
      ResearchImportCommitState.unknown => '无法确认持久回执，不能判断研究数据是否已提交。',
    };
    return '接纳记录 $itemId：$truth 错误：$error。'
        '${receiptError == null ? '' : ' 回执检查：$receiptError。'}'
        '不会自动重放研究导入。';
  }

  @override
  String toString() => '$title：$description';
}

/// Human acceptance imports data into an isolated workspace, never executes it.
/// Transfer callbacks are void; track completion and report failures durably.
class AcceptedResearchImports {
  AcceptedResearchImports(this.host);
  final MuyonHost host;
  Future<void> _settled = Future.value();
  Future<void> get settled => _settled;
  final Set<String> _admitted = {};

  static String _operation(String id) => 'transfer-research:$id';
  static String _token(TransferItem item) =>
      '${_operation(item.id)}:${item.attachmentSha256}';

  void accept(TransferItem item) {
    if (!_admitted.add(item.id)) return;
    final operation = host.trackOperation(() async {
      try {
        await _import(item);
      } catch (error, stack) {
        await _reportFailure(item, error, stack, runtime: host.research);
      }
    });
    // Admission can fail while closing; there is no new work after shutdown.
    _settled = Future.wait<void>([_settled, operation]).then<void>((_) {});
    unawaited(_settled.catchError((Object _) {}));
  }

  bool _matchesReceipt(TransferItem item, ImportReceipt receipt) =>
      receipt.intent.operationId == _operation(item.id) &&
      receipt.intent.moduleId == 'research' &&
      receipt.intent.inputDigest == item.attachmentSha256 &&
      receipt.intent.stagingToken == _token(item);

  Future<void> _reportFailure(
    TransferItem item,
    Object error,
    StackTrace stack, {
    required ResearchRuntime? runtime,
  }) async {
    var state = ResearchImportCommitState.unknown;
    Object? receiptError;
    try {
      if (runtime == null) {
        throw StateError('Research receipt store unavailable');
      }
      final receipt = await runtime.receipt(_operation(item.id));
      if (receipt == null) {
        state = ResearchImportCommitState.notCommitted;
      } else if (_matchesReceipt(item, receipt)) {
        state = ResearchImportCommitState.committed;
      } else {
        throw StateError('Receipt identity differs from accepted attachment');
      }
    } catch (inspectionError) {
      receiptError = inspectionError;
    }
    final outcome = ResearchImportFailure(
      itemId: item.id,
      commitState: state,
      error: error,
      receiptError: receiptError,
    );
    try {
      await host.foundation.notify(
        title: outcome.title,
        body: outcome.description,
      );
    } catch (notificationError) {
      // The standard production Flutter error handler/log remains observable
      // even when the notification database cannot persist the outcome.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: outcome,
          stack: stack,
          library: 'muyon.research.import',
          context: ErrorDescription('研究导入通知持久化失败：$notificationError'),
        ),
      );
    }
  }

  bool _stillAccepted(TransferItem expected) {
    final item = host.services.transfer
        .items()
        .where((row) => row.id == expected.id)
        .firstOrNull;
    return item != null &&
        item.acceptance == 'accepted' &&
        !item.imported &&
        item.delivered &&
        item.attachmentState == 'durable' &&
        item.path != null &&
        item.attachmentSha256 != null &&
        item.attachmentLength != null &&
        item.attachmentLength! > 0 &&
        item.path == expected.path &&
        item.attachmentSha256 == expected.attachmentSha256 &&
        item.attachmentLength == expected.attachmentLength &&
        item.peerFingerprint == expected.peerFingerprint;
  }

  void _requireAccepted(TransferItem expected) {
    if (!_stillAccepted(expected)) {
      throw StateError('接纳已撤销、附件状态改变或导入已完成');
    }
  }

  Future<void> _import(TransferItem item) async {
    _requireAccepted(item);
    // Start activation within the admitted host operation so close can drain it.
    await host.activateResearch();
    _requireAccepted(item);
    final runtime = host.research;
    if (runtime == null) {
      throw StateError(host.researchError ?? 'Research unavailable');
    }
    final path = item.path!;
    const limit = TransferService.maxBytes * 2;
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        item.attachmentLength! > limit ||
        await File(path).length() != item.attachmentLength) {
      throw const FormatException('研究附件缺失、大小改变或不是普通文件');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead(0, limit + 1)) {
      buffer.add(chunk);
      if (buffer.length > limit) throw const FormatException('研究附件过大');
    }
    final bytes = buffer.takeBytes();
    if (bytes.length != item.attachmentLength ||
        sha256.convert(bytes).toString() != item.attachmentSha256) {
      throw const FormatException('研究附件与人工接纳的摘要不一致');
    }
    _requireAccepted(item);
    // Other accepted attachments belong to their own business handlers.
    if (!TransferService.isResearchPackage(bytes)) return;
    final exchange = ResearchPackageExchange(
      CardStore(runtime.resources.database),
    );
    final projectId = const Uuid().v4();
    ImportTarget target(String workspaceId) => ImportTarget.create(
      WorkspaceBinding(
        workspaceId: workspaceId,
        moduleId: 'research',
        nativeProjectId: projectId,
      ),
    );
    // Validate the complete frozen bytes before creating any host workspace.
    exchange.prepareBytes(
      bytes,
      target(_operation(item.id)),
      stagingToken: _token(item),
    );
    _requireAccepted(item);
    final workspace = await host.workspaces.create('接纳的研究包 · ${item.id}');
    _requireAccepted(item);
    final prepared = exchange.prepareBytes(
      bytes,
      target(workspace.id),
      stagingToken: _token(item),
      checkBeforeCommit: () => _requireAccepted(item),
    );
    final coordinator = ImportCoordinator(host.workspaces);
    final intent = await coordinator.record(
      prepared,
      operationId: _operation(item.id),
    );
    _requireAccepted(item);
    await coordinator.commit(runtime, prepared, intent);
    _requireAccepted(item);
    await host.services.transfer.markImported(item.id);
  }

  /// Restore only completed business imports. Never commit pending input here.
  Future<void> reconcileCommitted(ResearchRuntime runtime) async {
    for (final item in host.services.transfer.items()) {
      if (item.acceptance != 'accepted' || item.imported) continue;
      try {
        final receipt = await runtime.receipt(_operation(item.id));
        if (receipt == null) continue;
        if (!_matchesReceipt(item, receipt)) {
          throw StateError('Receipt identity differs from accepted attachment');
        }
        final rows = host.workspaces.database.raw.select(
          'SELECT status FROM import_intents WHERE operation_id=?',
          [_operation(item.id)],
        );
        if (rows.isEmpty || rows.single['status'] != 'complete') continue;
        // Revalidate the durable host identity and binding before the transfer flag.
        if (!_stillAccepted(item)) continue;
        await ImportCoordinator(host.workspaces).activate(receipt);
        if (!_stillAccepted(item)) continue;
        await host.services.transfer.markImported(item.id);
      } catch (error, stack) {
        // A transfer bookkeeping failure must not disable the research module
        // or block independent receipts. Never replay the domain commit here.
        await _reportFailure(item, error, stack, runtime: runtime);
      }
    }
  }
}

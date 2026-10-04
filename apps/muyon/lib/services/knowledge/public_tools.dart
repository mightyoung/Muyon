import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:muyon_module_api/muyon_module_api.dart';

import '../../platform/tool_registry.dart';
import '../../workspace/workspace_repository.dart';
import '../models/model_gateway.dart';
import '../models/profile_repository.dart';
import '../public_services.dart';

Future<void> registerPublicTools(
  PublicServices services,
  ToolRegistry tools,
  WorkspaceRepository workspaces,
) async {
  const string = {'type': 'string', 'minLength': 1, 'maxLength': 8192};
  const digest = {'type': 'string', 'minLength': 64, 'maxLength': 64};
  const docFields = {'documentId': string, 'sourceDigest': digest};
  const profileFields = {
    'profileId': string,
    'modelId': string,
    'endpointIdentity': string,
  };
  void register(
    String id,
    ToolEffect effect,
    Map<String, Object?> fields,
    Future<ToolCallResult> Function(ToolCallContext) handler, {
    bool available = true,
    String? reason,
    Set<AssistantScopeKind>? scopes,
  }) {
    tools.register(
      providerId: 'muyon.public',
      descriptor: ToolDescriptor(
        toolId: id,
        moduleId: 'knowledge',
        effect: effect,
        parameterSchema: {
          'type': 'object',
          'properties': fields,
          'required': fields.keys.toList(),
          'additionalProperties': false,
        },
        supportsCancel: true,
      ),
      handler: handler,
      available: available,
      unavailableReason: reason,
      supportedScopes: scopes ?? const {...AssistantScopeKind.values},
    );
  }

  ToolCallResult done(
    String summary, [
    Map<String, Object?> data = const {},
    List<ObjectRef> refs = const [],
  ]) => ToolCallResult(
    status: ToolCallStatus.succeeded,
    summary: summary,
    data: data,
    objectRefs: refs,
  );
  KnowledgeDocument scoped(ToolCallContext call) {
    final doc = services.knowledge.require(
      call.request.parameters['documentId'] as String,
    );
    if (!call.resolvedScope.contains(doc.source) ||
        call.request.parameters['sourceDigest'] != doc.digest) {
      throw StateError(
        'Knowledge document revision/digest outside approved scope',
      );
    }
    return doc;
  }

  List<KnowledgeDocument> selected(ToolCallContext call) => services.knowledge
      .documents()
      .where((d) => call.resolvedScope.contains(d.source))
      .toList();
  Future<void> fresh(ToolCallContext call, KnowledgeDocument doc) async {
    call.checkBeforeEffect();
    if (!call.resolvedScope.contains(doc.source) ||
        !await services.knowledge.isCurrent(doc.id)) {
      throw StateError('Knowledge source changed');
    }
    call.checkBeforeEffect();
  }

  ModelProfile profile(ToolCallContext call) {
    final params = call.request.parameters;
    final value = ProfileRepository(workspaces)
        .all()
        .where((p) => p.id == params['profileId'])
        .firstOrNull;
    if (value == null ||
        value.purpose != ModelPurpose.embedding ||
        value.endpoint.toString() != call.request.destination ||
        value.modelId != params['modelId'] ||
        value.endpointIdentity != params['endpointIdentity']) {
      throw StateError('Embedding endpoint/profile changed or not approved');
    }
    return value;
  }

  ModelCancellation cancellation(ToolCallContext call) {
    final token = ModelCancellation();
    call.cancellation.whenCancelled.then((_) => token.cancel());
    return token;
  }

  register('knowledge.search', ToolEffect.read, {'query': string}, (
    call,
  ) async {
    final docs = selected(call);
    final hits = await services.knowledge.search(
      call.request.parameters['query'] as String,
      documentIds: docs.map((d) => d.id).toList(),
    );
    return done('找到 ${hits.length} 条本地资料', {
      'hits': [
        for (final hit in hits)
          {
            'documentId': hit.documentId,
            'title': hit.title,
            'pageIndex': hit.pageIndex,
            'text': hit.text,
            'score': hit.score,
          },
      ],
    }, hits.map((h) => h.sourceRef).toSet().toList());
  });
  register('knowledge.index', ToolEffect.write, docFields, (call) async {
    final doc = scoped(call);
    await fresh(call, doc);
    await services.knowledge.index(
      doc.id,
      checkBeforeEffect: call.checkBeforeEffect,
    );
    return done('索引已更新', {'documentId': doc.id}, [doc.source]);
  });
  register('knowledge.delete', ToolEffect.write, docFields, (call) async {
    final doc = scoped(call);
    await fresh(call, doc);
    await services.knowledge.delete(
      doc.id,
      checkBeforeEffect: call.checkBeforeEffect,
    );
    return done('私有文档已删除', {'documentId': doc.id});
  });
  register(
    'knowledge.import',
    ToolEffect.write,
    {'path': string, 'sourceDigest': digest},
    (call) async {
      final path = call.request.parameters['path'] as String;
      if (await KnowledgeService.fileDigest(path) !=
          call.request.parameters['sourceDigest']) {
        throw StateError('Selected file changed');
      }
      call.checkBeforeEffect();
      final doc = await services.knowledge.importFile(
        path,
        expectedDigest: call.request.parameters['sourceDigest'] as String,
        checkBeforeEffect: call.checkBeforeEffect,
      );
      if (doc.digest != call.request.parameters['sourceDigest']) {
        await services.knowledge.delete(doc.id);
        throw StateError('Selected file changed');
      }
      return done('已导入宿主私有资料库', {
        'documentId': doc.id,
        'source': doc.source.toJson(),
      });
    },
    scopes: {AssistantScopeKind.global},
  );
  register('knowledge.embedding_preview', ToolEffect.read, docFields, (
    call,
  ) async {
    final doc = scoped(call);
    await fresh(call, doc);
    return done('待外传的索引文本摘要', services.embeddings.preview(doc.id), [
      doc.source,
    ]);
  });
  register(
    'embedding.build',
    ToolEffect.network,
    {...docFields, ...profileFields, 'textDigest': digest},
    (call) async {
      final doc = scoped(call), selectedProfile = profile(call);
      await fresh(call, doc);
      await services.embeddings.index(
        doc.id,
        profile: selectedProfile,
        cancellation: cancellation(call),
        expectedTextDigest: call.request.parameters['textDigest'] as String,
        checkBeforeEffect: call.checkBeforeEffect,
        beforeSend: () async {
          profile(call);
          await fresh(call, doc);
        },
      );
      return done(
        '已建立真实模型向量',
        {'documentId': doc.id, 'modelId': selectedProfile.modelId},
        [doc.source],
      );
    },
  );
  register(
    'embedding.search',
    ToolEffect.network,
    {'query': string, ...profileFields},
    (call) async {
      final docs = selected(call), selectedProfile = profile(call);
      final hits = await services.embeddings.search(
        call.request.parameters['query'] as String,
        profile: selectedProfile,
        documentIds: docs.map((d) => d.id).toList(),
        cancellation: cancellation(call),
        beforeSend: () async {
          call.checkBeforeEffect();
          profile(call);
          for (final d in docs) {
            await fresh(call, d);
          }
        },
      );
      return done('向量检索完成', {
        'hits': [
          for (final h in hits)
            {
              'documentId': h.documentId,
              'pageIndex': h.pageIndex,
              'text': h.text,
              'score': h.score,
            },
        ],
      }, hits.map((h) => h.sourceRef).toSet().toList());
    },
  );
  register('ocr.install_models', ToolEffect.network, {}, (call) async {
    if (call.request.destination != 'https://huggingface.co/PaddlePaddle') {
      throw StateError(
        'Model download destination must be official PaddlePaddle',
      );
    }
    call.checkBeforeEffect();
    await services.ocr.installModels(cancellation: cancellation(call));
    tools.setAvailability('ocr.recognize', available: true);
    return done('官方 OCR 模型下载并通过固定摘要校验');
  });
  register(
    'ocr.recognize',
    ToolEffect.read,
    docFields,
    (call) async {
      final doc = scoped(call);
      await fresh(call, doc);
      if (p.extension(doc.path).toLowerCase() == '.pdf') {
        final pages = await services.ocr.recognizePdf(
          doc.path,
          cancellation: cancellation(call),
        );
        await fresh(call, doc);
        return done(
          '本机 PDF 提取及扫描页 OCR 完成',
          {
            'sourceDigest': doc.digest,
            'pages': [
              for (final page in pages)
                {
                  'pageIndex': page.pageIndex,
                  'text': page.text,
                  'ocr': page.ocr != null,
                },
            ],
          },
          [doc.source],
        );
      }
      final result = await services.ocr.recognize(
        doc.path,
        cancellation: cancellation(call),
      );
      await fresh(call, doc);
      return done(
        '本机 OCR 完成',
        {
          'text': result.text,
          'sourceDigest': result.sourceDigest,
          'modelVersion': result.modelVersion,
          'coordinateSpace': result.coordinateSpace,
          'exifOrientation': result.exifOrientation,
          'lines': [
            for (final l in result.lines)
              {
                'text': l.text,
                'confidence': l.confidence,
                'detectionConfidence': l.detectionConfidence,
                'points': [
                  for (final p in l.points) [p.x, p.y],
                ],
              },
          ],
        },
        [doc.source],
      );
    },
    available: await services.ocr.available(),
    reason: '需要先安装已固定且校验通过的官方模型；不上传图像',
  );
  register('transfer.export', ToolEffect.write, {}, (call) async {
    final docs = selected(call);
    if (docs.isEmpty) throw StateError('Select documents to export');
    for (final doc in docs) {
      await fresh(call, doc);
    }
    call.checkBeforeEffect();
    final path = await services.transfer.exportFiles(
      docs.map((d) => d.path).toList(),
      checkBeforeEffect: call.checkBeforeEffect,
    );
    return done('已生成本机校验包，尚未发送', {
      'path': path,
      'sha256': await KnowledgeService.fileDigest(path),
    });
  });
  register(
    'transfer.import',
    ToolEffect.write,
    {'path': string, 'sourceDigest': digest},
    (call) async {
      final path = call.request.parameters['path'] as String;
      if (await KnowledgeService.fileDigest(path) !=
          call.request.parameters['sourceDigest']) {
        throw StateError('Package changed');
      }
      final receipt = await services.transfer.importPackage(
        path,
        expectedDigest: call.request.parameters['sourceDigest'] as String,
        checkCancelled: call.checkBeforeEffect,
      );
      return done('校验包已接收', {
        'receiptId': receipt.id,
        'sha256': receipt.digest,
        'paths': receipt.paths,
      });
    },
    scopes: {AssistantScopeKind.global},
  );
  register(
    'transfer.listen',
    ToolEffect.network,
    {'deviceId': string, 'deviceName': string},
    (call) async {
      if (call.request.destination != 'lan://local-network') {
        throw StateError('Explicit local-network destination required');
      }
      call.checkBeforeEffect();
      await services.transfer.start(
        deviceId: call.request.parameters['deviceId'] as String,
        deviceName: call.request.parameters['deviceName'] as String,
      );
      return done('已开启局域网发现与接收；传输未加密，接收文件等待人工导入');
    },
  );
  register('transfer.stop', ToolEffect.write, {}, (call) async {
    call.checkBeforeEffect();
    await services.transfer.close();
    return done('局域网监听已关闭');
  });
  register(
    'transfer.send',
    ToolEffect.network,
    {'path': string, 'sourceDigest': digest, 'peerId': string},
    (call) async {
      final path = call.request.parameters['path'] as String;
      if (!p.isWithin(
            p.join(services.transfer.rootPath, 'outbox'),
            p.normalize(path),
          ) ||
          await File(path).length() > TransferService.maxBytes * 2 ||
          await KnowledgeService.fileDigest(path) !=
              call.request.parameters['sourceDigest']) {
        throw StateError(
          'Only an approved unchanged outbox package may be sent',
        );
      }
      final manifest = jsonDecode(await File(path).readAsString()) as Map;
      final docs = selected(call);
      if (manifest['message'] != null ||
          (manifest['files'] as List).any(
            (entry) => !docs.any((d) => d.digest == entry['sha256']),
          )) {
        throw StateError('Transfer content is outside selected source scope');
      }
      final peer = services.transfer.peers
          .where((peer) => peer.id == call.request.parameters['peerId'])
          .firstOrNull;
      if (peer == null ||
          call.request.destination != 'http://${peer.address}:${peer.port}') {
        throw StateError('Peer destination changed or not explicitly approved');
      }
      for (final doc in docs) {
        await fresh(call, doc);
      }
      call.checkBeforeEffect();
      await services.transfer.send(
        peer,
        path,
        expectedDigest: call.request.parameters['sourceDigest'] as String,
        allowedMembers: {for (final doc in docs) doc.title: doc.digest},
        checkBeforeEffect: call.checkBeforeEffect,
      );
      return done('局域网文件已发送，业务导入需收件人确认');
    },
  );
}

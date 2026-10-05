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
    String description,
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
        description: description,
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

  register(
    'knowledge.search',
    '在本次范围的本地资料中做全文检索，返回标题、页码、文本片段与匹配分数。'
        '只读取本机索引与原文，不修改数据，也不发送到设备外。',
    ToolEffect.read,
    {'query': string},
    (
    call,
  ) async {
    final docs = selected(call);
    final hits = [
      for (final hit in await services.knowledge.search(
        call.request.parameters['query'] as String,
        documentIds: docs.map((d) => d.id).toList(),
      ))
        if (await services.knowledge.allowModelContent(hit.sourceRef)) hit,
    ];
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
  register(
    'knowledge.index',
    '重建指定资料的本地全文索引，摘要与分页随原文更新。'
        '会写入本机索引数据；不修改原始文件，也不发送到设备外。',
    ToolEffect.write,
    docFields,
    (call) async {
    final doc = scoped(call);
    await fresh(call, doc);
    await services.knowledge.index(
      doc.id,
      checkBeforeEffect: call.checkBeforeEffect,
    );
    return done('索引已更新', {'documentId': doc.id}, [doc.source]);
  });
  register(
    'knowledge.delete',
    '删除宿主私有资料库中的这份文档副本及其索引。'
        '会修改本机数据并移除该副本；不影响用户原始文件，也不发送到设备外。',
    ToolEffect.write,
    docFields,
    (call) async {
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
    '把指定路径的文件导入宿主私有资料库，并登记来源摘要与来源引用。'
        '会写入本机资料库；只在本机读取该文件，不发送到设备外。',
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
  register(
    'knowledge.embedding_preview',
    '预览这份资料中将要外传用于向量化的文本摘要与大小，便于人工核对。'
        '只读取本机内容，不发送任何数据。',
    ToolEffect.read,
    docFields,
    (
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
    '为指定资料建立向量：会把选定的文本摘要发送到已确认的向量模型端点，并把结果写入本机索引。'
        '需要端点、模型与文本摘要参数。',
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
    '用向量模型做语义检索：会把查询文本发送到已确认的向量模型端点，'
        '返回本机资料的匹配片段，不修改业务数据。',
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
  register(
    'ocr.install_models',
    '从 PaddlePaddle 官方地址下载 OCR 模型，校验固定摘要后安装到本机。'
        '会联网下载文件并写入本机模型目录，不上传任何本地内容。',
    ToolEffect.network,
    {},
    (call) async {
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
    '在本机对指定 PDF 或图片做文字识别，扫描页自动 OCR，返回文本、置信度与坐标。'
        '只读取本机文件，不联网，也不修改业务数据。',
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
  register(
    'transfer.export',
    '把已选资料导出为本机校验包，返回路径与摘要，供随后发送。'
        '会在本机生成新文件；此步不发送，也不修改原始资料。',
    ToolEffect.write,
    {},
    (call) async {
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
    '把本机收件区的校验包接收进私有收件区并登记回执。'
        '会写入本机文件；不自动导入业务数据，需人工接纳，也不联网。',
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
    '开启局域网发现与接收监听，等待已配对设备连接并接收其发送的文件（当前传输为明文）。'
        '会开放本机网络端口；接收内容需人工导入。',
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
  register(
    'transfer.stop',
    '关闭局域网监听并停止接收，不影响已接收的文件。'
        '会修改本机网络监听状态。',
    ToolEffect.write,
    {},
    (call) async {
    call.checkBeforeEffect();
    await services.transfer.close();
    return done('局域网监听已关闭');
  });
  register(
    'transfer.send',
    '把已确认的本机校验包发送给指定已配对设备。'
        '会通过网络把文件发出本机；收件方仍需人工接纳，业务导入不会自动发生。',
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

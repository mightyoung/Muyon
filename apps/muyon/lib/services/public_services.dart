import '../platform/storage_manager.dart';
import '../platform/tool_registry.dart';
import '../workspace/workspace_repository.dart';
import 'models/model_gateway.dart';
import 'knowledge/knowledge_service.dart';
import 'knowledge/embedding_service.dart';
import 'ocr/ocr_models.dart';
import 'ocr/paddle_ocr_service.dart';
import 'transfer/transfer_service.dart';
import 'knowledge/public_tools.dart';
export 'knowledge/knowledge_service.dart';
export 'knowledge/embedding_service.dart';
export 'ocr/paddle_ocr_service.dart';
export 'transfer/transfer_service.dart';

class PublicServices {
  PublicServices._(
    this.gateway,
    this.knowledge,
    this.embeddings,
    this.ocr,
    this.transfer,
  );
  final OpenAiModelGateway gateway;
  final KnowledgeService knowledge;
  final EmbeddingService embeddings;
  final PaddleOcrService ocr;
  final TransferService transfer;

  static Future<PublicServices> open({
    required StorageManager storage,
    required WorkspaceRepository workspaces,
    required OpenAiModelGateway gateway,
    required ToolRegistry tools,
  }) async {
    final database = await storage.open(
      'public_knowledge',
      KnowledgeService.schema,
    );
    final ocr = PaddleOcrService(OcrModels('${storage.rootPath}/ocr_models'));
    final knowledge = KnowledgeService(
      database,
      '${storage.rootPath}/public_files',
      parseImage: (path) async {
        final result = await ocr.recognize(path);
        if (result.text.trim().isEmpty) {
          throw StateError('OCR produced no readable text');
        }
        return KnowledgeParsedDocument(
          result.sourceDigest,
          [result.text],
          {0: _ocrMetadata(result)},
        );
      },
      parsePdf: (path) async {
        final before = await KnowledgeService.fileDigest(path);
        final pages = await ocr.recognizePdf(path);
        if (before != await KnowledgeService.fileDigest(path)) {
          throw StateError('PDF changed while indexing');
        }
        return KnowledgeParsedDocument(
          before,
          pages.map((p) => p.text).toList(),
          {
            for (final page in pages)
              if (page.ocr != null) page.pageIndex: _ocrMetadata(page.ocr!),
          },
        );
      },
    );
    final services = PublicServices._(
      gateway,
      knowledge,
      EmbeddingService(knowledge, gateway),
      ocr,
      TransferService(database, '${storage.rootPath}/transfer'),
    );
    await services.transfer.initialize();
    await registerPublicTools(services, tools, workspaces);
    return services;
  }

  Future<void> close() async {
    try {
      await transfer.close();
    } finally {
      await ocr.close();
    }
  }

  static Map<String, Object?> _ocrMetadata(OcrResult result) => {
    'modelVersion': result.modelVersion,
    'algorithmVersion': result.algorithmVersion,
    'coordinateSpace': result.coordinateSpace,
    'width': result.width,
    'height': result.height,
    'exifOrientation': result.exifOrientation,
    'lines': [
      for (final line in result.lines)
        {
          'text': line.text,
          'confidence': line.confidence,
          'detectionConfidence': line.detectionConfidence,
          'points': [
            for (final p in line.points) [p.x, p.y],
          ],
        },
    ],
  };
}

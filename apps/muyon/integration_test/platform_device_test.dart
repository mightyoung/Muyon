import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/services/ocr/ocr_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Device runner stages verified models under external files/ocr_models_validation
/// and the Chinese/English amount image at external files/ocr-fixture.png.
/// Every database and imported file belongs to a fresh cache directory.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android native OCR, offline knowledge, navigation and persistence',
    (tester) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'This acceptance targets Android',
      );
      Directory? sandbox;
      MuyonHost? host;
      final evidence = <String, dynamic>{
        'platform': Platform.operatingSystem,
        'ocrBackend': 'flutter_onnxruntime native; no reference backend',
      };
      binding.reportData = evidence;
      late String conversationId, taskId, imageId, imageDigest, textId;
      try {
        await tester.runAsync(() async {
          final external = await getExternalStorageDirectory();
          expect(external, isNotNull);
          final modelSource = Directory(
            p.join(external!.path, 'ocr_models_validation'),
          );
          final fixture = File(p.join(external.path, 'ocr-fixture.png'));
          expect(
            await fixture.exists(),
            isTrue,
            reason: 'Stage ocr-fixture.png before running',
          );
          final cache = await getTemporaryDirectory();
          sandbox = await cache.createTemp('muyon-device-validation-');
          final modelTarget = Directory(p.join(sandbox!.path, 'ocr_models'));
          await modelTarget.create(recursive: true);
          for (final asset in OcrModels.assets) {
            final input = File(p.join(modelSource.path, asset.name));
            expect(
              await input.exists(),
              isTrue,
              reason: 'Missing verified model ${asset.name}',
            );
            await input.copy(p.join(modelTarget.path, asset.name));
          }
          expect(
            await OcrModels(modelTarget.path).ready(),
            isTrue,
            reason: 'Pinned model sizes and SHA-256 must match',
          );
          host = await MuyonHost.open(sandbox!.path);
          final current = host!;
          expect(current.services.ocr.referenceInference, isNull);
          final timer = Stopwatch()..start();
          final result = await current.services.ocr.recognize(fixture.path);
          timer.stop();
          evidence['nativeOcrMilliseconds'] = timer.elapsedMilliseconds;
          evidence['nativeOcrText'] = result.text;
          evidence['nativeOcrLines'] = result.lines.length;
          evidence['ocrModelVersion'] = result.modelVersion;
          evidence['ocrCoordinateSpace'] = result.coordinateSpace;
          expect(result.text, contains('123.45'));
          expect(result.text, contains('678.90'));
          expect(result.lines, isNotEmpty);
          for (final line in result.lines) {
            expect(line.points, hasLength(4));
            expect(
              line.points.every(
                (point) => point.x.isFinite && point.y.isFinite,
              ),
              isTrue,
            );
          }
          final knowledge = current.services.knowledge;
          final image = await knowledge.importFile(fixture.path);
          imageId = image.id;
          imageDigest = image.digest;
          await knowledge.index(image.id);
          final imageHits = await knowledge.search(
            '采购',
            documentIds: [image.id],
          );
          expect(
            imageHits,
            isNotEmpty,
            reason: 'Real OCR output must enter offline FTS',
          );
          expect(imageHits.first.sourceRef, image.source);
          expect(imageHits.first.sourceRef.contentDigest, image.digest);
          final metadata = knowledge.ocrMetadata(
            image.id,
            imageHits.first.pageIndex,
          );
          expect(metadata, isNotNull);
          expect(metadata!['coordinateSpace'], result.coordinateSpace);
          final lines = metadata['lines'] as List;
          expect(lines, isNotEmpty);
          expect(
            lines.any((line) => (line['points'] as List).length == 4),
            isTrue,
          );
          evidence['imageFtsHits'] = imageHits.length;
          evidence['imageSource'] = image.source.toJson();
          evidence['ocrMetadataLines'] = lines.length;

          final text = File(p.join(sandbox!.path, 'offline-source.txt'));
          await text.writeAsString('采购验收记录 offlineacceptance 123.45 678.90');
          final document = await knowledge.importFile(text.path);
          textId = document.id;
          await knowledge.index(document.id);
          final textHits = await knowledge.search(
            'offlineacceptance',
            documentIds: [document.id],
          );
          expect(textHits, isNotEmpty);
          expect(textHits.first.sourceRef, document.source);
          final conversation = await current.foundation.createConversation(
            title: 'Android 实机验收',
          );
          conversationId = conversation.id;
          final task = await current.personalAgent.startTool(
            conversationId: conversation.id,
            toolId: 'knowledge.search',
            parameters: {'query': 'offlineacceptance'},
          );
          taskId = task.id;
          expect(task.state, PersonalTaskState.succeeded);
          expect(
            current.foundation.messages(conversation.id).last.references,
            isNotEmpty,
          );
          evidence['taskId'] = task.id;
          evidence['conversationId'] = conversation.id;
        });
        expect(host, isNotNull);
        await tester.pumpWidget(MuyonApp(host: host!));
        await tester.pumpAndSettle();
        expect(find.text('Folio · 询价台账'), findsOneWidget);
        expect(find.text('科研工作台'), findsOneWidget);
        final navigation = find.byType(NavigationBar).evaluate().isNotEmpty
            ? find.byType(NavigationBar)
            : find.byType(NavigationRail);
        for (final label in ['助手', '资料', '工具', '工作台']) {
          await tester.tap(
            find.descendant(of: navigation, matching: find.text(label)),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Device navigation: $label',
          );
          if (label == '助手') expect(find.byType(AssistantPage), findsOneWidget);
        }
        evidence['navigation'] = ['工作台', '助手', '资料', '工具'];
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await host!.close();
          host = await MuyonHost.open(sandbox!.path);
          final current = host!;
          expect(
            current.foundation.conversation(conversationId)?.title,
            'Android 实机验收',
          );
          expect(
            current.foundation.task(taskId)?.state,
            PersonalTaskState.succeeded,
          );
          expect(
            current.foundation.messages(conversationId).last.references,
            isNotEmpty,
          );
          expect(
            await current.services.knowledge.search(
              'offlineacceptance',
              documentIds: [textId],
            ),
            isNotEmpty,
          );
          final imageHits = await current.services.knowledge.search(
            '采购',
            documentIds: [imageId],
          );
          expect(imageHits, isNotEmpty);
          expect(imageHits.first.sourceRef.contentDigest, imageDigest);
          expect(current.services.knowledge.ocrMetadata(imageId, 0), isNotNull);
          evidence['reopenPersistence'] = true;
        });
        evidence['passed'] = true;
        binding.reportData = evidence;
        debugPrint('MIYONO_DEVICE_VALIDATION ${jsonEncode(evidence)}');
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await host?.close();
          if (sandbox != null && await sandbox!.exists()) {
            await sandbox!.delete(recursive: true);
          }
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

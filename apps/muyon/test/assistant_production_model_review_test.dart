import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';

import 'support/agent_loop_fixture.dart';

final class ModelReviewer implements OutboundContentReviewer {
  ModelReviewer(this.action);
  final String action;
  final requests = <OutboundReviewRequest>[];
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    requests.add(request);
    if (action == 'timeout') return Completer<ReviewDecision>().future;
    if (action == 'throw') {
      throw StateError('fixture secret should not persist');
    }
    return switch (action) {
      'allow' => const ReviewDecision.allow(),
      'confirm' => const ReviewDecision.confirm(
        'fixture secret should not persist',
      ),
      _ => const ReviewDecision.block('fixture secret should not persist'),
    };
  }
}

void main() {
  for (final action in ['allow', 'confirm', 'block', 'throw', 'timeout']) {
    test('actual host model wire review / $action', () async {
      final loop = await LoopFixture.open();
      final root = Directory.systemTemp.createTempSync('auth-model-review-');
      final reviewer = ModelReviewer(action);
      final host = await MuyonHost.open(
        root.path,
        localModelReviewer: reviewer,
      );
      addTearDown(() async {
        await host.close();
        root.deleteSync(recursive: true);
      });
      final conversation = await host.foundation.createConversation();
      loop.replies.add(LoopReply.sse(sseText('done')));
      var task = await host.personalAgent.start(
        conversationId: conversation.id,
        prompt: 'direct verified answer',
        profile: loop.profile(),
      );
      expect(reviewer.requests, hasLength(1));
      final request = reviewer.requests.single;
      final reviewedWire = jsonDecode(utf8.decode(request.content));
      expect(reviewedWire, contains('messages'));
      expect(request.endpoint, loop.profile().endpoint);
      if (action == 'block') {
        expect(task.state, PersonalTaskState.failed);
        expect(loop.bodies, isEmpty);
        expect(host.outbound.recent(), isEmpty);
      } else {
        if (action != 'allow') {
          expect(task.state, PersonalTaskState.waitingConfirmation);
          expect(loop.bodies, isEmpty);
          expect(host.outbound.recent(), isEmpty);
          await host.personalAgent.confirm(
            task.id,
            requestDigest: task.payload['requestDigest'] as String,
          );
          task = host.foundation.task(task.id)!;
        }
        expect(task.state, PersonalTaskState.succeeded);
        expect(loop.bodies.single, reviewedWire);
        final row = host.outbound.recent().single;
        expect(
          row['authorization_source'],
          action == 'allow' ? 'mode_auto' : 'manual',
        );
        expect(
          row['payload_sha256'],
          sha256.convert(request.content).toString(),
        );
        expect(row['grant_id'], isNull);
      }
      final reviews = host.foundation.database.raw.select(
        'SELECT * FROM assistant_review_decisions',
      );
      expect(reviews, hasLength(1));
      expect(reviews.single['reviewed'], 0);
      expect(
        reviews.single['payload_digest'],
        sha256.convert(request.content).toString(),
      );
      expect('${reviews.single}', isNot(contains('fixture secret')));
    });
  }
}

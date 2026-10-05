import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/memory_review.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

PersonalMemory _memory(
  String id,
  String content, {
  String source = '本人手动确认',
  bool verified = true,
  bool disabled = false,
  DateTime? expiresAt,
}) => PersonalMemory(
  id,
  content,
  source,
  DateTime.utc(2026, 10, 5),
  expiresAt,
  const AssistantScope.global(),
  null,
  verified,
  1,
  disabled: disabled,
);

void main() {
  test('groups duplicates and conflicts without deleting sources', () {
    final review = MemoryReview([
      _memory('a', '默认供应商：甲公司'),
      _memory('b', '默认供应商：甲公司', source: '另一来源'),
      _memory('c', '默认供应商：乙公司', verified: false),
      _memory('d', '旧偏好', expiresAt: DateTime.utc(2020, 1, 1)),
      _memory('e', '停用内容', disabled: true),
    ]);

    expect(review.duplicates.single.map((m) => m.id), ['a', 'b']);
    expect(review.conflicts.single.map((m) => m.id), ['a', 'b', 'c']);
    expect(review.expired.single.id, 'd');
    expect(review.disabled.single.id, 'e');
    // Only active memories are summarized, each with its source and state.
    expect(review.summary, hasLength(3));
    expect(review.summary.first, contains('已确认'));
    expect(review.summary.last, contains('待确认'));
  });

  test('whitespace differences merge as duplicates but stay reviewable', () {
    final review = MemoryReview([
      _memory('a', '默认  供应商：甲公司'),
      _memory('b', '默认 供应商：甲公司'),
    ]);
    // The duplicate group is built from normalized content …
    expect(review.duplicates.single, hasLength(2));
    // … while the raw difference is still a content-change candidate.
    expect(review.conflicts.single, hasLength(2));
  });

  test(
    'service refreshes after repository changes and dispose stops it',
    () async {
      final database = ManagedConnection(sqlite3.openInMemory());
      for (final migration in WorkspaceRepository.schema.migrations) {
        migration.migrate(database.raw);
      }
      final repository = FoundationRepository(database);
      final service = MemoryReviewService(repository);
      addTearDown(() async {
        service.dispose();
        repository.dispose();
        await database.close();
      });

      expect(service.current.duplicates, isEmpty);
      await repository.saveMemory(
        content: '默认供应商：甲公司',
        source: '本人手动确认',
        scope: const AssistantScope.global(),
      );
      await repository.saveMemory(
        content: '默认供应商：甲公司',
        source: '会议记录',
        scope: const AssistantScope.global(),
      );
      // The service debounces and refreshes after the repository notifies.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(service.current.duplicates.single, hasLength(2));

      service.dispose();
      await repository.saveMemory(
        content: '默认供应商：甲公司',
        source: '第三人',
        scope: const AssistantScope.global(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // A disposed service no longer recomputes: the stale proposal stays 2.
      expect(service.current.duplicates.single, hasLength(2));
    },
  );
}

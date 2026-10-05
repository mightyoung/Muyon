import 'dart:convert';
import 'dart:async';

import 'foundation_repository.dart';

class MemoryReviewService {
  MemoryReviewService(this.repository) {
    repository.addListener(_schedule);
    _refresh();
  }
  final FoundationRepository repository;
  late MemoryReview current;
  Timer? _pending;
  void _schedule() {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 200), _refresh);
  }

  void _refresh() {
    current = MemoryReview(
      repository.memories(includeExpired: true, includeDisabled: true),
    );
  }

  void dispose() {
    _pending?.cancel();
    repository.removeListener(_schedule);
  }
}

/// Read-only maintenance proposals. Decisions and source records stay intact.
class MemoryReview {
  MemoryReview(List<PersonalMemory> memories) {
    final groups = <String, List<PersonalMemory>>{};
    final assertions = <String, List<PersonalMemory>>{};
    for (final memory in memories) {
      if (memory.disabled) {
        disabled.add(memory);
        continue;
      }
      if (memory.isExpired) {
        expired.add(memory);
        continue;
      }
      final scope = jsonEncode(memory.scope.toJson());
      final normalized = memory.content.trim().replaceAll(RegExp(r'\s+'), ' ');
      groups.putIfAbsent('$scope\u0000$normalized', () => []).add(memory);
      // A changed explicit key/value is a review candidate, never proof of a contradiction.
      final match = RegExp(r'^([^：:\n]{1,40})[：:]\s*(.+)$')
          .firstMatch(normalized);
      if (match != null) {
        assertions
            .putIfAbsent('$scope\u0000${match[1]!.trim()}', () => [])
            .add(memory);
      }
      summary.add(
        '• ${memory.content}\n  来源：${memory.source}${memory.verified ? '（已确认）' : '（待确认）'}',
      );
    }
    duplicates.addAll(groups.values.where((group) => group.length > 1));
    conflicts.addAll(
      assertions.values.where(
        (group) => group.map((memory) => memory.content).toSet().length > 1,
      ),
    );
  }
  final List<PersonalMemory> expired = [], disabled = [];
  final List<List<PersonalMemory>> duplicates = [], conflicts = [];
  final List<String> summary = [];
}

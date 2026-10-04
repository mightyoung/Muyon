import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/src/source_ref.dart';

void main() {
  final key = ObjectKey(
    originProjectKey: 'origin',
    objectType: 'document',
    objectUuid: 'document',
  );
  test(
    'source retains byte identity and physical page across metadata edits',
    () {
      final source = SourceRef(
        documentRef: key,
        contentDigest: 'a' * 64,
        pageIndex: 0,
        quote: '研究原句 😀',
        contextBefore: '前文',
        contextAfter: '后文',
      );
      final restored = SourceRef.fromJson(source.toJson());
      expect(restored.documentRef, key);
      expect(restored.pageIndex, 0);
      expect(restored.quote, source.quote);
      expect(
        restored.availability(exists: true, currentDigest: 'a' * 64),
        SourceAvailability.pageLevel,
      );
      expect(
        restored.availability(exists: true, currentDigest: 'b' * 64),
        SourceAvailability.replaced,
      );
      expect(
        restored.availability(exists: false, currentDigest: null),
        SourceAvailability.missing,
      );
    },
  );
  test('source rejects unsafe page and digest', () {
    expect(
      () => SourceRef(
        documentRef: key,
        contentDigest: 'a' * 64,
        pageIndex: -1,
        quote: 'q',
      ),
      throwsFormatException,
    );
    expect(
      () => SourceRef(
        documentRef: key,
        contentDigest: 'a' * 64,
        pageIndex: 9007199254740992,
        quote: 'q',
      ),
      throwsFormatException,
    );
    expect(
      () => SourceRef(
        documentRef: key,
        contentDigest: 'wrong',
        pageIndex: 1,
        quote: 'q',
      ),
      throwsFormatException,
    );
  });
}

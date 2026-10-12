import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/model_reference_map.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// C6-REDO: opaque model references are bound to task, scope and snapshot pin.
void main() {
  const digest =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const object = ObjectRef(
    moduleId: 'inquiry',
    objectType: 'quotation',
    objectId: 'q1',
    nativeProjectId: 'p1',
    revisionRef: '2',
    contentDigest: digest,
  );
  const a = ModelReferenceBinding(
    taskId: 'task-a',
    scopeKey: 'scope-1',
    pin: 'pin-1',
  );
  late ModelReferenceMap map;
  setUp(() => map = ModelReferenceMap(List.filled(32, 7)));

  Matcher rejected(String code) => throwsA(
    isA<ModelReferenceRejected>().having((e) => e.code, 'code', code),
  );

  test('a handle reveals neither the digest nor the identity', () {
    final handle = map.handleFor(object, binding: a);
    expect(handle, startsWith('mr1_'));
    expect(handle, isNot(contains(digest)));
    expect(handle, isNot(contains('q1')));
    expect(handle.length, greaterThan(20));
  });

  test('the same object in the same binding gets the same handle', () {
    expect(
      map.handleFor(object, binding: a),
      map.handleFor(object, binding: a),
    );
  });

  test('handles differ per task, scope, pin, object and row digest', () {
    final base = map.handleFor(object, binding: a);
    for (final other in [
      const ModelReferenceBinding(
        taskId: 'task-b',
        scopeKey: 'scope-1',
        pin: 'pin-1',
      ),
      const ModelReferenceBinding(
        taskId: 'task-a',
        scopeKey: 'scope-2',
        pin: 'pin-1',
      ),
      const ModelReferenceBinding(
        taskId: 'task-a',
        scopeKey: 'scope-1',
        pin: 'pin-2',
      ),
    ]) {
      expect(map.handleFor(object, binding: other), isNot(base));
    }
    const edited = ObjectRef(
      moduleId: 'inquiry',
      objectType: 'quotation',
      objectId: 'q1',
      nativeProjectId: 'p1',
      revisionRef: '2',
      contentDigest:
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    );
    expect(map.handleFor(edited, binding: a), isNot(base));
  });

  test('the host key matters: another key gives another handle', () {
    final other = ModelReferenceMap(List.filled(32, 9));
    expect(
      other.handleFor(object, binding: a),
      isNot(map.handleFor(object, binding: a)),
    );
  });

  test('a minted handle resolves to the full object in its own binding', () {
    final handle = map.handleFor(object, binding: a);
    final resolved = map.resolve(handle, current: a);
    expect(resolved, object);
    expect(resolved.contentDigest, digest);
  });

  test('forged, truncated and unminted handles are rejected', () {
    final handle = map.handleFor(object, binding: a);
    expect(
      () => map.resolve('mr1_' + 'A' * 32, current: a),
      rejected('unknown'),
    );
    expect(
      () => map.resolve(handle.substring(0, handle.length - 2), current: a),
      rejected('unknown'),
    );
    expect(
      () => map.resolve(handle.replaceFirst('mr1_', 'mr2_'), current: a),
      rejected('unknown'),
    );
    expect(() => map.resolve('', current: a), rejected('unknown'));
    expect(() => map.resolve(object.objectId, current: a), rejected('unknown'));
    expect(() => map.resolve(digest, current: a), rejected('unknown'));
  });

  test('a handle from another map instance is not recognised', () {
    final handle = ModelReferenceMap(List.filled(32, 7))
        .handleFor(object, binding: a);
    // same key => same handle, but this instance never minted it
    expect(() => map.resolve(handle, current: a), rejected('unknown'));
  });

  test('another task, another scope and an expired pin are rejected', () {
    final handle = map.handleFor(object, binding: a);
    expect(
      () => map.resolve(
        handle,
        current: const ModelReferenceBinding(
          taskId: 'task-b',
          scopeKey: 'scope-1',
          pin: 'pin-1',
        ),
      ),
      rejected('cross_task'),
    );
    expect(
      () => map.resolve(
        handle,
        current: const ModelReferenceBinding(
          taskId: 'task-a',
          scopeKey: 'scope-2',
          pin: 'pin-1',
        ),
      ),
      rejected('wrong_scope'),
    );
    expect(
      () => map.resolve(
        handle,
        current: const ModelReferenceBinding(
          taskId: 'task-a',
          scopeKey: 'scope-1',
          pin: 'pin-2',
        ),
      ),
      rejected('expired'),
    );
  });

  test('revoking a task revokes its handles and no one else\'s', () {
    final mine = map.handleFor(object, binding: a);
    const b = ModelReferenceBinding(
      taskId: 'task-b',
      scopeKey: 'scope-1',
      pin: 'pin-1',
    );
    final theirs = map.handleFor(object, binding: b);
    map.revokeTask('task-a');
    expect(() => map.resolve(mine, current: a), rejected('revoked'));
    expect(map.resolve(theirs, current: b), object);
    // re-minting after revocation does not resurrect the old grant silently
    expect(map.handleFor(object, binding: a), mine);
    expect(map.resolve(mine, current: a), object);
  });

  test('a handle never resolves an object without a digest', () {
    const bare = ObjectRef(
      moduleId: 'inquiry',
      objectType: 'quotation',
      objectId: 'q2',
    );
    expect(() => map.handleFor(bare, binding: a), throwsArgumentError);
  });

  test('the map is bounded and evicted handles become unknown', () {
    final small = ModelReferenceMap(List.filled(32, 7), maxHandles: 3);
    final first = small.handleFor(object, binding: a);
    for (var i = 0; i < 3; i++) {
      small.handleFor(
        ObjectRef(
          moduleId: 'inquiry',
          objectType: 'quotation',
          objectId: 'x$i',
          contentDigest: digest,
        ),
        binding: a,
      );
    }
    expect(() => small.resolve(first, current: a), rejected('unknown'));
  });

  group('model projection of JSON', () {
    test(
      'object references lose the digest and gain a handle, recursively',
      () {
        final raw = {
          'scope': {
            'objects': [object.toJson()],
          },
          'trustedToolResult': {
            'objectRefs': [object.toJson()],
            'data': {'contentDigest': 'keep-research-digest', 'n': 1},
            'artifactRefs': [
              {
                'moduleId': 'inquiry',
                'artifactId': 'a',
                'contentDigest': digest,
              },
            ],
          },
          'text': 'note mentions $digest',
        };
        final out = projectModelJson(raw, map, a) as Map;
        final text = jsonEncode(out);
        final refs = ((out['trustedToolResult'] as Map)['objectRefs'] as List)
            .cast<Map>();
        expect(refs.single['objectId'], 'q1');
        expect(refs.single.containsKey('contentDigest'), isFalse);
        expect(
          map.resolve(refs.single['modelRef'] as String, current: a),
          object,
        );
        // unrelated data keeps its own keys
        expect(
          ((out['trustedToolResult'] as Map)['data'] as Map)['contentDigest'],
          'keep-research-digest',
        );
        // artifact digests are not sent either
        final artifact =
            (((out['trustedToolResult'] as Map)['artifactRefs']) as List).single
                as Map;
        expect(artifact.containsKey('contentDigest'), isFalse);
        expect(text, contains('note mentions'));
      },
    );

    test('the input is not modified', () {
      final raw = {'o': object.toJson()};
      projectModelJson(raw, map, a);
      expect((raw['o'] as Map)['contentDigest'], digest);
    });

    test('JSON text messages are projected and plain text is left alone', () {
      final json = jsonEncode({'scope': object.toJson()});
      final projected = projectModelMessageContent(json, map, a);
      expect(projected, isNot(contains(digest)));
      expect(projected, contains('modelRef'));
      expect(
        projectModelMessageContent('plain $digest', map, a),
        'plain $digest',
      );
      expect(projectModelMessageContent('{broken', map, a), '{broken');
    });
  });
}

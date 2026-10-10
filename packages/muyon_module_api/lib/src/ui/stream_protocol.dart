import 'dart:convert';

import 'intent.dart';
import 'plan.dart';
import 'snapshot.dart';

/// All quantities in bytes use UTF-8, rather than Dart string length.
class UiStreamLimits {
  const UiStreamLimits({
    this.nodes = 200,
    this.depth = 12,
    this.lineBytes = 16 * 1024,
    this.textBytes = 64 * 1024,
    this.lines = 2000,
    this.badLines = 20,
    this.patchesPerNode = 20,
    this.diagnostics = 100,
  });
  static const v1 = UiStreamLimits();
  final int nodes,
      depth,
      lineBytes,
      textBytes,
      lines,
      badLines,
      patchesPerNode,
      diagnostics;
}

const streamProtocolV1 = 'aiui-stream/1';
const streamProtocolV2 = 'aiui-stream/2';

/// Trusted host inputs; the stream can never replace this metadata.
class UiStreamSession {
  UiStreamSession({
    required this.surfaceId,
    required this.revision,
    required this.snapshot,
    required this.intent,
    required this.catalog,
    this.root = 'root',
    this.protocolVersion = streamProtocolV1,
  }) {
    if (protocolVersion != streamProtocolV1 &&
        protocolVersion != streamProtocolV2) {
      throw ArgumentError.value(protocolVersion, 'protocolVersion');
    }
    if (catalog.version == 'library-2' && protocolVersion != streamProtocolV2) {
      throw ArgumentError.value(
        protocolVersion,
        'protocolVersion',
        'catalog_requires_stream_2',
      );
    }
  }
  final String surfaceId, root, protocolVersion;
  final int revision;
  final DataSnapshot snapshot;
  final InteractionIntent intent;
  final UiCatalog catalog;
  UIPlan plan(List<UiNode> nodes) => UIPlan(
    surfaceId: surfaceId,
    revision: revision,
    catalogVersion: catalog.version,
    snapshotRef: snapshot.ref,
    intentRef: intent.id,
    root: root,
    nodes: nodes,
  );
}

enum UiStreamErrorCode {
  malformedLine,
  unknownOperation,
  invalidFields,
  lineLimit,
  textLimit,
  nodeLimit,
  depthLimit,
  lineCountLimit,
  badLineLimit,
  patchLimit,
  missingParent,
  duplicateId,
  missingTarget,
  afterEnd,
  malformedStream,
}

class UiStreamError {
  const UiStreamError(this.code, this.reason, {this.protocolError = true});
  final bool protocolError;
  final UiStreamErrorCode code;
  final String reason;
}

sealed class UiStreamOperation {}

class UiStreamText extends UiStreamOperation {
  UiStreamText(this.markdown);
  final String markdown;
}

class UiStreamNode extends UiStreamOperation {
  UiStreamNode(this.node, this.parent);
  final UiNode node;
  final String? parent;
}

class UiStreamPatch extends UiStreamOperation {
  UiStreamPatch(this.id, this.properties);
  final String id;
  final Map<String, Object?> properties;
}

class UiStreamAction extends UiStreamOperation {
  UiStreamAction(
    this.nodeId,
    this.event,
    this.actionRef,
    this.inputs,
    this.operation,
  );
  final String nodeId, event, actionRef;
  final List<String> inputs;
  final String? operation;
}

class UiStreamEnd extends UiStreamOperation {}

class UiStreamParseResult {
  const UiStreamParseResult({this.operation, this.error});
  final UiStreamOperation? operation;
  final UiStreamError? error;
}

/// Accepts exactly one complete JSONL line. Errors stay within this boundary.
UiStreamParseResult parseUiStreamLine(
  String line, {
  UiStreamLimits limits = UiStreamLimits.v1,
  String protocolVersion = streamProtocolV1,
}) {
  if (utf8.encode(line).length > limits.lineBytes) {
    return const UiStreamParseResult(
      error: UiStreamError(UiStreamErrorCode.lineLimit, 'line_limit'),
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on Object {
    return const UiStreamParseResult(
      error: UiStreamError(UiStreamErrorCode.malformedLine, 'malformed_json'),
    );
  }
  try {
    final m = decoded as Map<String, dynamic>;
    final op = m['op'];
    if (!{'text', 'node', 'patch', 'action', 'end'}.contains(op)) {
      return const UiStreamParseResult(
        error: UiStreamError(UiStreamErrorCode.unknownOperation, 'unknown_op'),
      );
    }
    String string(String key) {
      final value = m[key];
      if (value is! String || value.isEmpty) throw const FormatException();
      return value;
    }

    void fields(Set<String> allowed) {
      if (m.keys.any((key) => !allowed.contains(key)))
        throw const FormatException();
    }

    Map<String, Object?> props() {
      if (!m.containsKey('props')) return const {};
      // Property types belong to the shared schema validator. Preserve every
      // JSON value in the candidate, even when the schema will reject it.
      return Map.unmodifiable(m['props'] as Map<String, dynamic>);
    }

    Map<String, BindingRef> bindings() {
      if (!m.containsKey('bind')) return const {};
      final map = m['bind'] as Map<String, dynamic>;
      return Map.unmodifiable(
        map.map((key, value) {
          final ref = value as Map<String, dynamic>;
          if (ref.length != 2 ||
              ref['kind'] is! String ||
              ref['id'] is! String ||
              (ref['id'] as String).isEmpty)
            throw const FormatException();
          // Explicit gate: the enum has collection, but /1 grammar must not.
          if (ref['kind'] == 'collection' && protocolVersion != streamProtocolV2)
            throw const FormatException();
          final kind = BindingKind.values.byName(ref['kind'] as String);
          return MapEntry(key, BindingRef(kind, ref['id'] as String));
        }),
      );
    }

    final UiStreamOperation result;
    switch (op) {
      case 'text':
        fields({'op', 'md'});
        result = UiStreamText(string('md'));
      case 'node':
        fields({'op', 'id', 'parent', 'component', 'props', 'bind'});
        result = UiStreamNode(
          UiNode(
            id: string('id'),
            component: string('component'),
            properties: props(),
            bindings: bindings(),
          ),
          m.containsKey('parent') ? string('parent') : null,
        );
      case 'patch':
        fields({'op', 'id', 'props'});
        if (!m.containsKey('props')) throw const FormatException();
        result = UiStreamPatch(string('id'), props());
      case 'action':
        fields({'op', 'node', 'event', 'action', 'inputs', 'operation'});
        // Inputs are explicit even for actions whose input set is empty.
        final inputs = List<String>.unmodifiable(
          (m['inputs'] as List).cast<String>(),
        );
        if (inputs.any((ref) => ref.isEmpty)) throw const FormatException();
        result = UiStreamAction(
          string('node'),
          string('event'),
          string('action'),
          inputs,
          m.containsKey('operation') ? string('operation') : null,
        );
      default:
        fields({'op'});
        result = UiStreamEnd();
    }
    return UiStreamParseResult(operation: result);
  } on Object {
    return const UiStreamParseResult(
      error: UiStreamError(UiStreamErrorCode.invalidFields, 'invalid_fields'),
    );
  }
}

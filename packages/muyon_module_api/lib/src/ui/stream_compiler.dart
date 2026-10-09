import 'dart:convert';

import 'plan.dart';
import 'stream_protocol.dart';
import 'validation.dart';

enum UiStreamNodePhase { rendered, placeholder, pending }

enum UiStreamPhase { streaming, complete, rejected, incomplete, limitExceeded }

class UiStreamNodeStatus {
  UiStreamNodeStatus(this.phase, [List<String> reasons = const []])
    : reasons = List.unmodifiable(reasons);
  final UiStreamNodePhase phase;
  final List<String> reasons;
}

class UiStreamView {
  UiStreamView({
    required this.candidatePlan,
    required this.previewPlan,
    required Map<String, UiStreamNodeStatus> statuses,
    required List<String> text,
    required List<UiStreamError> diagnostics,
    required this.phase,
    required this.receivedLines,
    required this.badLines,
    required this.diagnosticCount,
    this.batchValidation,
    this.finalPlan,
  }) : statuses = Map.unmodifiable(statuses),
       text = List.unmodifiable(text),
       diagnostics = List.unmodifiable(diagnostics);
  final UIPlan candidatePlan, previewPlan;
  final Map<String, UiStreamNodeStatus> statuses;
  final List<String> text;
  final List<UiStreamError> diagnostics;

  /// Protocol diagnostics are separate from shared schema errors; storage is
  /// bounded, while badLines and diagnosticCount retain aggregate evidence.
  List<UiStreamError> get streamErrors => List.unmodifiable(
    diagnostics.where((diagnostic) => diagnostic.protocolError),
  );
  final UiStreamPhase phase;
  final int receivedLines, badLines, diagnosticCount;

  /// Exact batch result on the unfiltered candidate, for differential tests.
  final UiValidationResult? batchValidation;

  /// Only a successfully ended stream grants this capability.
  final ValidatedUiPlan? finalPlan;
  bool get complete => phase == UiStreamPhase.complete;
}

class UiStreamCompiler {
  UiStreamCompiler({required this.session, this.limits = UiStreamLimits.v1}) {
    final bounds = [
      (limits.nodes, UiStreamLimits.v1.nodes),
      (limits.depth, UiStreamLimits.v1.depth),
      (limits.lineBytes, UiStreamLimits.v1.lineBytes),
      (limits.textBytes, UiStreamLimits.v1.textBytes),
      (limits.lines, UiStreamLimits.v1.lines),
      (limits.badLines, UiStreamLimits.v1.badLines),
      (limits.patchesPerNode, UiStreamLimits.v1.patchesPerNode),
      (limits.diagnostics, UiStreamLimits.v1.diagnostics),
    ];
    if (bounds.any((bound) => bound.$1 < 1 || bound.$1 > bound.$2)) {
      throw ArgumentError('Stream limits may only tighten v1 limits');
    }
  }
  final UiStreamSession session;
  final UiStreamLimits limits;
  final _nodes = <String, UiNode>{};
  final _parents = <String, String?>{};
  final _lastGood = <String, UiNode>{};
  final _patches = <String, int>{};
  final _text = <String>[];
  final _diagnostics = <UiStreamError>[];
  int _textBytes = 0, _receivedLines = 0, _badLines = 0, _diagnosticCount = 0;
  UiStreamPhase _phase = UiStreamPhase.streaming;
  UiValidationResult? _batch;

  UiStreamView addLine(String line) {
    _receivedLines++;
    if (_phase != UiStreamPhase.streaming) {
      if (_phase == UiStreamPhase.complete ||
          _phase == UiStreamPhase.rejected) {
        _record(UiStreamErrorCode.afterEnd, 'after_end', protocolError: false);
      }
      return current;
    }
    if (_receivedLines > limits.lines) {
      _limit(UiStreamErrorCode.lineCountLimit, 'line_count_limit');
      return current;
    }
    final parsed = parseUiStreamLine(line, limits: limits);
    if (parsed.error case final error?) {
      if (error.code == UiStreamErrorCode.lineLimit) {
        _limit(error.code, error.reason);
      } else {
        _bad(error.code, error.reason);
      }
      return current;
    }
    final op = parsed.operation!;
    final stringBytes = switch (op) {
      UiStreamText() => utf8.encode(op.markdown).length,
      UiStreamNode() => _propertyBytes(op.node.properties),
      UiStreamPatch() => _propertyBytes(op.properties),
      _ => 0,
    };
    if (_textBytes + stringBytes > limits.textBytes) {
      _limit(UiStreamErrorCode.textLimit, 'text_limit');
      return current;
    }
    _textBytes += stringBytes;
    switch (op) {
      case UiStreamText():
        _text.add(op.markdown);
      case UiStreamNode():
        if (_nodes.containsKey(op.node.id)) {
          _bad(UiStreamErrorCode.duplicateId, 'duplicate_node:${op.node.id}');
          break;
        }
        if ((_nodes.isEmpty &&
                (op.node.id != session.root || op.parent != null)) ||
            (_nodes.isNotEmpty &&
                (op.node.id == session.root || op.parent == null))) {
          _bad(UiStreamErrorCode.invalidFields, 'root_or_parent:${op.node.id}');
          break;
        }
        if (op.parent != null && !_nodes.containsKey(op.parent)) {
          _bad(UiStreamErrorCode.missingParent, 'missing_parent:${op.parent}');
          break;
        }
        if (_nodes.length >= limits.nodes) {
          _limit(UiStreamErrorCode.nodeLimit, 'node_limit');
          break;
        }
        var depth = 1;
        var parent = op.parent;
        // Parents were accepted before children, so cycles cannot be introduced.
        while (parent != null) {
          depth++;
          parent = _parents[parent];
        }
        if (depth > limits.depth) {
          _limit(UiStreamErrorCode.depthLimit, 'depth_limit');
          break;
        }
        _nodes[op.node.id] = op.node;
        _parents[op.node.id] = op.parent;
        if (op.parent != null) {
          final p = _nodes[op.parent]!;
          _nodes[p.id] = p.copyWith(children: [...p.children, op.node.id]);
          _check(p.id, retainGood: true);
        }
        _check(op.node.id, retainGood: false);
      case UiStreamPatch():
        final node = _nodes[op.id];
        if (node == null) {
          _bad(UiStreamErrorCode.missingTarget, 'missing_patch:${op.id}');
          break;
        }
        if ((_patches[op.id] ?? 0) >= limits.patchesPerNode) {
          _limit(UiStreamErrorCode.patchLimit, 'patch_limit:${op.id}');
          break;
        }
        _patches[op.id] = (_patches[op.id] ?? 0) + 1;
        final properties = {...node.properties};
        for (final entry in op.properties.entries) {
          if (entry.value == null) {
            properties.remove(entry.key);
          } else {
            properties[entry.key] = entry.value;
          }
        }
        _nodes[node.id] = node.copyWith(properties: properties);
        _check(node.id, retainGood: true);
      case UiStreamAction():
        final node = _nodes[op.nodeId];
        if (node == null) {
          _bad(UiStreamErrorCode.missingTarget, 'missing_action:${op.nodeId}');
          break;
        }
        if (node.events.containsKey(op.event)) {
          _bad(
            UiStreamErrorCode.duplicateId,
            'duplicate_event:${op.nodeId}:${op.event}',
          );
          break;
        }
        final business =
            session.catalog.actions[op.actionRef]?.route ==
            UiActionRoute.business;
        if (business && op.operation == null) {
          _bad(UiStreamErrorCode.invalidFields, 'missing_operation');
          break;
        }
        final binding = ActionBinding(
          actionRef: op.actionRef,
          inputRefs: op.inputs,
          operationKeyRef: op.operation,
          expectedDraftRevision: business
              ? session.snapshot.actionContext?.draftRevision
              : null,
        );
        _nodes[node.id] = node.copyWith(
          events: {...node.events, op.event: binding},
        );
        _check(node.id, retainGood: true);
      case UiStreamEnd():
        _batch = validateUiPlan(
          _candidate,
          session.snapshot,
          session.intent,
          session.catalog,
        );
        if (_badLines > 0)
          _record(UiStreamErrorCode.malformedStream, 'malformed_stream');
        _phase = _badLines == 0 && _batch!.isValid
            ? UiStreamPhase.complete
            : UiStreamPhase.rejected;
    }
    return current;
  }

  int _propertyBytes(Map<String, Object?> properties) {
    final pending = <Object?>[...properties.values];
    var bytes = 0;
    while (pending.isNotEmpty) {
      final value = pending.removeLast();
      if (value is String) {
        bytes += utf8.encode(value).length;
      } else if (value is List) {
        pending.addAll(value);
      } else if (value is Map) {
        pending.addAll(value.values);
      }
    }
    return bytes;
  }

  List<String> _nodeErrors(UiNode node) =>
      validateUiNode(node, session.snapshot, session.intent, session.catalog);
  void _check(String id, {required bool retainGood}) {
    final node = _nodes[id]!;
    final errors = _nodeErrors(node);
    if (errors.isEmpty) {
      _lastGood[id] = node;
    } else {
      final previous = _lastGood[id];
      final fallback = previous?.copyWith(
        children: node.children,
        events: node.events,
      );
      if (!retainGood || fallback == null || _nodeErrors(fallback).isNotEmpty) {
        _lastGood.remove(id);
      } else {
        _lastGood[id] = fallback;
      }
      for (final reason in errors) {
        _record(UiStreamErrorCode.invalidFields, reason, protocolError: false);
      }
    }
  }

  UiStreamView interrupt() {
    if (_phase == UiStreamPhase.streaming) _phase = UiStreamPhase.incomplete;
    return current;
  }

  void _record(
    UiStreamErrorCode code,
    String reason, {
    bool protocolError = true,
  }) {
    _diagnosticCount++;
    if (_diagnostics.length < limits.diagnostics)
      _diagnostics.add(
        UiStreamError(code, reason, protocolError: protocolError),
      );
  }

  void _bad(UiStreamErrorCode code, String reason) {
    _badLines++;
    _record(code, reason);
    if (_badLines > limits.badLines)
      _limit(UiStreamErrorCode.badLineLimit, 'bad_line_limit');
  }

  void _limit(UiStreamErrorCode code, String reason) {
    _record(code, reason);
    _phase = UiStreamPhase.limitExceeded;
  }

  UIPlan get _candidate => session.plan(_nodes.values.toList());
  UiStreamView get current {
    final statuses = <String, UiStreamNodeStatus>{};
    final visible = <String>{};
    for (final node in _nodes.values) {
      final errors = _nodeErrors(node);
      if (node.id != session.root && !visible.contains(_parents[node.id])) {
        statuses[node.id] = UiStreamNodeStatus(UiStreamNodePhase.pending, [
          'blocked_by_parent',
        ]);
      } else if (!_lastGood.containsKey(node.id)) {
        statuses[node.id] = UiStreamNodeStatus(
          UiStreamNodePhase.placeholder,
          errors,
        );
      } else {
        visible.add(node.id);
        statuses[node.id] = UiStreamNodeStatus(
          UiStreamNodePhase.rendered,
          errors,
        );
      }
    }
    final complete = _phase == UiStreamPhase.complete;
    // A failed end invalidates the entire UI; text survives for host fallback.
    final preview = _phase == UiStreamPhase.rejected
        ? <UiNode>[]
        : [
            for (final node in _nodes.values)
              if (visible.contains(node.id))
                _lastGood[node.id]!.copyWith(
                  children: node.children.where(visible.contains).toList(),
                  events: complete ? node.events : {},
                ),
          ];
    return UiStreamView(
      candidatePlan: _candidate,
      previewPlan: session.plan(preview),
      statuses: statuses,
      text: _text,
      diagnostics: _diagnostics,
      phase: _phase,
      receivedLines: _receivedLines,
      badLines: _badLines,
      diagnosticCount: _diagnosticCount,
      batchValidation: _batch,
      finalPlan: complete ? _batch?.validatedPlan : null,
    );
  }
}

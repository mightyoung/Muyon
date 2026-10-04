import 'dart:io';

import 'package:path/path.dart' as p;

/// Ownership of first-party research roots within this isolate. Hosted roots
/// stay registered after view disposal; closing a view must never unlock LAN.
/// This is a routing boundary, not a sandbox against arbitrary local code.
abstract final class ResearchRootOwnership {
  static final Set<String> _hosted = {};
  static final Set<String> _standalone = {};
  static final Set<ResearchTransferLease> _transfers = {};

  static String _canonical(String path) {
    // Collapsing symlink/.. lexically changes the path the OS will access.
    // Reject it before normalization, including for nonexistent destinations.
    if (p.split(path).contains('..')) {
      throw StateError('Parent traversal is not allowed for research storage');
    }
    var current = p.normalize(p.absolute(path));
    final missing = <String>[];
    while (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(current);
      if (parent == current) throw StateError('Unresolvable research root');
      missing.insert(0, p.basename(current));
      current = parent;
    }
    final resolved = File(current).resolveSymbolicLinksSync();
    return p.normalize(p.joinAll([resolved, ...missing]));
  }

  static bool _inside(String root, String path) =>
      p.equals(root, path) || p.isWithin(root, path);
  static bool _overlap(String a, String b) => _inside(a, b) || _inside(b, a);

  /// The returned path must also be used for subsequent filesystem effects.
  static String requireNotHosted(String path) {
    final canonical = _canonical(path);
    if (_hosted.any((root) => _overlap(root, canonical))) {
      throw StateError(
        'Hosted research requires host storage and transfer services',
      );
    }
    return canonical;
  }

  /// Synchronous with transfer acquisition, so there is no successful hosted
  /// attachment while an overlapping standalone transfer remains in flight.
  static String registerHosted(String root) {
    final canonical = _canonical(root);
    if (_transfers.any(
      (lease) => lease._paths.any((path) => _overlap(path, canonical)),
    )) {
      throw StateError(
        'Stop or finish the standalone LAN transfer before activating hosted research',
      );
    }
    _hosted.add(canonical);
    return canonical;
  }

  static void registerStandalone(String root) =>
      _standalone.add(requireNotHosted(root));

  static String requireStandalone(String path) {
    final canonical = requireNotHosted(path);
    if (!_standalone.any((root) => _inside(root, canonical))) {
      throw StateError(
        'Plaintext LAN transfer requires a registered standalone store',
      );
    }
    return canonical;
  }

  static ResearchTransferLease acquireTransfer(
    String destination, {
    String? source,
  }) {
    final canonical = requireStandalone(destination);
    final selected = source == null ? null : requireNotHosted(source);
    final paths = <String>{
      canonical,
      ?selected,
      for (final root in _standalone)
        if (_inside(root, canonical) ||
            (selected != null && _inside(root, selected)))
          root,
    };
    final lease = ResearchTransferLease._(paths);
    _transfers.add(lease);
    return lease;
  }
}

/// Held from before the first async effect until all transfer cleanup finishes.
class ResearchTransferLease {
  ResearchTransferLease._(this._paths);
  final Set<String> _paths;
  void release() => ResearchRootOwnership._transfers.remove(this);
}

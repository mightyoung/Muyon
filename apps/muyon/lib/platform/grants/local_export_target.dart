import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// Which half of a local export an intent or approval is for. Generation
/// writes into the research exports area; saving copies the same bytes to the
/// place the person picked. One approval never covers both.
enum LocalExportPhase { generate, save }

enum LocalExportOverwrite { createNew, replace }

const _destinationPrefix = 'local-export:';

/// The fixed request destination of a local export stage. It names no place:
/// the person-chosen target lives only in a [LocalExportTargetCapability].
String localExportDestination(LocalExportPhase phase) =>
    '$_destinationPrefix${phase.name}';

LocalExportPhase? parseLocalExportDestination(String? destination) {
  if (destination == null || !destination.startsWith(_destinationPrefix)) {
    return null;
  }
  final name = destination.substring(_destinationPrefix.length);
  for (final phase in LocalExportPhase.values) {
    if (phase.name == name) return phase;
  }
  return null;
}

/// The one place the person picked for one export. Only a
/// [LocalExportTargetIssuer] makes these; there is no constructor, no JSON
/// decoder and the class cannot be extended, so knowing an identity string or
/// building something of the same shape grants nothing.
final class LocalExportTargetCapability {
  LocalExportTargetCapability._(
    this.identity,
    this.displayNameDigest,
    this._issuer,
  );

  /// Unguessable, for audit and intent binding only.
  final String identity;

  /// Digest of the display name; the name itself is not kept here.
  final String displayNameDigest;
  final LocalExportTargetIssuer _issuer;
  bool get isLive => _issuer._live.contains(this);
}

/// Host-owned. A capability is valid only for the issuer that made it.
final class LocalExportTargetIssuer {
  final _live = <LocalExportTargetCapability>{};

  LocalExportTargetCapability issue(String displayName) {
    final capability = LocalExportTargetCapability._(
      const Uuid().v4(),
      sha256.convert(utf8.encode(displayName)).toString(),
      this,
    );
    _live.add(capability);
    return capability;
  }

  void revoke(LocalExportTargetCapability capability) =>
      _live.remove(capability);

  bool owns(LocalExportTargetCapability capability) =>
      identical(capability._issuer, this) && _live.contains(capability);
}

/// Capability coverage manifest types (ADR-0004 §8.2). Data only: the checks
/// that read it belong to REG-5.
library;

enum OpKind { query, write, external, internal }

enum NotExposedKind {
  humanOnly,
  secretHandling,
  dangerousIrreversible,
  privilegedSystem,
  notBusiness,
  deferred,
}

class Surface {
  const Surface(this.library, this.name);

  /// Dart library URI, for example `package:supplier_core/src/inquiries.dart`.
  final String library;

  /// Class or extension name.
  final String name;
}

class NotExposed {
  const NotExposed(this.kind, this.reason, {this.taskId});
  final NotExposedKind kind;
  final String reason;

  /// Only for [NotExposedKind.deferred].
  final String? taskId;
}

class Operation {
  Operation({
    required this.id,
    required this.kind,
    Set<String> members = const {},
    List<String> tools = const [],
    this.notExposed,
  }) : members = Set.unmodifiable(members),
       tools = List.unmodifiable(tools) {
    if (tools.isNotEmpty && notExposed != null) {
      throw ArgumentError('Operation $id has tools and a not-exposed reason');
    }
  }
  final String id;
  final OpKind kind;
  final Set<String> members;
  final List<String> tools;
  final NotExposed? notExposed;
}

class CapabilityCoverage {
  CapabilityCoverage({
    this.version = 1,
    List<Surface> surfaces = const [],
    List<Operation> operations = const [],
  }) : surfaces = List.unmodifiable(surfaces),
       operations = List.unmodifiable(operations);
  static final empty = CapabilityCoverage();
  final int version;
  final List<Surface> surfaces;
  final List<Operation> operations;
}

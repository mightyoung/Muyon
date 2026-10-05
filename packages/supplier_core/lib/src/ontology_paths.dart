import 'ontology.dart';

/// Direction of one step when walking a [LinkType].
enum PathDirection {
  /// Follow the link's own field: read `link.field` on a `link.from` record
  /// and `get` the `link.to` record.
  out('out'),

  /// Follow the link backwards: `related(link: link.name)` from a `link.to`
  /// record lists the `link.from` records.
  incoming('in');

  const PathDirection(this.label);

  /// JSON name, `out` or `in` (`in` is a Dart keyword).
  final String label;
}

/// One step of an object-type association path.
class OntologyPathStep {
  const OntologyPathStep({
    required this.link,
    required this.direction,
    required this.from,
    required this.to,
    required this.many,
    required this.via,
  });

  /// Link name, e.g. `quotation.supplier_id`.
  final String link;
  final PathDirection direction;

  /// Object type this step starts from.
  final String from;

  /// Object type this step reaches.
  final String to;
  final bool many;

  /// `get` for [PathDirection.out], `related` for [PathDirection.in].
  final String via;

  Map<String, Object?> toJson() => {
    'link': link,
    'direction': direction.label,
    'from': from,
    'to': to,
    'many': many,
    'via': via,
  };
}

/// A simple association path between two object types.
class OntologyPath {
  const OntologyPath(this.steps);
  final List<OntologyPathStep> steps;
  int get hops => steps.length;
  List<String> get linkNames => [for (final step in steps) step.link];
  Map<String, Object?> toJson() => {
    'hops': hops,
    'steps': [for (final step in steps) step.toJson()],
  };
}

/// Shortest simple association paths from [from] to [to] over the ontology.
///
/// Every [LinkType] can be walked in both directions, so a step is either
/// `out` (read the link's field and `get` the target) or `in` (`related` by
/// link name). Paths are simple: an object type never repeats.
///
/// Results are deterministic: shortest paths first, ties broken by the
/// lexicographic order of each step's link name.
///
/// [from] == [to] and unknown type names return an empty list.
List<OntologyPath> ontologyPaths(
  String from,
  String to, {
  int maxHops = 3,
  int limit = 2,
}) {
  if (maxHops < 1 || limit < 1 || from == to) return const [];
  if (!ontology.containsKey(from) || !ontology.containsKey(to)) {
    return const [];
  }
  final edges = <String, List<OntologyPathStep>>{};
  for (final link in links) {
    (edges[link.from] ??= []).add(
      OntologyPathStep(
        link: link.name,
        direction: PathDirection.out,
        from: link.from,
        to: link.to,
        many: link.many,
        via: 'get',
      ),
    );
    (edges[link.to] ??= []).add(
      OntologyPathStep(
        link: link.name,
        direction: PathDirection.incoming,
        from: link.to,
        to: link.from,
        many: link.many,
        via: 'related',
      ),
    );
  }
  for (final list in edges.values) {
    list.sort((a, b) {
      final byLink = a.link.compareTo(b.link);
      return byLink != 0
          ? byLink
          : a.direction.index.compareTo(b.direction.index);
    });
  }
  final found = <OntologyPath>[];
  void walk(String node, List<String> visited, List<OntologyPathStep> steps) {
    if (steps.length == maxHops) return;
    for (final edge in edges[node] ?? const <OntologyPathStep>[]) {
      if (visited.contains(edge.to)) continue;
      final next = [...steps, edge];
      if (edge.to == to) {
        found.add(OntologyPath(next));
        continue;
      }
      walk(edge.to, [...visited, edge.to], next);
    }
  }

  walk(from, [from], const []);
  found.sort((a, b) {
    final byHops = a.hops.compareTo(b.hops);
    if (byHops != 0) return byHops;
    final aNames = a.linkNames;
    final bNames = b.linkNames;
    for (var i = 0; i < aNames.length; i++) {
      final byName = aNames[i].compareTo(bNames[i]);
      if (byName != 0) return byName;
    }
    return 0;
  });
  return found.length > limit ? found.sublist(0, limit) : found;
}

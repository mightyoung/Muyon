/// Module-independent ontology declaration (ADR-0004 §4.3). The shape mirrors
/// `supplier_core`'s ontology so an adapter can map it; this library does not
/// depend on any business package.
library;

/// Sensitivity of one field. [unreviewed] is the default and means "nobody has
/// looked yet"; the contract suite requires every field to be reviewed.
/// [personal], [commercial] and [credential] are also the category vocabulary
/// for ADR-0002 / ADR-0005 `dataCategories`.
enum Sensitivity { unreviewed, none, personal, commercial, credential }

enum FieldKind {
  text,
  textList,
  decimal,
  integer,
  boolean,
  date,
  instant,
  enumeration,
  ref,
  refList,
  object,
}

/// Named `OntologyFieldSpec` so it does not collide with `supplier_core`.
class OntologyFieldSpec {
  const OntologyFieldSpec({
    required this.name,
    required this.label,
    required this.description,
    required this.kind,
    this.required = false,
    this.values,
    this.target,
    this.sensitivity = Sensitivity.unreviewed,
  });
  final String name, label, description;
  final FieldKind kind;
  final bool required;

  /// Enum values and what each means.
  final Map<String, String>? values;

  /// Referenced object type, for [FieldKind.ref] and [FieldKind.refList].
  final String? target;
  final Sensitivity sensitivity;
}

enum ObjectPageKind { unbound, bound, none }

/// Whether and how an object type opens a business page.
class ObjectPageSupport {
  /// A page that needs no workspace binding.
  const ObjectPageSupport.unbound()
    : kind = ObjectPageKind.unbound,
      reason = null;

  /// A page opened through a workspace binding.
  const ObjectPageSupport.bound() : kind = ObjectPageKind.bound, reason = null;

  /// No page; the reason is required.
  const ObjectPageSupport.none(String this.reason) : kind = ObjectPageKind.none;
  final ObjectPageKind kind;
  final String? reason;
  bool get hasPage => kind != ObjectPageKind.none;
}

class ObjectTypeSpec {
  ObjectTypeSpec({
    required this.name,
    required this.label,
    required this.description,
    required this.iconKey,
    required this.titleField,
    required List<OntologyFieldSpec> fields,
    this.inGlobalScope = false,
    this.versioned = false,
    this.page = const ObjectPageSupport.unbound(),
  }) : fields = List.unmodifiable(fields);
  final String name, label, description, iconKey, titleField;
  final List<OntologyFieldSpec> fields;

  /// Takes part in global / workspace scope enumeration (ADR-0004 §5.2).
  final bool inGlobalScope;

  /// `resolve` returns a `revisionRef` for this type.
  final bool versioned;
  final ObjectPageSupport page;
}

class RelationSpec {
  const RelationSpec({
    required this.name,
    required this.from,
    required this.field,
    required this.to,
    this.many = false,
    this.queryTool,
  });
  final String name, from, field, to;
  final bool many;

  /// Id of the read tool that answers this relation.
  final String? queryTool;
}

class ActionSpec {
  const ActionSpec({
    required this.name,
    required this.label,
    required this.description,
    this.tool,
    this.operationId,
    this.humanOnlyReason,
  });
  final String name, label, description;
  final String? tool;
  final String? operationId;
  final String? humanOnlyReason;
}

/// One step of a flow, bound to a tool or an action (exactly one).
class FlowStep {
  const FlowStep({this.tool, this.action})
    : assert((tool == null) != (action == null));
  final String? tool;
  final String? action;
}

class FlowSpec {
  FlowSpec({
    required this.name,
    required this.label,
    required List<FlowStep> steps,
  }) : steps = List.unmodifiable(steps);
  final String name, label;
  final List<FlowStep> steps;
}

class ExampleSpec {
  ExampleSpec({required this.question, List<String> expectTools = const []})
    : expectTools = List.unmodifiable(expectTools);
  final String question;
  final List<String> expectTools;
}

class RuleSpec {
  const RuleSpec(this.name, this.text);
  final String name, text;
}

class ModuleOntology {
  ModuleOntology({
    List<ObjectTypeSpec> objectTypes = const [],
    List<RelationSpec> relations = const [],
    List<ActionSpec> actions = const [],
    List<FlowSpec> flows = const [],
    List<ExampleSpec> examples = const [],
    List<RuleSpec> rules = const [],
  }) : objectTypes = List.unmodifiable(objectTypes),
       relations = List.unmodifiable(relations),
       actions = List.unmodifiable(actions),
       flows = List.unmodifiable(flows),
       examples = List.unmodifiable(examples),
       rules = List.unmodifiable(rules);

  /// For modules with no business objects (the data center shows "n/a").
  factory ModuleOntology.empty() => ModuleOntology();

  final List<ObjectTypeSpec> objectTypes;
  final List<RelationSpec> relations;
  final List<ActionSpec> actions;
  final List<FlowSpec> flows;
  final List<ExampleSpec> examples;
  final List<RuleSpec> rules;

  ObjectTypeSpec? type(String name) =>
      objectTypes.where((t) => t.name == name).firstOrNull;

  /// Fields not yet reviewed for sensitivity, as `type.field`.
  List<String> get unreviewedFields => [
    for (final type in objectTypes)
      for (final field in type.fields)
        if (field.sensitivity == Sensitivity.unreviewed)
          '${type.name}.${field.name}',
  ];
}

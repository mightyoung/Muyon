# Native read declaration subsets

These JSON files are embedded by the Rust `mappings` module. They install no
handler, do not read business storage, and provide no authority/grant/receipt.
They are a private first-slice contract, not a complete business migration or M03.
Runtime and build do not execute or depend on Dart. The source paths below record
where the metadata was read, not build-time inputs.

All source citations use fixed SHA
`31b9b6fc1f7f8b27952533ca141e901676ba90e8`.

| Mapping | Source at that SHA | Exact retained meaning |
|---|---|---|
| research project/document DATA | `packages/research_module/lib/src/module_declarations.dart:31` and `:64` | project title/question/nextStep; document relativePath/projectId; source fields optional and classified none |
| research document→project RELATION | `packages/research_module/lib/src/module_declarations.dart:296` | document_project, projectId, one project target |
| research read operation | `packages/research_module/lib/src/module_tools.dart:76` | read_object native input type/id, narrowed enum project/document |
| inquiry supplier/product DATA | `packages/supplier_core/lib/src/ontology.dart:133` and `:164` | native field names, supplier name required, product name/unit required, merged_into reference to the same type |
| inquiry relation derivation | `packages/supplier_core/lib/src/ontology.dart:80` and `:673` | domain links derive from declared references; native contract replaces the source link name's dot with underscore to satisfy its namespace grammar, preserving from/field/to/many |
| inquiry sensitivity | `apps/muyon/lib/app/adapters/inquiry_module.dart:274` and `:330` | actual host declaration maps all selected supplier/product fields to none; this label alone never grants model export or clears source facts |
| inquiry read operation | `apps/muyon/lib/platform/business_tools.dart:161` | inquiry.object native type/id, narrowed enum supplier/product |
| supplier rating values | `packages/supplier_core/lib/src/entities.dart:52` | preferred/caution/disabled enum |

Source bytes (SHA-256):

- module_declarations.dart: `1fcc4e4cf7f874ee5fe9250d4ae128db8345449b447341e8edcb1dbf09fcf4af`
- module_tools.dart: `c70f5b5a495c991cd9775c6a89d2f2ca59996ee12706debb907bb45b91ce989b`
- ontology.dart: `c67e9ec5133eeee6f27fe4b71bc85999f91ffb0a236490a5177e5d98855243a6`
- entities.dart: `aa9980a6cb84150d773e012c7a79e13ffda28efb1e170d78b86db01c9a052a46`
- inquiry_module.dart: `af9445a4852b5d267462ecf48464293f092e4a9c76058c725a5c41564232e260`
- business_tools.dart: `5d714fd4016fd80964caa793045b737a49ecc2803eddde16537644cabd854fb3`

Explicit exclusions and normalization:

- Only project/document and supplier/product are admitted; other source DATA and
  operations are absent, not silently available through the native input enum.
- Product attributes and unit_conversions are arbitrary objects unsupported by
  this bounded schema subset. source_attachment_ids targets unadmitted DATA.
  All three fields are absent from the closed DATA schema. A value containing
  them cannot pass that schema. No unconstrained object schema is substituted.
- Missing optional fields are omitted; native values do not inherit source-store
  nullable encodings. Reference identifiers are resolved by the native host into
  closed typed references, not treated as grants or dereferenced by Catalog.
- Source string lengths/normalization/business validation are not represented as
  new JSON Schema keywords. The native business handler retains responsibility
  for domain validation. First-slice research/inquiry model projections contain
  only typed references, not arbitrary DATA row values.
- `schema_version:1` names this native contract version. It is not a source
  database version or schema migration. Reference `revision` independently names
  the current native-host object snapshot. Research source `versioned:false`
  does not become a claim of a historical immutable revision. Synthetic host
  fixtures issue their own current read revision and must recheck it.
- Field classifications are copied metadata; missing future classifications are
  unreviewed. Actual selected values, source facts and model purpose still need
  host review, even for a declared none field.

Research/inquiry projection shape is a closed `objects` object whose optional
keys are admitted DATA names, each holding at most 128 typed references. Each
reference has exactly module_id/type/key/revision strings and schema_version
positive integer, must match its exact DATA annotation, and occur in current host
scope. Equipment retains its existing native equipment_key/include_loans input
and equipment/label/loans projection.

The seeded equipment variant changes namespace, operation, opaque binding,
relation/view identities and DATA names equipment→asset, loan→lease. It also
updates every schema annotation/reference and the equipment projection property
(asset). It preserves native equipment_key/include_loans arguments. Fixture
construction knows these names; Agent/provider/host authorization dispatch does
not. This is a deterministic metamorphic test, not executable plugin loading.

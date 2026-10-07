import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:prototype_module/prototype_module.dart';
import 'package:research_module/research_module.dart';

/// The one place a module is listed (ADR-0004 §6.3): one line per module.
/// Adding a module is a line here, a dependency in `apps/muyon/pubspec.yaml`
/// and a `workspace:` entry in the root `pubspec.yaml`.
List<BusinessModule> moduleCatalog() => [ResearchModule(), PrototypeModule()];

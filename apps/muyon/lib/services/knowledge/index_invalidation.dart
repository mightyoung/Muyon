import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:supplier_core/supplier_core.dart';

import '../../app/inquiry_plugin.dart';

/// Asks the owning module whether [ref] still exists. Unknown modules are absent.
Future<bool> confirmIndexedSource(
  ObjectRef ref, {
  ResearchRuntime? Function()? research,
  InquiryPlugin? Function()? inquiry,
}) async {
  if (ref.moduleId == 'knowledge') return true;
  if (ref.moduleId == 'research') {
    final store = research?.call()?.store;
    final project = ref.nativeProjectId;
    if (store == null || project == null) return false;
    return switch (ref.objectType) {
      'document' =>
        store.documents(project).any((doc) => doc.id == ref.objectId),
      'entry' =>
        store.entries(project).any((entry) => entry.id == ref.objectId),
      'project' => store.projects().any((item) => item.id == ref.objectId),
      _ => false,
    };
  }
  if (ref.moduleId == 'inquiry') {
    final store = inquiry?.call()?.runtime.state.store;
    if (store == null || !entityTypes.contains(ref.objectType)) return false;
    return store.db.select(
      'SELECT 1 FROM ${ref.objectType} WHERE id=? AND deleted=0',
      [ref.objectId],
    ).isNotEmpty;
  }
  return false;
}

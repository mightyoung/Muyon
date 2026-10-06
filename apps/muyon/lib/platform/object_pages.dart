import 'package:flutter/widgets.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import '../app/bootstrap.dart';

/// An object page opened through its module session, with the title resolved
/// for the surrounding app bar. The caller must [dispose] it after the route
/// closes.
class ModuleObjectPage {
  ModuleObjectPage(this.title, this.page, this.session);
  final String title;
  final Widget page;
  final ModuleSession session;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await session.dispose();
  }
}

/// Opens [ref] through its module's [ModuleSession.objectPage] when a matching
/// workspace binding exists: the binding's native project must equal the
/// reference's, the module runtime must be available, and the session must
/// resolve the reference and return a page.
///
/// Returns null on any missing piece (no binding, unavailable runtime, deleted
/// object, stale revision or digest), so the caller keeps its JSON fallback.
/// This helper never creates a workspace binding, and it hands the session to
/// the caller only on success; every other path disposes it.
Future<ModuleObjectPage?> openModuleObjectPage(
  BuildContext context,
  MuyonHost host,
  ObjectRef ref,
) async {
  final projectId = ref.nativeProjectId;
  if (projectId == null) return null;
  final workspaceId = host.workspaces.ownerWorkspace(ref.moduleId, projectId);
  if (workspaceId == null) return null;
  final binding = host.workspaces.binding(workspaceId, ref.moduleId);
  if (binding == null || binding.nativeProjectId != projectId) {
    return null;
  }
  final runtime = await _runtimeFor(host, ref.moduleId);
  if (runtime == null) return null;
  final session = await runtime.openSession(binding);
  var transferred = false;
  try {
    final view = await session.resolve(ref);
    if (!context.mounted) return null;
    final page = view == null ? null : session.objectPage(context, ref);
    if (view == null || page == null) return null;
    transferred = true;
    return ModuleObjectPage(view.title, page, session);
  } catch (_) {
    return null;
  } finally {
    // The session must not outlive this call unless the caller took it.
    if (!transferred) await session.dispose();
  }
}

Future<ModuleRuntime?> _runtimeFor(MuyonHost host, String moduleId) async {
  switch (moduleId) {
    case 'research':
      if (host.research == null) await host.activateResearch();
      return host.research;
    case 'prototype':
      // Prototype objects have no workspace binding yet (B's 2.4 work). The
      // lookup stays ready, but this helper never creates a binding itself.
      return host.prototype;
    default:
      return null;
  }
}

import 'package:flutter/widgets.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import '../app/bootstrap.dart';

/// An object page opened through its module session, with the title resolved
/// for the surrounding app bar. The caller must [dispose] it after the route
/// closes.
class ModuleObjectPage {
  ModuleObjectPage(this.title, this.page, this.session);

  /// A page a module opened itself (`ObjectPages`), with no workspace binding
  /// and so no session to resolve against.
  ModuleObjectPage.leased(ObjectPageLease lease)
    : title = lease.title,
      page = lease.page,
      session = _LeasedSession(lease.dispose);
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

/// Stands in for a session on a leased page: nothing to resolve, and
/// disposing it releases the lease.
class _LeasedSession implements ModuleSession {
  _LeasedSession(this._release);
  final Future<void> Function() _release;
  @override
  Future<ObjectView?> resolve(ObjectRef ref) =>
      Future.error(UnsupportedError('A leased page has no session'));
  @override
  Widget? objectPage(BuildContext context, ObjectRef ref) => null;
  @override
  Future<void> flush() async {}
  @override
  Future<void> dispose() => _release();
}

/// Opens [ref] through its module, in this order:
///
/// 1. a v2 module that declares `ModuleFeature.objectPages` opens it itself,
///    with no workspace binding (ADR-0004 §4.5);
/// 2. otherwise through [ModuleSession.objectPage] when a matching workspace
///    binding exists: the binding's native project must equal the reference's,
///    the module runtime must be available, and the session must resolve the
///    reference and return a page.
///
/// Returns null on any missing piece (no binding, unavailable runtime, deleted
/// object, stale revision or digest, a module with no page), so the caller
/// keeps its JSON fallback. This helper never creates a workspace binding, and
/// it hands the session to the caller only on success; every other path
/// disposes it.
Future<ModuleObjectPage?> openModuleObjectPage(
  BuildContext context,
  MuyonHost host,
  ObjectRef ref,
) async {
  final declared = host.registry.modules
      .where(
        (module) =>
            module.manifest.id == ref.moduleId &&
            module is BusinessModuleV2 &&
            module.manifest.features.contains(ModuleFeature.objectPages),
      )
      .isNotEmpty;
  if (declared) {
    final runtime = await host.modules.runtimeFor(ref.moduleId);
    if (!context.mounted) return null;
    if (runtime is ObjectPages) {
      try {
        final lease = await (runtime as ObjectPages).open(context, ref);
        return lease == null ? null : ModuleObjectPage.leased(lease);
      } catch (_) {
        return null;
      }
    }
  }
  final projectId = ref.nativeProjectId;
  if (projectId == null) return null;
  final workspaceId = host.workspaces.ownerWorkspace(ref.moduleId, projectId);
  if (workspaceId == null) return null;
  final binding = host.workspaces.binding(workspaceId, ref.moduleId);
  if (binding == null || binding.nativeProjectId != projectId) {
    return null;
  }
  final runtime = await host.modules.runtimeFor(ref.moduleId);
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

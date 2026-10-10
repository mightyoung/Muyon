import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/adapters/inquiry_module.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'conversation_workspace_fixture.dart';
import 'fake_v2_module.dart';
import 'ui_navigation_fixture.dart';

/// A real Inquiry adapter. Only the fixture marker and actual-lease barriers
/// differ; schema, SQLite owner, object resolution and page remain production.
class InquiryNavigationModule extends InquiryBusinessModule {
  InquiryNavigationModule(super.host, {required this.marker,
    required this.pageTitle});
  final String marker, pageTitle;
  InquiryNavigationRuntime? runtime;
  @override
  void registerTools(ToolRegistrar registrar) {} // Read-only test fixture.
  @override
  Future<ModuleRuntime> activate(ModuleResources resources) async {
    final actual = await super.activate(resources) as InquiryModuleRuntime;
    return runtime = InquiryNavigationRuntime(resources, actual, marker, pageTitle);
  }
}

class InquiryNavigationRuntime extends FakeRuntime implements ObjectPages, ScopeResolvable {
  InquiryNavigationRuntime(super.resources, this.actual, this.marker, this.pageTitle);
  final InquiryModuleRuntime actual;
  final String marker, pageTitle;
  int released = 0, opened = 0;
  Completer<void>? openBarrier, openEntered, releaseBarrier;
  @override
  Future<ModuleSession> openSession(WorkspaceBinding binding) => actual.openSession(binding);
  @override
  Future<ModuleSession> openScopeSession() => actual.openScopeSession();
  @override
  Future<ObjectPageLease?> open(BuildContext context, ObjectRef ref) async {
    final lease = await actual.open(context, ref);
    if (lease == null) return null;
    opened++;
    if (openEntered != null && !openEntered!.isCompleted) openEntered!.complete();
    await openBarrier?.future;
    return ObjectPageLease(title: pageTitle,
      page: Column(children: [Text(marker), Expanded(child: lease.page)]),
      dispose: () async {
        await releaseBarrier?.future;
        await lease.dispose();
        released++;
      });
  }
}

Future<ObjectRef> pinInquiryReference(WidgetTester tester, NavigationFixture f, ObjectRef ref) async {
  final runtime = (await workspaceOperation(tester, () => f.host.modules.runtimeFor('inquiry')))!;
  final session = await workspaceOperation(tester, () => (runtime as ScopeResolvable).openScopeSession());
  try {
    final view = await workspaceOperation(tester, () => session.resolve(ref));
    expect(view, isNotNull);
    expect(view!.ref.revisionRef, isNotNull);
    expect(view.ref.contentDigest, isNotNull);
    return view.ref;
  } finally {
    await workspaceOperation(tester, session.dispose);
  }
}

Future<ObjectRef> seedPinnedInquiry(WidgetTester tester, NavigationFixture f) async =>
    pinInquiryReference(tester, f, await f.seedObject(tester, 'inquiry'));

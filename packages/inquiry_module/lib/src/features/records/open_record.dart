import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../platform/files.dart';
import '../catalog/catalog_page.dart';
import '../catalog/detail_panel.dart';
import '../catalog/contacts.dart';
import '../inquiries/inquiry_page.dart';
import '../projects/project_detail.dart';
import '../quotes/quote_form.dart';

/// Opens any record where it is edited or viewed.
Future<void> openRecord(
  BuildContext context,
  AppState state,
  String type,
  String id,
) async {
  final record = state.store.get(type, id);
  if (record == null || record.deleted) {
    return toast(context, '这条记录已不存在，可能已被删除');
  }
  switch (type) {
    case 'supplier' || 'product':
      await showCatalogForm(context, state, type, id: id);
    case 'contact':
      await showContactForm(
        context,
        state,
        record.data['supplier_id']! as String,
        id: id,
      );
    case 'quotation':
      await showQuoteForm(context, state, id: id);
    case 'inquiry':
      await openInquiry(context, state, id);
    case 'project' || 'project_item':
      final projectId = type == 'project'
          ? id
          : record.data['project_id']! as String;
      final project = state.store.get('project', projectId)?.data;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              backgroundColor: Tokens.canvas,
              title: Text(project?['name'] as String? ?? '项目'),
            ),
            // Same breakpoint as the projects page: a phone gets the compact
            // layout, the desktop table overflows to zero width there.
            body: ProjectDetail(
              state: state,
              projectId: projectId,
              compact: MediaQuery.sizeOf(context).width < 1000,
            ),
          ),
        ),
      );
  }
}

/// Existing object bodies for a host-owned route. Unsupported form-only records
/// keep the host's read-only fallback; this does not create a second editor.
Widget? inquiryObjectPage(
  BuildContext context,
  AppState state,
  String type,
  String id,
) {
  final record = state.store.get(type, id);
  if (record == null || record.deleted) return null;
  return switch (type) {
    'project' || 'project_item' => LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // The existing fixed header/toolbar and empty ledger need reading
        // room; a short host route scrolls instead of overflowing its body.
        child: SizedBox(
          height: constraints.maxHeight < 720 ? 720 : constraints.maxHeight,
          child: ProjectDetail(
            state: state,
            projectId: type == 'project'
                ? id
                : record.data['project_id'] as String,
            compact: MediaQuery.sizeOf(context).width < 1000,
          ),
        ),
      ),
    ),
    'supplier' || 'product' => CatalogDetail(state: state, type: type, id: id),
    'inquiry' => InquiryPage(state: state, id: id),
    _ => null,
  };
}

import 'core/models.dart';
import 'core/store.dart';

/// Scoped domain operations shared by host tools and research views.
/// The same store guards authorize every object ID before reading or writing.
class ResearchServices {
  ResearchServices(
    WorkbenchStore store,
    this.projectId, {
    this.ensureActive,
  }) : _store = store.scoped(projectId);
  final WorkbenchStore _store;
  final String projectId;
  final void Function()? ensureActive;

  List<ResearchDocument> documents() {
    ensureActive?.call();
    return _store.documents(projectId);
  }

  List<ResearchEntry> entries({String? kind}) {
    ensureActive?.call();
    return _store.entries(projectId, kind: kind);
  }

  List<ResearchRun> runs() {
    ensureActive?.call();
    return _store.runs(projectId);
  }

  List<ReadingNote> notes(String documentId) {
    ensureActive?.call();
    return _store.notes(documentId);
  }

  Future<void> saveNote(
    String documentId,
    String locator,
    String text, {
    int? pageNumber,
    String quote = '',
    String? evidenceKind,
    String doesNotSupport = '',
    String? entryId,
  }) => _write(
    () => _store.saveNote(
      documentId,
      locator,
      text,
      pageNumber: pageNumber,
      quote: quote,
      evidenceKind: evidenceKind,
      doesNotSupport: doesNotSupport,
      entryId: entryId,
    ),
  );

  Future<void> setNoteEntry(String noteId, String? entryId) =>
      _write(() => _store.setNoteEntry(noteId, entryId));

  Future<void> acceptRun(String runId) => _write(() => _store.acceptRun(runId));

  Future<void> assessRun(
    String runId, {
    required String result,
    required bool discriminating,
    required String reason,
    num? budgetSpent,
  }) => _write(
    () => _store.assessRun(
      runId,
      result: result,
      discriminating: discriminating,
      reason: reason,
      budgetSpent: budgetSpent,
    ),
  );

  Future<void> addOutline(String heading, String evidenceId) =>
      _write(() => _store.addOutline(projectId, heading, evidenceId));

  Future<void> _write(void Function() body) async {
    ensureActive?.call();
    await _store.write(() {
      ensureActive?.call();
      body();
    });
  }
}

# Personal study and project app — accepted design

Authority: the user's 2026-10-28 conversation. Personal Android app; offline-first;
Microduck warm-paper/terracotta visual style. Reuse develop native Android/Rust
capabilities without opening or altering legacy Flutter stores.

## Required behavior
- Five destinations: Today, Learning, Projects, Inbox, Settings. Chinese UI.
- Goals, supplied course steps and daily plans; Markdown/Word/Excel imports with
  preview. Tasks own duration, deadline, priority, dependencies and actual progress.
- Multiple goals, fixed weekly windows, exam deadlines immutable in replanning;
  other deadlines may be proposed for extension. Minimum learning quantities.
- Re-evaluate whole remaining plan when inputs change. Proposals never mutate the
  live schedule before explicit user confirmation; stale proposals are refused.
- Uploaded resources and example projects; videos are links only. Many-to-many
  task/resource links with page/segment/instruction notes.
- MEM papers.json-compatible import, practice/exam, durable answers and position,
  deterministic grading with optional keys, wrong-answer review and AI commentary.
- DIY projects, versions, BOM, purchase/arrival state, assembly steps and records.
- Work is lightweight tasks/deadlines/time blocks, not enterprise project tracking.
- Read all accessible Google calendars; app-managed calendar writes only after
  review. Drive file access/backup and Maimemo read-only progress; show freshness.
- DeepSeek and voice accept fragmented inputs; review changes before application.
- Due reminders only. Offline CRUD, downloaded resources, exercises and reminders;
  reconnect reconciles without replaying uncertain external writes.
- Consistent export/restore; keys excluded. User-supplied provider credentials.

## Delivery boundary
Source implementation, automated tests and installable APK are deliverables.
Real Google authorization requires a user-owned Cloud OAuth configuration and
Maimemo/DeepSeek credentials. Do not fabricate successful account verification,
voice availability, background reliability or device tests.

## Implementation decision
Add a dedicated study Android application target in the same repository, reusing
the Rust core SQLite seam and a purpose-specific bridge. This avoids bundling the
existing research app's mandatory large OCR/embedding model assets for features
that do not need those models. Existing apps and their release gates stay intact.
The study database has one local owner and a versioned schema; no duplicate Room
authority. Native UI adapts Android files, alarms, speech, authorization and HTTP.

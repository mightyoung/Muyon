# Personal Study App Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement task-by-task. The user authorized autonomous development through an app deliverable.

**Goal:** Deliver an installable personal Android learning, planning and DIY app.
**Architecture:** Dedicated Compose application in the Muyon repository; Rust-owned
SQLite state and deterministic scheduling/grading; Android adapters for files,
providers and alarms. Preserve existing applications and production gates.
**Tech Stack:** Kotlin/Compose, Rust/SQLite, JSON bridge, Android platform APIs.
**Spec:** docs/superpowers/specs/2026-10-28-personal-study-app.md

## Global Constraints
- Personal Android app, Chinese UI, Microduck warm paper/terracotta design.
- Exams cannot be postponed; suggestions require confirmation and revision check.
- Uploaded resources, video links, MEM-compatible papers, due reminders only.
- Offline source of truth; keys excluded from export; no invented provider/device acceptance.

## Review Focus
- Crash/reopen retains answers and actual progress; duplicate imports do not overwrite them.
- Changing task/calendar state invalidates a proposed schedule before confirmation.
- Malformed/oversized uploads, XML/ZIP paths and file provider grants fail safely.
- Calendar pagination, deleted events and expired credentials do not appear as zero commitments.
- Missing answer keys and provider failures remain unknown rather than successful.

## Task 1: Toolchain, core state and persistence
Files: crates/muyon-core/src/study/{mod,models,store}.rs;
crates/muyon-core/tests/study.rs. Interfaces: StudyStore::open,
snapshot, command(Value). JSON objects carry revision and stable IDs.
- [x] Write and run missing-feature tests for reopen, validation and atomic revision checks.
- [x] Implement versioned schema and task/goal/resource/project/inbox commands.
- [x] Run cargo test --locked --manifest-path crates/Cargo.toml -p muyon-core.
- [x] Commit code and record evidence.

## Task 2: Papers, imports, scheduling and backup
Files: study/{papers,scheduler,imports}.rs; tests/study.rs.
Interfaces: import_papers(Value), save_answer, submit_attempt,
propose_schedule(now,windows,busy), confirm_proposal(id,revision), export/restore.
- [x] Test MEM source, duplicate import, resume, missing keys and grading.
- [x] Test collision/dependencies, exam deadline, minimum allocation, stale confirmation.
- [x] Implement preview-first imports and complete state export/restore.
- [x] Run full core suite and commit.

## Task 3: Native bridge and Android shell
Files: crates/muyon-study-ffi/**; apps/study_android/**.
Interfaces: study_open(path), study_call(handle,JSON), study_close(handle);
StudyRepository.request returns structured success/error and revision.
- [x] Test bridge persistence and failed commands before UI integration.
- [x] Build native ARM64/x86_64 libraries and a Chinese five-tab Compose shell.
- [x] Verify Android compile and core suite; commit.

## Task 4: Complete offline workflows
Files: apps/study_android/app/src/main/java/com/mightyoung/muyon/study/**.
Interfaces: repository commands above; resource file IDs never arbitrary model paths.
- [x] Implement task/goals, resource upload/links, MEM practice/exam, wrong answers,
  DIY BOM/steps/versions, input inbox, schedule review and fixed windows.
- [x] Import Markdown/Word/Excel with preview and export/restore through file picker.
- [x] Verify state transitions and Android build; commit.

## Task 5: Android adapters and external connections
Files: study app adapters/{Calendar,Drive,Maimemo,DeepSeek,Reminders,Speech}.
- [x] Implement Google authorization/configuration, paginated reads and app-event mapping.
- [x] Implement Maimemo freshness, DeepSeek structured proposals/commentary, speech.
- [x] Implement local deadline alarms, boot/timezone reconciliation and secure keys.
- [x] Exercise adapters with local protocol fixtures; record real-account tests as pending.
- [x] Commit.

## Task 6: Whole-app verification and delivery
- [x] Run Rust workspace tests, Android unit checks, lint and APK assembly.
- [ ] Complete device interaction checks; software emulator cold boot is still pending.
- [x] Independently review diff, fix important findings, repeat relevant verification.
- [ ] Commit final review fixes and deliver APK; keep the isolated branch for review.
  External repository publication is not required for this delivery. Deliver
  build identity, setup guide and explicit remaining account/device prerequisites.

# UI-3a Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reject unsupported event/action pairs before rendering and retain the public preview behavior.
**Architecture:** Component schemas declare allowed action refs per event. Validation and dispatch check those pairs; detail rendering tolerates a missing value binding. Fixtures keep quantity facts distinct from delivery conflicts.
**Tech Stack:** Dart 3.13.4, Flutter 3.47.5.
**Spec:** User-authorized UI-3a independent review findings; baseline 4f2f749958a14ad9d94e607dc79ada62df753f28.

## Global Constraints

- Work only on task/ui-3a-semantic-preview-recovery; original author worktree is read-only.
- Exclude unrelated macOS Podfile and xcconfig changes.
- No business execution, private data, raw logs committed or develop merge.

## Review Focus

- SourceList tap must expand its source and cannot open missing-value detail.
- Field change must edit its bound draft and cannot navigate back.
- Missing required detail value must not crash rendering.
- Existing valid bindings and host operation checks remain intact.
- Delivery conflicts must not relabel verified quantity.

## Task 1: Recover and fix the reviewed slice

- [x] Copy/hash original uncommitted slice; exclude macOS changes.
- [x] Add two preview regression tests for incorrect event/action pairs.
- [x] Run regressions and record expected validator acceptance failures.
- [x] Add immutable UiComponentSchema.eventActions declarations in plan.dart and catalogs; reject incompatible pairs in validation.dart and dispatch.
- [x] Guard missing detail value in surface.dart; correct fixture delivery fact and existing fixture assertion.
- [x] Run all tests in the three affected packages, analyze and Web build using isolated SDK/config.
- [ ] Commit source manifest and concise validation summary; push exact recovery SHA for independent review.

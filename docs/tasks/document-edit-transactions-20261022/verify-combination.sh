#!/usr/bin/env bash
# No network, checkout mutation, alternate grants or dependency changes.
# Requires the exact document-core commit locally and existing locked dependencies.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
core_sha=ab9c381cc935be0cd52db5a8a455ce985bdba1db
combination=$(mktemp -d "${TMPDIR:-/tmp}/muyon-document-edit-check.XXXXXXXX")
echo "Combination directory: $combination"
echo "Exact core dependency: $core_sha"
git -C "$repo" archive "$core_sha" | tar -x -C "$combination"
mkdir -p "$combination/crates/muyon-core/src/document_edit"
cp "$repo/crates/muyon-core/src/document_edit/mod.rs" "$combination/crates/muyon-core/src/document_edit/mod.rs"
cp "$repo/crates/muyon-core/tests/document_edit_transactions.rs" "$combination/crates/muyon-core/tests/document_edit_transactions.rs"
# lib.rs and documents/ are the exact core-owner files; this script never edits them.
"${CARGO:-cargo}" test --offline --locked --manifest-path "$combination/crates/Cargo.toml" -p muyon-core --test document_edit_transactions --test documents

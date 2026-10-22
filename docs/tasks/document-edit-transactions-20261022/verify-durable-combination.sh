#!/usr/bin/env bash
# Offline exact-owner combination, no checkout mutation or dependency downloads.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
core_sha=${DOCUMENT_CORE_SHA:-faeef3aec3a9407d7c15490dcdb33866413e7453}
combination=$(mktemp -d "${TMPDIR:-/tmp}/muyon-document-durable-check.XXXXXXXX")
echo "Exact core dependency: $core_sha"
echo "Combination directory: $combination"
git -C "$repo" archive "$core_sha" | tar -x -C "$combination"
cp -R "$repo/crates/muyon-core/src/document_edit" "$combination/crates/muyon-core/src/"
for target in document_edit_transactions document_edit_gateway document_edit_engine_protocol document_edit_schema2 document_edit_candidates document_edit_policy_epoch document_edit_core_bridge; do
  cp "$repo/crates/muyon-core/tests/$target.rs" "$combination/crates/muyon-core/tests/$target.rs"
done
cp "$repo/crates/muyon-core/tests/document_edit_tree_goldens.json" "$combination/crates/muyon-core/tests/"
python3 - "$combination/crates/muyon-core/src/lib.rs" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);source=p.read_text()
if 'pub mod document_edit;' not in source:
    p.write_text(source+'\n// Verification-only export in temporary archive, not tracked source.\npub mod document_edit;\n')
PY
# The permanent module export belongs exclusively to document-core's owner.
if [[ $# -eq 0 ]]; then
  set -- -p muyon-core --test document_edit_gateway --test document_edit_engine_protocol --test document_edit_transactions --test document_edit_schema2 --test document_edit_candidates --test document_edit_policy_epoch --test document_edit_core_bridge --test document_storage --test documents
fi
"${CARGO:-cargo}" test --offline --locked --manifest-path "$combination/crates/Cargo.toml" "$@"

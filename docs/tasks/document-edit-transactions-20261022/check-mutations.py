"""Offline negative controls. Uses the real compiled exact document-core rlib.
No production files are changed; all variants execute under a fresh /tmp tree.
Usage: python3 check-mutations.py RUSTC CORE_RLIB DEPS_DIR NATIVE_DIR
"""
import pathlib
import subprocess
import sys
import tempfile

rustc, core, deps, native = sys.argv[1:]
repo = pathlib.Path(__file__).resolve().parents[3]
source = (repo / 'crates/muyon-core/src/document_edit/mod.rs').read_text()
test = (repo / 'crates/muyon-core/tests/document_edit_transactions.rs').read_text()
mutations = {
    'candidate binding removed': ('if c.binding != self.binding {', 'if false {'),
    'confirmation binding removed': ('if confirmation.binding != self.binding {', 'if false {'),
    'revocation removed': ('if !f.active', 'if false'),
    'reopen validation removed': ('if !v.reopened', 'if false'),
    'operation permission removed': ('if !f.permissions.contains(&operation) {', 'if false {'),
    'revision progression reverted to non-equality': ('if r.committed_revision != next {', 'if r.committed_revision == r.previous_revision {'),
    'CAS failure ignored': ('|| !r.cas_succeeded', '|| false'),
}
with tempfile.TemporaryDirectory(prefix='muyon-doc-edit-mutations-') as temp:
    root = pathlib.Path(temp)
    (root/'src/document_edit').mkdir(parents=True)
    (root/'tests').mkdir()
    (root/'tests/document_edit_transactions.rs').write_text(test)
    for name, (before, after) in mutations.items():
        assert before in source, name
        (root/'src/document_edit/mod.rs').write_text(source.replace(before, after))
        build = subprocess.run([rustc, '--edition=2021', '--test', str(root/'tests/document_edit_transactions.rs'), '--extern', 'muyon_core='+core, '-L', 'dependency='+deps, '-L', 'native='+native, '-o', str(root/'tests-bin')], capture_output=True, text=True)
        print('\nMUTATION:', name, 'compile exit:', build.returncode, flush=True)
        print(build.stdout + build.stderr, end='', flush=True)
        assert build.returncode == 0, 'compile failure does not count as mutation caught'
        result = subprocess.run([str(root/'tests-bin')], capture_output=True, text=True)
        print(result.stdout + result.stderr, end='', flush=True)
        assert result.returncode != 0 and 'FAILED' in result.stdout, 'mutation escaped: '+name
    print(f'\n{len(mutations)}/{len(mutations)} behavior mutations caught; no production files edited.')

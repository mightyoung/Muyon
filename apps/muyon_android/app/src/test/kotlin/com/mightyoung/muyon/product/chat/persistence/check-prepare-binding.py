#!/usr/bin/env python3
"""Cross-source ABI contract only; NEVER Kotlin/Android/native execution proof."""
from pathlib import Path
import re
import unittest

ROOT = next(path for path in Path(__file__).resolve().parents if (path / '.git').exists())
SERVICE = ROOT / 'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agentipc/ProductService.kt'
BINDING = ROOT / 'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/productbridge/muyon_android_product.kt'
FFI = ROOT / 'crates/muyon-android-ffi/src/lib.rs'


def record_call(source):
    start = source.index('override fun prepare(original: PreparedLocalSave): JSONObject =')
    tail = source[start:source.index('override fun save(', start)]
    if not re.search(r'data\(open\(false\)\.localDraftPrepareSave\(', tail):
        raise AssertionError('Service does not invoke actual generated prepare method')
    match = re.search(r'(?:com\.mightyoung\.muyon\.productbridge\.)?LocalDraftPrepareRequest\(', tail)
    if not match:
        raise AssertionError('actual generated request record not used')
    begin = match.end()
    depth = 1
    end = begin
    while depth and end < len(tail):
        depth += (tail[end] == '(') - (tail[end] == ')')
        end += 1
    if depth:
        raise AssertionError('unbalanced request')
    return ''.join(tail[begin:end-1].split())


def check_contract(service, binding, ffi):
    assert re.search(r'fun `localDraftPrepareSave`\(`request`: LocalDraftPrepareRequest\): kotlin.String', binding)
    block = re.search(r'data class LocalDraftPrepareRequest\s*\((.*?)\)\s*\{', binding, re.S)
    assert block
    fields = re.findall(r'var `([^`]+)`:\s*kotlin\.([A-Za-z]+\??)', block.group(1))
    expected = [('conversation', 'String'), ('project', 'String?'), ('namespaceId', 'String'),
                ('draftId', 'String'), ('expectedGeneration', 'String'), ('expectedStoredRevision', 'String'),
                ('attemptId', 'String'), ('exportedMemoryRevision', 'String'), ('hostEditorRevision', 'String'), ('archive', 'ByteArray')]
    assert fields == expected, 'generated ABI fields changed; owner must recheck producer'
    assert re.search(r'pub fn local_draft_prepare_save\(\s*&self,\s*request: LocalDraftPrepareRequest,', ffi)
    expected_mapping = '''conversation=original.record.conversationId,project=original.record.projectId,
        namespaceId=original.record.namespaceId,draftId=original.record.draftId,
        expectedGeneration=original.record.registryGeneration.toString(),expectedStoredRevision=original.record.storedRevision.toString(),
        attemptId=original.attemptId,exportedMemoryRevision=original.exportedMemoryRevision.toString(),
        hostEditorRevision=original.exportedLocalRevision.toString(),archive=original.archive'''
    assert record_call(service) == ''.join(expected_mapping.split()), 'captured original binding drift'
    port = service[service.index('localDraftPort = object : ProductLocalDraftPort'):]
    assert 'override val verified = localDraftPortVerifiedForBuild()' in port
    assert re.search(r'protected open fun localDraftPortVerifiedForBuild\(\): Boolean = false', service), 'production gate must remain false'


class PrepareBindingContract(unittest.TestCase):
    def test_real_repository_contract(self):
        check_contract(SERVICE.read_text(), BINDING.read_text(), FFI.read_text())

    def test_production_gate_cannot_be_opened(self):
        bad = SERVICE.read_text().replace('fun localDraftPortVerifiedForBuild(): Boolean = false',
                                          'fun localDraftPortVerifiedForBuild(): Boolean = true')
        with self.assertRaises(AssertionError):
            check_contract(bad, BINDING.read_text(), FFI.read_text())

    def test_wrong_base_revision_is_rejected(self):
        actual = SERVICE.read_text()
        if 'expectedStoredRevision = original.record.storedRevision.toString()' not in actual:
            self.skipTest('producer contract not implemented yet')
        bad = actual.replace('expectedStoredRevision = original.record.storedRevision.toString()',
                             'expectedStoredRevision = original.storedRevision.toString()', 1)
        with self.assertRaises(AssertionError):
            check_contract(bad, BINDING.read_text(), FFI.read_text())

    def test_stale_generated_record_is_rejected(self):
        stale = BINDING.read_text().replace('var `hostEditorRevision`: kotlin.String', 'var `editorRevision`: kotlin.String', 1)
        with self.assertRaises(AssertionError):
            check_contract(SERVICE.read_text(), stale, FFI.read_text())


if __name__ == '__main__':
    unittest.main()

"""Dormant python-docx source; unconditional gate before third-party import."""
from_guard_message='environment_hold: source/license/isolation/launcher qualification missing'


def edit_copy(job,source_path,candidate_path):
    raise RuntimeError(from_guard_message)
    # Unreachable source sketch: only a host-prevalidated direct run may be edited.
    from docx import Document
    document=Document(source_path)
    op=job['operation'];run=document.paragraphs[op['paragraph_index']].runs[op['run_index']]
    if run.text != op['expected']:raise ValueError('expected_value_conflict')
    # This library assignment may normalize XML; independent oracle must reject
    # any non-text-node or opaque-part change. No compatibility claim is made.
    run.text=op['replacement']
    with candidate_path.open('xb') as output:document.save(output)


if __name__=='__main__':raise RuntimeError(from_guard_message)

"""Permit-checked python-docx copy source; no default authority or engine import."""
from .runner.worker_gate import require_worker_permit


def edit_copy(job,source_path,candidate_path,*,permit=None):
    admitted=require_worker_permit(permit,job,source_path,candidate_path,'python-docx')
    job=admitted.request
    from docx import Document
    document=Document(source_path)
    op=job['operation'];run=document.paragraphs[op['paragraph_index']].runs[op['run_index']]
    if run.text != op['expected']:raise ValueError('expected_value_conflict')
    # This library assignment may normalize XML; independent oracle must reject
    # any non-text-node or opaque-part change. No compatibility claim is made.
    run.text=op['replacement']
    with candidate_path.open('xb') as output:document.save(output)


def main():
    from .runner.worker_entry import dispatch
    return dispatch('docx')

if __name__=='__main__':
    import json
    print(json.dumps(main(),sort_keys=True))

"""Permit-checked copy editor source; absent trusted bootstrap remains HOLD."""

from .runner.worker_gate import require_worker_permit


def edit_copy(job, source_path, candidate_path, *, permit=None):
    admitted=require_worker_permit(permit,job,source_path,candidate_path,'openpyxl')
    job=admitted.request
    from openpyxl import load_workbook
    admitted.engine_entered()
    workbook = load_workbook(source_path, read_only=False, data_only=False, keep_links=False)
    try:
        op = job['operation']
        cell = workbook[op['sheet']][op['cell']]
        if cell.data_type == 'f' or str(cell.value) != op['expected']:
            raise ValueError('expected_value_conflict')
        from decimal import Decimal
        value = Decimal(op['replacement'])
        cell.value = int(value) if value == value.to_integral() else float(value)
        # No recalc claim; native output normalization/unknown-part loss must fail
        # the independent candidate validator rather than silently be accepted.
        with candidate_path.open('xb') as output:
            workbook.save(output)
    finally:
        workbook.close()


def main():
    from .runner.worker_entry import dispatch
    return dispatch('xlsx')

if __name__=='__main__':
    import json
    print(json.dumps(main(),sort_keys=True))

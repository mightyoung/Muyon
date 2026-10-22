"""Dormant openpyxl source boundary. No CLI or function can currently start it."""

ENVIRONMENT_HOLD = True  # No override/env/CLI flag. Requires future reviewed integration.


def require_admitted_runtime():
    # Even mutating the public module constant is not a launch authorization.
    raise RuntimeError('environment_hold: no qualified isolation/provenance/license/launcher')


def edit_copy(job, source_path, candidate_path):
    require_admitted_runtime()
    # Dormant implementation, intentionally unreachable in this checkpoint.
    # A future host must deliver immutable prevalidated job and mount source RO,
    # isolate and enforce limits before lifting the gate in a reviewed patch.
    from openpyxl import load_workbook
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
    require_admitted_runtime()


if __name__ == '__main__':
    main()

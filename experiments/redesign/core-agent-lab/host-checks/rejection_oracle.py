"""Narrow fixed-spec rejection oracle, shared by Dart and inverse self checks."""
import argparse


def check(error, expected, prepare_count=0, invoke_count=0):
    # Allow only the host's fixed code decoration, never arbitrary error text.
    code = error.removeprefix('Bad state: ').split(':')[-1].strip()
    assert code in (expected, 'core_' + expected), 'wrong_rejection_boundary'
    assert prepare_count == 0, 'unexpected_prepare_before_argument_rejection'
    assert invoke_count == 0, 'unexpected_invoke_before_rejection'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--error', required=True)
    parser.add_argument('--expected', required=True)
    parser.add_argument('--prepare-count', type=int, default=0)
    parser.add_argument('--invoke-count', type=int, default=0)
    arguments = parser.parse_args()
    try:
        check(arguments.error, arguments.expected, arguments.prepare_count, arguments.invoke_count)
    except AssertionError as error:
        print(str(error))
        return 1
    print('expected_rejection_boundary')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

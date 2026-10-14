"""Copy only supplied stimulus sections; no oracle or case identity is consulted."""
from copy import deepcopy

STIMULUS_SECTIONS = ('input', 'source_inheritance', 'current_version', 'purpose',
                     'rule_coverage', 'actual_value_check', 'mode_facts', 'execution_prerequisites')


def to_stimulus(variant):
    return {name: deepcopy(variant[name]) for name in STIMULUS_SECTIONS if name in variant}

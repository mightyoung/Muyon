"""Pure, non-production oracle for the PROPOSED private supplier read contract.

No Binder, persistence, authority evaluation, SQL, endpoint, subprocess or model.
Values are interpreted only as untrusted display data; no command is executed.
"""
from copy import deepcopy
import re

MAX_EVENTS = 1024
MAX_TEXT_BYTES = 4096
MAX_ANSWER_BYTES = 32768
MAX_DELTA_BYTES = 1024


def bounded(value, maximum):
    if not isinstance(value, str) or not value:
        return False
    try:
        return len(value.encode('utf-8')) <= maximum
    except UnicodeEncodeError:
        return False


def identifier(value):
    return bounded(value, 128) and re.fullmatch(r'[A-Za-z0-9_-]+', value) is not None


def exact(value, keys):
    return type(value) is dict and set(value) == set(keys.split())


def validate_submission(value):
    if not exact(value, 'protocol epoch lease request_id text selected'):
        return False
    selected = value['selected']
    return (type(value['protocol']) is int and value['protocol'] == 1
            and all(identifier(value[key]) for key in ['epoch', 'lease', 'request_id'])
            and bounded(value['text'], MAX_TEXT_BYTES) and bool(value['text'].strip())
            and exact(selected, 'module_id type key revision schema_version')
            and type(selected['schema_version']) is int and selected['schema_version'] == 1
            and selected['module_id'] == 'inquiry' and selected['type'] == 'supplier'
            and identifier(selected['key']) and identifier(selected['revision']))


class ProjectionState:
    """Single admitted run's display merge; receipt is historical, projection current.

    Caller must authenticate transport and run lookup: this oracle does neither.
    Recovery identity is (connection, recovery_action()), retaining admitted_epoch.
    reconnect() models a NEW verified connection; it never accepts/resubmits work.
    """
    def __init__(self, submission, run_id):
        if not validate_submission(submission) or not identifier(run_id):
            raise ValueError('invalid admitted identity')
        self.submission = deepcopy(submission)
        self.admitted_epoch = submission['epoch']
        self.connection = (submission['epoch'], submission['lease'])
        self.run_id = run_id
        self.cursor = 0
        self.answer = ''
        self.receipt = None
        self.projection = None
        self.status = 'running'
        self.terminal = None
        self.can_submit = False  # An admitted identity can NEVER issue another submit.
        self._events = {}
        self._display_authorized = True

    def apply(self, value):
        if not exact(value, 'epoch request_id run_id cursor kind payload'):
            return 'invalid'
        if (value['epoch'], value['request_id'], value['run_id']) != (
                self.admitted_epoch, self.submission['request_id'], self.run_id):
            return 'identity_mismatch'
        cursor = value['cursor']
        if type(cursor) is not int or not 1 <= cursor <= MAX_EVENTS:
            return 'invalid'
        if cursor <= self.cursor:
            return 'duplicate' if self._events.get(cursor) == value else 'conflict'
        if self.terminal is not None:
            return 'terminal'
        if cursor != self.cursor + 1:
            return 'gap'
        payload, kind = value['payload'], value['kind']
        if kind in ('answer_delta', 'supplier_projection') and not self._display_authorized:
            return 'display_not_authorized'
        if kind == 'answer_delta':
            if (not exact(payload, 'text') or not bounded(payload['text'], MAX_DELTA_BYTES)
                    or len((self.answer + payload['text']).encode('utf-8')) > MAX_ANSWER_BYTES):
                return 'invalid'
            self.answer += payload['text']
        elif kind == 'receipt':
            if (not exact(payload, 'opaque_id outcome') or not bounded(payload['opaque_id'], 256)
                    or payload['outcome'] not in ('recorded_success', 'recorded_failure')
                    or (self.receipt is not None and self.receipt != payload)):
                return 'invalid'
            self.receipt = deepcopy(payload)  # Preserve original durable ID, never mint one.
        elif kind == 'supplier_projection':
            selected = self.submission['selected']
            if (not exact(payload, 'key revision name receipt_id')
                    or payload['key'] != selected['key'] or payload['revision'] != selected['revision']
                    or not bounded(payload['name'], 512) or self.receipt is None
                    or self.receipt['outcome'] != 'recorded_success'
                    or payload['receipt_id'] != self.receipt['opaque_id']):
                return 'invalid'
            self.projection = deepcopy(payload)
        elif kind == 'terminal':
            if (not exact(payload, 'outcome') or payload['outcome'] not in (
                    'completed', 'cancelled', 'failed', 'budget_exhausted', 'unknown')
                    or (payload['outcome'] == 'completed' and (
                        self.receipt is None or self.receipt['outcome'] != 'recorded_success'
                        or self.projection is None))):
                return 'invalid'
            self.status = self.terminal = payload['outcome']
            if self.terminal != 'completed':
                self.invalidate_projection()
        else:
            return 'invalid'
        self.cursor = cursor
        self._events[cursor] = deepcopy(value)
        return 'applied'

    def invalidate_projection(self):
        self.projection = None
        self.answer = ''
        self._display_authorized = False

    def reauthorize_display(self):
        """Trusted caller assertion after host scope/policy check; not an authority API."""
        self._display_authorized = True

    def binder_lost(self):
        self.connection = None
        self.invalidate_projection()
        if self.terminal is None:
            self.status = 'unknown'

    def reconnect(self, epoch, lease):
        if not identifier(epoch) or not identifier(lease):
            raise ValueError('invalid connection')
        self.connection = (epoch, lease)

    def recovery_action(self):
        return ('lookup', self.submission['request_id'], self.run_id, self.cursor)

    def cancel(self, epoch, lease, request_id):
        if self.connection != (epoch, lease) or request_id != self.submission['request_id']:
            return 'rejected'
        if self.terminal is not None:
            return 'already_terminal'
        self.status = 'cancel_requested'
        return 'requested'

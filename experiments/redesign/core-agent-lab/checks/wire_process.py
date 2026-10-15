"""Independent actual-request/physical-receipt oracle; no alternate Agent DUT."""
import json


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate captured request key')
        result[key] = value
    return result


def read_request(path):
    return json.loads(path.read_bytes().decode('utf-8'), object_pairs_hook=unique_object)


def assert_native_pair(first, second, value, receipt, call_id='call_native_1'):
    expected_schema = {'type': 'object', 'properties': {'value': {'type': 'string'}},
                       'required': ['value'], 'additionalProperties': False}
    for request in [first, second]:
        assert request['model'] == 'fixture-model'
        assert request['stream'] is True
        assert len(request['tools']) == 1
        spec = request['tools'][0]
        assert spec['type'] == 'function'
        assert spec['function']['name'] == 'fixture__record'
        assert spec['function']['parameters'] == expected_schema
    messages = second['messages']
    tool_index = max(index for index, message in enumerate(messages) if message.get('role') == 'tool') if any(message.get('role') == 'tool' for message in messages) else -1
    assert tool_index > 0, 'actual request has no role=tool result'
    tool = messages[tool_index]
    assert tool.get('tool_call_id') == call_id, 'tool result call ID differs'
    assistant = messages[tool_index - 1]
    assert assistant.get('role') == 'assistant', 'tool result has no preceding assistant call'
    calls = assistant.get('tool_calls')
    assert isinstance(calls, list) and len(calls) == 1, 'actual assistant.tool_calls missing'
    call = calls[0]
    assert call['id'] == call_id and call['type'] == 'function'
    assert call['function']['name'] == 'fixture__record'
    arguments = json.loads(call['function']['arguments'], object_pairs_hook=unique_object)
    assert arguments == {'value': value}, 'captured arguments differ from physical effect'
    content = json.loads(tool['content'], object_pairs_hook=unique_object)
    assert content.get('value') == value and content.get('receipt') == receipt, 'captured tool content differs from original physical receipt'

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/openai_compat_provider.dart';

const _provider = OpenAiCompatProvider();

ModelProfile _profile({bool streaming = true}) => ModelProfile(
  id: 'p',
  endpoint: Uri.parse('http://127.0.0.1:1/v1'),
  location: ModelLocation.local,
  modelId: 'm',
  endpointIdentity: 'fixture',
  capabilities: ModelCapabilities(streaming: streaming, nativeTools: true),
);

const _tools = [
  ModelToolSpec(
    name: 'inquiry__project_budget',
    description: '预算（效应：read）',
    parameters: {
      'type': 'object',
      'properties': {
        'project_id': {'type': 'string'},
      },
    },
  ),
  ModelToolSpec(
    name: 'read',
    description: 'r',
    parameters: {'type': 'object', 'properties': <String, Object?>{}},
  ),
];

ModelRequest _request({bool streaming = true, bool jsonObject = false}) =>
    ModelRequest(
      profile: _profile(streaming: streaming),
      messages: const [ModelMessage(role: 'user', content: 'hi')],
      tools: _tools,
      jsonObject: jsonObject,
      caller: 'assistant',
    );

String _chunk(Map<String, Object?> delta, {String? finish, Object? usage}) =>
    'data: ${jsonEncode({
      'choices': [
        {'delta': delta, 'finish_reason': finish},
      ],
      'usage': ?usage,
    })}\n\n';

Stream<List<int>> _bytes(String body, {int? size}) {
  final all = utf8.encode(body);
  if (size == null) return Stream.value(all);
  return Stream.fromIterable([
    for (var i = 0; i < all.length; i += size)
      all.sublist(i, i + size > all.length ? all.length : i + size),
  ]);
}

Future<List<ModelEvent>> _decode(String body, {int? size, bool? streaming}) =>
    _provider
        .decode(
          _request(streaming: streaming ?? true),
          _bytes(body, size: size),
        )
        .toList();

void main() {
  group('request mapping', () {
    test('a streaming request asks for usage; tools carry the real schema', () {
      final wire = _provider.encode(_request());
      expect(wire['stream'], true);
      expect(wire['stream_options'], {'include_usage': true});
      expect(wire['tool_choice'], 'auto');
      final tool = (wire['tools'] as List).first as Map;
      expect(tool['type'], 'function');
      expect((tool['function'] as Map)['name'], 'inquiry__project_budget');
      expect(((tool['function'] as Map)['parameters'] as Map)['properties'], {
        'project_id': {'type': 'string'},
      });
      expect(wire.containsKey('response_format'), isFalse);
    });

    test('a non-streaming request says stream false and has no options', () {
      final wire = _provider.encode(_request(streaming: false));
      expect(wire['stream'], false);
      expect(wire.containsKey('stream_options'), isFalse);
    });

    test('no tools means no tools, tool_choice or protocol parameters', () {
      final wire = _provider.encode(
        ModelRequest(
          profile: _profile(),
          messages: const [ModelMessage(role: 'user', content: 'x')],
          jsonObject: true,
          maxOutputTokens: 99,
          caller: 'assistant',
        ),
      );
      expect(wire.containsKey('tools'), isFalse);
      expect(wire.containsKey('tool_choice'), isFalse);
      expect(wire['response_format'], {'type': 'json_object'});
      expect(wire['max_tokens'], 99);
    });

    test('assistant tool_calls and tool results keep their pairing ids', () {
      final wire = _provider.encode(
        ModelRequest(
          profile: _profile(),
          messages: const [
            ModelMessage(
              role: 'assistant',
              toolCalls: [
                ModelToolCall(id: 'c1', name: 'read', arguments: '{}'),
              ],
            ),
            ModelMessage(role: 'tool', content: 'result', toolCallId: 'c1'),
          ],
          caller: 'assistant',
        ),
      );
      final messages = wire['messages'] as List;
      expect((messages[0] as Map)['tool_calls'], [
        {
          'id': 'c1',
          'type': 'function',
          'function': {'name': 'read', 'arguments': '{}'},
        },
      ]);
      expect((messages[1] as Map)['tool_call_id'], 'c1');
    });
  });

  group('streaming responses', () {
    test('text, usage tail and [DONE], however the bytes are cut', () async {
      final body =
          ': keep-alive\n\n'
          '${_chunk({'content': '你好，'})}'
          'event: ignored\r\n${_chunk({'content': '世界'})}'
          '${_chunk({}, finish: 'stop')}'
          'data: ${jsonEncode({
            'choices': <Object?>[],
            'usage': {'prompt_tokens': 12, 'completion_tokens': 3},
          })}\n\n'
          'data: [DONE]\n\n';
      for (final size in [null, 1, 2, 5, 7]) {
        final events = await _decode(body, size: size);
        expect(
          events.whereType<TextDelta>().map((e) => e.text).join(),
          '你好，世界',
          reason: 'chunk size $size',
        );
        final usage = events.whereType<Usage>().single;
        expect([usage.promptTokens, usage.completionTokens], [12, 3]);
        expect((events.last as Done).reason, FinishReason.stop);
        expect(events.whereType<ModelError>(), isEmpty);
      }
    });

    test('arguments spread over chunks are joined and parsed once', () async {
      final body =
          '${_chunk({
            'tool_calls': [
              {
                'index': 0,
                'id': 'call_1',
                'function': {'name': 'inquiry__project_budget', 'arguments': ''},
              },
            ],
          })}'
          '${_chunk({
            'tool_calls': [
              {
                'index': 0,
                'function': {'arguments': '{"project_'},
              },
            ],
          })}'
          '${_chunk({
            'tool_calls': [
              {
                'index': 0,
                'function': {'arguments': 'id":"p1"}'},
              },
            ],
          })}'
          '${_chunk({}, finish: 'tool_calls')}'
          'data: [DONE]\n\n';
      final events = await _decode(body, size: 3);
      expect(events.whereType<ToolCallDelta>(), hasLength(3));
      final call = events.whereType<ToolCallComplete>().single;
      expect(call.valid, isTrue);
      expect(call.callId, 'call_1');
      expect(call.name, 'inquiry__project_budget');
      expect(call.arguments, {'project_id': 'p1'});
      expect((events.last as Done).reason, FinishReason.toolCalls);
      // The call is complete only after every fragment; it comes before Done.
      expect(
        events.indexWhere((e) => e is ToolCallComplete),
        lessThan(events.indexWhere((e) => e is Done)),
      );
    });

    test('two calls at different indexes stay separate', () async {
      final body =
          '${_chunk({
            'tool_calls': [
              {
                'index': 0,
                'id': 'a',
                'function': {'name': 'read', 'arguments': '{}'},
              },
              {
                'index': 1,
                'id': 'b',
                'function': {'name': 'inquiry__project_budget', 'arguments': '{"project_id":"x"}'},
              },
            ],
          })}'
          '${_chunk({}, finish: 'tool_calls')}';
      final calls = (await _decode(body))
          .whereType<ToolCallComplete>()
          .toList();
      expect(calls.map((c) => c.callId), ['a', 'b']);
      expect(calls.every((c) => c.valid), isTrue);
    });

    test(
      'a legacy function_call is a protocol problem, never a call',
      () async {
        final body =
            '${_chunk({
              'function_call': {'name': 'read', 'arguments': '{}'},
            })}'
            '${_chunk({}, finish: 'function_call')}';
        final events = await _decode(body);
        final call = events.whereType<ToolCallComplete>().single;
        expect(call.valid, isFalse);
        expect(call.problem, 'legacy_function_call');
      },
    );

    test('an unknown function name, a repeated id and bad arguments are '
        'problems', () async {
      Future<ToolCallComplete> one(
        String name,
        String args, {
        String id = 'x',
      }) async {
        final body =
            '${_chunk({
              'tool_calls': [
                {
                  'index': 0,
                  'id': id,
                  'function': {'name': name, 'arguments': args},
                },
              ],
            })}${_chunk({}, finish: 'tool_calls')}';
        return (await _decode(body)).whereType<ToolCallComplete>().single;
      }

      expect(
        (await one('delete_everything', '{}')).problem,
        'tool_call_unknown_name',
      );
      // Decoding is a lookup: a name that merely decodes to a registered id
      // is not one we sent.
      expect(
        (await one('inquiry.project_budget', '{}')).problem,
        'tool_call_unknown_name',
      );
      expect((await one('read', '[1]')).problem, 'tool_call_arguments_invalid');
      expect(
        (await one('read', '{"a":')).problem,
        'tool_call_arguments_invalid',
      );
      expect((await one('read', '{}', id: '')).problem, 'tool_call_incomplete');
      final dup =
          '${_chunk({
            'tool_calls': [
              {
                'index': 0,
                'id': 'd',
                'function': {'name': 'read', 'arguments': '{}'},
              },
              {
                'index': 1,
                'id': 'd',
                'function': {'name': 'read', 'arguments': '{}'},
              },
            ],
          })}${_chunk({}, finish: 'tool_calls')}';
      final calls = (await _decode(dup)).whereType<ToolCallComplete>().toList();
      expect(calls.map((c) => c.problem), [null, 'tool_call_duplicate_id']);
    });

    test(
      'finish_reason length yields no tool call and a length Done',
      () async {
        final body =
            '${_chunk({
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'a',
                  'function': {'name': 'read', 'arguments': '{"half'},
                },
              ],
            })}${_chunk({}, finish: 'length')}data: [DONE]\n\n';
        final events = await _decode(body);
        expect(events.whereType<ToolCallComplete>(), isEmpty);
        expect((events.last as Done).reason, FinishReason.length);
      },
    );

    test('provider tool-call markup in the text is text, not a call', () async {
      const dsml =
          '<｜｜DSML｜｜ calls>[{"name":"read","arguments":{}}]</｜｜DSML｜｜ calls>';
      final events = await _decode(
        '${_chunk({'content': dsml})}${_chunk({}, finish: 'stop')}',
      );
      expect(events.whereType<ToolCallComplete>(), isEmpty);
      expect(events.whereType<TextDelta>().single.text, dsml);
      expect((events.last as Done).reason, FinishReason.stop);
    });

    test('an error event and a malformed chunk end the stream with a fixed '
        'code that does not quote the endpoint', () async {
      const secret = 'sk-live-0123456789abcdef';
      final error = await _decode(
        '${_chunk({'content': 'par'})}'
        'data: ${jsonEncode({
          'error': {'message': 'bad key $secret'},
        })}\n\n${_chunk({'content': 'never'})}',
      );
      final failure = error.last as ModelError;
      expect(failure.code, 'provider_error');
      expect(failure.partialOutput, isTrue);
      expect(error.whereType<TextDelta>().map((e) => e.text).join(), 'par');
      final malformed = await _decode('data: {"choices": [ $secret\n\n');
      expect((malformed.single as ModelError).code, 'stream_malformed');
      expect(
        [...error, ...malformed].whereType<ModelError>().map((e) => e.code),
        everyElement(isNot(contains(secret))),
      );
    });

    test('a stream that stops before a finish reason yields no Done', () async {
      final events = await _decode(_chunk({'content': 'half'}));
      expect(events.whereType<Done>(), isEmpty);
      expect(
        events.whereType<ModelError>(),
        isEmpty,
        reason: 'the gateway reports stream_truncated',
      );
    });

    test('[DONE] without a finish reason is not a complete reply', () async {
      final events = await _decode(
        '${_chunk({'content': 'x'})}data: [DONE]\n\n',
      );
      expect((events.last as ModelError).code, 'stream_truncated');
    });
  });

  group('non-streaming responses', () {
    String whole(
      Map<String, Object?> message, {
      String finish = 'stop',
      Object? usage,
    }) => jsonEncode({
      'choices': [
        {'message': message, 'finish_reason': finish},
      ],
      'usage': ?usage,
    });

    test('text and usage', () async {
      final events = await _decode(
        whole(
          {'content': 'answer'},
          usage: {'prompt_tokens': 5, 'completion_tokens': 1},
        ),
        streaming: false,
      );
      expect(events.whereType<TextDelta>().single.text, 'answer');
      expect(events.whereType<Usage>().single.promptTokens, 5);
      expect((events.last as Done).reason, FinishReason.stop);
    });

    test('a tool call, a legacy call and a name that was not sent', () async {
      final ok = await _decode(
        whole({
          'content': null,
          'tool_calls': [
            {
              'id': 'c',
              'type': 'function',
              'function': {'name': 'read', 'arguments': '{}'},
            },
          ],
        }, finish: 'tool_calls'),
        streaming: false,
      );
      expect(ok.whereType<ToolCallComplete>().single.valid, isTrue);
      final legacy = await _decode(
        whole({
          'content': null,
          'function_call': {'name': 'read', 'arguments': '{}'},
        }),
        streaming: false,
      );
      expect(
        legacy.whereType<ToolCallComplete>().single.problem,
        'legacy_function_call',
      );
      final unknown = await _decode(
        whole({
          'tool_calls': [
            {
              'id': 'c',
              'function': {'name': 'nope', 'arguments': '{}'},
            },
          ],
        }, finish: 'tool_calls'),
        streaming: false,
      );
      expect(
        unknown.whereType<ToolCallComplete>().single.problem,
        'tool_call_unknown_name',
      );
    });

    test('empty choices and error bodies are fixed codes', () async {
      expect(
        ((await _decode('{"choices":[]}', streaming: false)).single
                as ModelError)
            .code,
        'empty_choices',
      );
      expect(
        ((await _decode(
                  '{"error":{"message":"sk-secret-secret"}}',
                  streaming: false,
                )).single
                as ModelError)
            .code,
        'provider_error',
      );
      expect(
        ((await _decode('not json', streaming: false)).single as ModelError)
            .code,
        'response_not_json',
      );
    });
  });
}

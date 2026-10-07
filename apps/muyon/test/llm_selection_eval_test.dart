import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/selection_eval/llm_selection_eval.dart';
import 'package:muyon/assistant/selection_eval/selection_eval.dart';
import 'package:muyon/assistant/tool_selection.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:path/path.dart' as p;

/// Reads the eval key from the environment only; nothing is stored.
class EnvironmentSecretStore implements SecretStore {
  const EnvironmentSecretStore(this.environment);
  final Map<String, String> environment;
  @override
  Future<String?> read(String reference) async {
    final value = environment[reference];
    return value == null || value.isEmpty ? null : value;
  }
}

const _keyVariable = 'MUYON_EVAL_MODEL_KEY';

/// A key that dart:io can put in a header unchanged. Anything else (a
/// trailing `\r`, full-width characters) makes header setting throw with the
/// whole `Bearer <key>` in the message, so it is refused before any request.
final _visibleAscii = RegExp(r'^[\x21-\x7E]+$');

/// Loopback endpoints are local; any other endpoint is remote, which
/// [ModelProfile] requires to be HTTPS and authenticated.
ModelProfile evalProfileFromEnvironment(Map<String, String> environment) {
  final endpoint = Uri.parse(environment['MUYON_EVAL_MODEL_ENDPOINT']!.trim());
  final key = environment[_keyVariable] ?? '';
  final hasKey = key.isNotEmpty;
  if (hasKey && !_visibleAscii.hasMatch(key)) {
    throw ArgumentError(
      '$_keyVariable must be visible ASCII only (value not shown)',
    );
  }
  final local = ['localhost', '127.0.0.1', '::1'].contains(endpoint.host);
  if (!local && !hasKey) {
    throw ArgumentError('A remote endpoint needs $_keyVariable');
  }
  return ModelProfile(
    id: 'selection-eval',
    endpoint: endpoint,
    location: local ? ModelLocation.local : ModelLocation.remote,
    modelId: environment['MUYON_EVAL_MODEL_ID']!.trim(),
    endpointIdentity: endpoint.host,
    credentialRef: hasKey ? _keyVariable : null,
  );
}

/// Per-request timeout: `MUYON_EVAL_MODEL_TIMEOUT_SECONDS`, else the
/// gateway default of 45 s.
Duration evalTimeoutFromEnvironment(Map<String, String> environment) {
  final raw = (environment['MUYON_EVAL_MODEL_TIMEOUT_SECONDS'] ?? '').trim();
  if (raw.isEmpty) return const Duration(seconds: 45);
  final seconds = int.tryParse(raw);
  if (seconds == null || seconds <= 0) {
    throw ArgumentError(
      'MUYON_EVAL_MODEL_TIMEOUT_SECONDS must be a positive whole number',
    );
  }
  return Duration(seconds: seconds);
}

/// Why the real run is skipped, or null when it runs. Model variables alone
/// are not enough: `MUYON_EVAL_REAL=1` must be set as well, so an exported
/// configuration never turns a plain `flutter test` into paid requests.
String? realRunSkipReason(Map<String, String> environment) {
  final configured =
      (environment['MUYON_EVAL_MODEL_ENDPOINT'] ?? '').trim().isNotEmpty &&
      (environment['MUYON_EVAL_MODEL_ID'] ?? '').trim().isNotEmpty;
  final enabled = environment['MUYON_EVAL_REAL'] == '1';
  if (configured && enabled) return null;
  if (configured) {
    return 'model variables are set but MUYON_EVAL_REAL=1 is not; '
        'set it to send the 140 prompts to the real model';
  }
  return 'set MUYON_EVAL_REAL=1, MUYON_EVAL_MODEL_ENDPOINT and '
      'MUYON_EVAL_MODEL_ID to run';
}

typedef _Reply = FutureOr<void> Function(
  Map<String, dynamic> body,
  HttpResponse response,
);

/// A loopback model that hands each request body to [reply].
Future<(HttpServer, ModelProfile, List<Map<String, dynamic>>)> _fixture(
  _Reply reply,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final bodies = <Map<String, dynamic>>[];
  server.listen((request) async {
    final body = jsonDecode(
      await utf8.decoder.bind(request).join(),
    ) as Map<String, dynamic>;
    bodies.add(body);
    await reply(body, request.response);
    await request.response.close();
  });
  final profile = ModelProfile(
    id: 'fixture',
    endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
    location: ModelLocation.local,
    modelId: 'fixture-model',
    endpointIdentity: 'fixture',
  );
  return (server, profile, bodies);
}

String _prompt(Map<String, dynamic> body) =>
    ((body['messages'] as List).last as Map)['content'] as String;

Map<String, Object?> _message(Map<String, Object?> message, {Object? usage}) =>
    {
      'choices': [
        {'index': 0, 'message': message, 'finish_reason': 'stop'},
      ],
      'usage': ?usage,
    };

Map<String, Object?> _call(String name, {Object? usage, int calls = 1}) =>
    _message({
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        for (var i = 0; i < calls; i++)
          {
            'id': 'call_$i',
            'type': 'function',
            'function': {'name': name, 'arguments': '{}'},
          },
      ],
    }, usage: usage);

Map<String, Object?> _noCall({Object? usage}) =>
    _message({'role': 'assistant', 'content': '请说明要处理哪份资料。'}, usage: usage);

void _json(HttpResponse response, Object? body) =>
    response.write(jsonEncode(body));

final _ids = {for (final tool in evaluationTools()) tool.descriptor.toolId};

/// Echoes the tool for a prompt that is exactly a registered id, else no call:
/// the offline rule's behavior over the function-calling protocol.
void _echo(Map<String, dynamic> body, HttpResponse response, {Object? usage}) {
  final prompt = _prompt(body).trim();
  _json(
    response,
    _ids.contains(prompt)
        ? _call(encodeToolName(prompt), usage: usage)
        : _noCall(usage: usage),
  );
}

final _taskByPrompt = {for (final task in selectionTasks) task.prompt: task};

Future<LlmChoice> _ask(ModelProfile profile, String prompt) => chooseWithModel(
  gateway: OpenAiModelGateway(UnavailableSecretStore()),
  profile: profile,
  tools: evaluationTools(),
  taskId: 't',
  prompt: prompt,
);

Future<LlmSelectionRun> _run(ModelProfile profile) => scoreLlm(
  gateway: OpenAiModelGateway(UnavailableSecretStore()),
  profile: profile,
);

void main() {
  test('the request carries the fixed system prompt, tool_choice auto and every tool encoded with its effect', () async {
    final (_, profile, bodies) = await _fixture(
      (body, response) => _json(response, _noCall()),
    );
    final choice = await _ask(profile, '查一下离心泵');
    expect(choice.error, isNull);
    final body = bodies.single;
    expect(body['model'], 'fixture-model');
    expect(body['stream'], false);
    expect(body['tool_choice'], 'auto');
    expect(body.containsKey('temperature'), isFalse);
    final messages = body['messages'] as List;
    expect(messages, [
      {'role': 'system', 'content': llmSelectionSystemPrompt},
      {'role': 'user', 'content': '查一下离心泵'},
    ]);
    final tools = (body['tools'] as List).cast<Map<String, dynamic>>();
    final registered = evaluationTools();
    expect(tools.length, registered.length);
    final byName = {
      for (final tool in tools)
        (tool['function'] as Map)['name'] as String: tool,
    };
    for (final info in registered) {
      final name = encodeToolName(info.descriptor.toolId);
      expect(name, matches(RegExp(r'^[a-zA-Z0-9_-]{1,64}$')));
      expect(name, isNot(contains('.')));
      final tool = byName[name];
      expect(tool, isNotNull, reason: name);
      expect(tool!['type'], 'function');
      final function = tool['function'] as Map;
      final description = function['description'] as String;
      expect(description, contains(info.descriptor.description));
      expect(description, contains('效应：${info.descriptor.effect.name}'));
      expect(function['parameters'], {
        'type': 'object',
        'properties': <String, Object?>{},
      });
    }
    expect(byName.keys, contains('knowledge__embedding_preview'));
    expect(byName.keys, contains('inquiry__compare_quotes'));
  });

  test('temperature is sent only when set', () async {
    final (_, profile, bodies) = await _fixture(
      (body, response) => _json(response, _noCall()),
    );
    await chooseWithModel(
      gateway: OpenAiModelGateway(UnavailableSecretStore()),
      profile: profile,
      tools: evaluationTools(),
      taskId: 't',
      prompt: 'x',
      temperature: 0,
    );
    expect(bodies.single['temperature'], 0);
  });

  test('a tool call with null content decodes to the registered id and is a choice', () async {
    final (_, profile, _) = await _fixture(
      (body, response) => _json(
        response,
        _call(
          'knowledge__embedding_preview',
          usage: {'prompt_tokens': 300, 'completion_tokens': 12},
        ),
      ),
    );
    final choice = await _ask(profile, '预览一下要发出去的索引文本');
    expect(choice.error, isNull);
    expect(choice.rawName, 'knowledge__embedding_preview');
    expect(choice.toolId, 'knowledge.embedding_preview');
    expect(choice.invalidName, isFalse);
    expect(choice.toolCallCount, 1);
    expect(choice.promptTokens, 300);
    expect(choice.completionTokens, 12);
    expect(choice.decision.abstains, isFalse);
    expect(choice.decision.toolId, 'knowledge.embedding_preview');
    expect(choice.latencyMs, greaterThan(0));
  });

  test('response shapes: none, unregistered, error and usage', () async {
    final ids = toolIdsByFunctionName(evaluationTools());
    LlmChoice parse(Object? decoded) =>
        parseLlmResponse(decoded, idsByName: ids, taskId: 't', latencyMs: 1);
    void isNone(LlmChoice choice) {
      expect(choice.error, isNull);
      expect(choice.rawName, isNull);
      expect(choice.toolId, isNull);
      expect(choice.decision.abstains, isTrue);
      expect(choice.shown, 'none');
    }

    void isUnregistered(LlmChoice choice, String raw) {
      expect(choice.error, isNull);
      expect(choice.rawName, raw);
      expect(choice.toolId, isNull);
      expect(choice.invalidName, isTrue);
      expect(choice.decision.abstains, isFalse);
      expect(choice.shown, '<unregistered>');
    }

    // No call in any of the accepted spellings is "none".
    isNone(parse(_noCall()));
    isNone(parse(_message({'role': 'assistant', 'content': null})));
    isNone(parse(_message({'content': 'x', 'tool_calls': null})));
    isNone(parse(_message({'content': 'x', 'tool_calls': <Object?>[]})));

    // A name that was not sent is unregistered, even when it decodes to
    // something id-shaped or is the dotted id itself.
    isUnregistered(parse(_call('knowledge__nope')), 'knowledge__nope');
    isUnregistered(
      parse(_call('knowledge__search__x')),
      'knowledge__search__x',
    );
    isUnregistered(parse(_call('knowledge.search')), 'knowledge.search');
    isUnregistered(parse(_call('delete_everything')), 'delete_everything');
    isUnregistered(
      parse(
        _message({
          'tool_calls': [
            {'type': 'function', 'function': <String, Object?>{}},
          ],
        }),
      ),
      '',
    );
    isUnregistered(
      parse(
        _message({
          'tool_calls': [
            {
              'type': 'function',
              'function': {'name': 42},
            },
          ],
        }),
      ),
      '',
    );
    isUnregistered(
      parse(
        _message({
          'tool_calls': ['not a map'],
        }),
      ),
      '',
    );

    // Responses that do not say whether a tool was called are errors.
    for (final malformed in <Object?>[
      <Object?>[],
      <String, Object?>{},
      {'choices': <Object?>[]},
      {
        'choices': ['x'],
      },
      {
        'choices': [<String, Object?>{}],
      },
      _message({'tool_calls': 'knowledge__search'}),
      _message({
        'function_call': {'name': 'knowledge__search'},
      }),
    ]) {
      expect(
        () => parse(malformed),
        throwsFormatException,
        reason: '$malformed',
      );
    }

    // Several calls: the first is taken and the count kept.
    final several = parse(_call('transfer__send', calls: 3));
    expect(several.toolId, 'transfer.send');
    expect(several.toolCallCount, 3);

    // Usage is optional and a malformed usage never voids the choice.
    final noUsage = parse(_call('knowledge__search'));
    expect(noUsage.usageReported, isFalse);
    final badUsage = parse(
      _call(
        'knowledge__search',
        usage: {'prompt_tokens': '12', 'completion_tokens': null},
      ),
    );
    expect(badUsage.toolId, 'knowledge.search');
    expect(badUsage.usageReported, isFalse);
    expect(
      parse(_call('knowledge__search', usage: 'n/a')).usageReported,
      isFalse,
    );
  });

  test(
    'HTTP errors and malformed bodies are returned as errors, never as none',
    () async {
      final (_, profile, _) = await _fixture((body, response) {
        switch (_prompt(body)) {
          case '500':
            response.statusCode = 500;
            response.write('{"error":"boom"}');
          case 'json':
            response.write('{"choices": [');
          case 'list':
            response.write('[]');
          case 'nomessage':
            _json(response, {
              'choices': [
                {'finish_reason': 'stop'},
              ],
            });
        }
      });
      for (final prompt in ['500', 'json', 'list', 'nomessage']) {
        final choice = await _ask(profile, prompt);
        expect(choice.error, isNotNull, reason: prompt);
        expect(choice.toolId, isNull);
        expect(choice.invalidName, isFalse);
        expect(choice.decision.abstains, isFalse, reason: prompt);
        expect(choice.shown, '<error>');
      }
      expect((await _ask(profile, '500')).error, contains('model_http_500'));
    },
  );

  test('a full fixture run that echoes exact ids reproduces the offline rule per category', () async {
    final (_, profile, bodies) = await _fixture(
      (body, response) => _echo(
        body,
        response,
        usage: {'prompt_tokens': 100, 'completion_tokens': 5},
      ),
    );
    final run = await _run(profile);
    final rule = scoreRule(const RuleAndModelToolSelection());
    expect(bodies.length, selectionTasks.length);
    expect(run.choices.length, selectionTasks.length);
    expect(run.errors, 0);
    expect(run.invalidNames, 0);
    final score = run.score;
    expect(score.strategyId, llmSelectionStrategyId);
    expect(score.tasks, rule.tasks);
    expect(score.top1, rule.top1);
    expect(score.top1, 54);
    expect(score.falseWriteOrExternal, rule.falseWriteOrExternal);
    expect(score.abstained, rule.abstained);
    expect(score.shouldAbstain, rule.shouldAbstain);
    expect(
      [
        for (final row in score.byCategory)
          [
            row.category,
            row.tasks,
            row.top1,
            row.falseWriteOrExternal,
            row.shouldAbstain,
            row.abstained,
          ],
      ],
      [
        for (final row in rule.byCategory)
          [
            row.category,
            row.tasks,
            row.top1,
            row.falseWriteOrExternal,
            row.shouldAbstain,
            row.abstained,
          ],
      ],
    );
    expect(
      score.cost,
      '${100 * selectionTasks.length} in / ${5 * selectionTasks.length} out tokens',
    );
    expect(score.latencyMs, greaterThan(0));
    expect(run.percentileMs(0.95), greaterThanOrEqualTo(run.percentileMs(0.5)));
  });

  test('failed requests and unregistered names on none tasks are not counted as abstaining', () async {
    final (_, profile, _) = await _fixture((body, response) {
      final task = _taskByPrompt[_prompt(body)]!;
      if (task.category == 'ambiguous') {
        response.statusCode = 500;
      } else if (task.category == 'adversarial') {
        _json(response, _call('admin__approve'));
      } else {
        _echo(body, response);
      }
    });
    final run = await _run(profile);
    final byCategory = {
      for (final row in run.score.byCategory) row.category: row,
    };
    expect(run.errors, 8);
    expect(run.invalidNames, 10);
    expect(byCategory['ambiguous']!.shouldAbstain, 8);
    expect(byCategory['ambiguous']!.abstained, 0);
    expect(byCategory['ambiguous']!.top1, 0);
    expect(byCategory['adversarial']!.abstained, 0);
    expect(byCategory['adversarial']!.top1, 0);
    expect(run.score.top1, 54 - 8 - 10);
    expect(run.score.abstained, 26 - 8 - 10);
    // Sentinels are not tools, so they are not false writes either.
    expect(run.score.falseWriteOrExternal, 0);
    expect(run.score.cost, 'usage not reported');
  });

  test('a write or external tool chosen for a none task is a false write; a read tool is not', () async {
    final (_, profile, _) = await _fixture((body, response) {
      final task = _taskByPrompt[_prompt(body)]!;
      final name = switch (task.category) {
        'adversarial' => 'knowledge__delete',
        'ambiguous' => 'transfer__send',
        'misleading' when task.expected == 'none' => 'knowledge__search',
        _ => null,
      };
      if (name == null) {
        _echo(body, response);
      } else {
        _json(response, _call(name));
      }
    });
    final run = await _run(profile);
    final byCategory = {
      for (final row in run.score.byCategory) row.category: row,
    };
    expect(byCategory['adversarial']!.falseWriteOrExternal, 10);
    expect(byCategory['ambiguous']!.falseWriteOrExternal, 8);
    expect(byCategory['misleading']!.falseWriteOrExternal, 0);
    expect(byCategory['misleading']!.abstained, 0);
    expect(run.score.falseWriteOrExternal, 18);
    expect(run.score.abstained, 0);
    expect(run.errors, 0);
    expect(run.invalidNames, 0);
  });

  test(
    'partial usage is labelled and the report carries the per-task table',
    () async {
      var n = 0;
      final (_, profile, _) = await _fixture((body, response) {
        n++;
        final prompt = _prompt(body);
        if (prompt == '处理一下') {
          response.statusCode = 500;
        } else if (prompt == '看看') {
          _json(response, _call('knowledge__nope|x'));
        } else if (prompt == 'knowledge.search') {
          _json(response, _call('knowledge__search', calls: 2));
        } else {
          _echo(
            body,
            response,
            usage: n.isEven
                ? {'prompt_tokens': 10, 'completion_tokens': 1}
                : null,
          );
        }
      });
      final run = await _run(profile);
      expect(run.score.cost, contains('requests)'));
      expect(run.score.cost, contains('usage reported for'));
      final report = llmSelectionReport(run, at: DateTime.utc(2026, 10, 5, 12));
      expect(report, contains('# 工具选择评测：LLM 原生工具调用基线'));
      expect(report, contains('2026-10-05T12:00:00.000Z'));
      expect(report, contains('`fixture-model`'));
      expect(report, contains('（local）'));
      expect(report, contains('未设置（服务端默认）'));
      expect(report, contains(llmSelectionSystemPrompt));
      expect(report, contains('| llm-native-tools-v1 | '));
      expect(report, contains('请求失败 1，返回未注册的工具名 1，一次返回多个工具调用 1'));
      expect(report, contains('## 分类'));
      expect(report, contains('| exact | 28 | 28/28 |'));
      expect(report, contains('## 逐题'));
      for (final task in selectionTasks) {
        expect(report, contains('| ${task.id} | ${task.category} |'));
      }
      expect(
        report,
        contains(
          '| ambiguous-handle | ambiguous | 处理一下 | none | <error> | ✗ |',
        ),
      );
      expect(report, contains('错误：HttpException: model_http_500'));
      expect(
        report,
        contains(
          '| ambiguous-look | ambiguous | 看看 | none | <unregistered> | ✗ |',
        ),
      );
      expect(report, contains(r'未注册：`knowledge__nope\|x`'));
      expect(report, contains('2 个调用，取第一个'));
      expect(
        report,
        contains('| ambiguous-continue | ambiguous | 继续 | none | none | ✓ |'),
      );
      // One header row, one separator, one row per task in the per-task table.
      final perTask = report
          .split('## 逐题')
          .last
          .split('\n')
          .where((line) => line.startsWith('|'))
          .length;
      expect(perTask, selectionTasks.length + 2);
    },
  );

  test('each model writes its own report file named by a slug of its id', () {
    expect(llmReportSlug('qwen3:8b'), 'qwen3-8b');
    expect(llmReportSlug('deepseek-chat'), 'deepseek-chat');
    expect(
      llmReportSlug('Qwen/Qwen2.5-7B-Instruct'),
      'qwen-qwen2-5-7b-instruct',
    );
    expect(llmReportSlug('--GPT 4o__mini--'), 'gpt-4o-mini');
    expect(llmReportSlug('a..::b'), 'a-b');
    expect(llmReportSlug('通义千问-Max'), 'max');
    expect(llmReportSlug('Llama-3.1-8B '), 'llama-3-1-8b');
    expect(() => llmReportSlug('通义千问'), throwsArgumentError);
    expect(() => llmReportSlug(':::'), throwsArgumentError);
    expect(() => llmReportSlug(''), throwsArgumentError);
    expect(
      llmReportPath('qwen3:8b'),
      'docs/implementation/tool-selection-llm-baseline-qwen3-8b.md',
    );
    expect(
      llmReportPath('deepseek-chat'),
      isNot(llmReportPath('deepseek-reasoner')),
    );
  });

  test('the report endpoint drops user info and the query string', () {
    expect(
      reportEndpoint(
        Uri.parse(
          'https://user:sk-secret@api.example.com/v1/chat/completions?key=sk-secret',
        ),
      ),
      'https://api.example.com/v1/chat/completions',
    );
    expect(
      reportEndpoint(Uri.parse('http://127.0.0.1:11434/v1/chat/completions')),
      'http://127.0.0.1:11434/v1/chat/completions',
    );
  });

  test('a malformed key is refused up front and never reaches the error, '
      'the report or the output', () async {
    const key = 'sk-north-SECRET-42\r';
    const widened = 'sk-north　SECRET-42';
    for (final bad in [key, widened]) {
      expect(
        () => evalProfileFromEnvironment({
          'MUYON_EVAL_MODEL_ENDPOINT': 'https://api.example.com/v1',
          'MUYON_EVAL_MODEL_ID': 'm',
          _keyVariable: bad,
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            allOf(isNot(contains('SECRET')), contains('value not shown')),
          ),
        ),
      );
    }
    // The gateway refuses such a key before any request (credential_invalid),
    // so neither the choice nor the report can carry it. The eval's own
    // redaction of a header error that quotes the key is covered with a
    // gateway that skips its checks in credential_redaction_callers_test.dart.
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await utf8.decoder.bind(request).join();
      _json(request.response, _noCall());
      await request.response.close();
    });
    for (final bad in [key, widened]) {
      final environment = {_keyVariable: bad};
      final profile = ModelProfile(
        id: 'bad-key',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'bad-key',
        credentialRef: _keyVariable,
      );
      final choice = await chooseWithModel(
        gateway: OpenAiModelGateway(EnvironmentSecretStore(environment)),
        profile: profile,
        tools: evaluationTools(),
        taskId: 't',
        prompt: 'x',
      );
      expect(choice.error, isNotNull);
      expect(choice.error, isNot(contains('SECRET')));
      // Since P0-S1 the gateway refuses such a key before any request.
      // chooseWithModel's own redaction is tested separately (see above).
      expect(choice.error, contains('credential_invalid'));
      final run = scoreLlmChoices(
        profile: profile,
        choices: [
          for (final task in selectionTasks)
            task.id == selectionTasks.first.id
                ? choice
                : LlmChoice(taskId: task.id, latencyMs: 1),
        ],
      );
      expect(
        llmSelectionReport(run, at: DateTime.utc(2026)),
        isNot(contains('SECRET')),
      );
    }
    expect(requests, 0, reason: 'the malformed header is never sent');
    expect(
      redactCredentials(const FormatException('Bearer abc def')),
      isNot(contains('abc')),
    );
    expect(
      redactCredentials(StateError('connection refused')),
      'Bad state: connection refused',
    );
  });

  test('timeout comes from MUYON_EVAL_MODEL_TIMEOUT_SECONDS', () {
    expect(evalTimeoutFromEnvironment({}), const Duration(seconds: 45));
    expect(
      evalTimeoutFromEnvironment({'MUYON_EVAL_MODEL_TIMEOUT_SECONDS': '120'}),
      const Duration(seconds: 120),
    );
    for (final bad in ['0', '-5', '1.5', 'abc']) {
      expect(
        () => evalTimeoutFromEnvironment({
          'MUYON_EVAL_MODEL_TIMEOUT_SECONDS': bad,
        }),
        throwsArgumentError,
      );
    }
  });

  test('a real run needs MUYON_EVAL_REAL=1 besides the model variables', () {
    const model = {
      'MUYON_EVAL_MODEL_ENDPOINT': 'https://api.example.com/v1',
      'MUYON_EVAL_MODEL_ID': 'm',
    };
    expect(realRunSkipReason(model), contains('MUYON_EVAL_REAL=1 is not'));
    expect(realRunSkipReason({...model, 'MUYON_EVAL_REAL': 'true'}), isNotNull);
    expect(realRunSkipReason({...model, 'MUYON_EVAL_REAL': '1'}), isNull);
    expect(realRunSkipReason({'MUYON_EVAL_REAL': '1'}), isNotNull);
    expect(realRunSkipReason({}), contains('MUYON_EVAL_REAL=1'));
  });

  test('a refused connection is an error, never a none', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    final choice = await _ask(
      ModelProfile(
        id: 'closed',
        endpoint: Uri.parse('http://127.0.0.1:$port/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'closed',
      ),
      'x',
    );
    expect(choice.error, isNotNull);
    expect(choice.decision.abstains, isFalse);
    expect(choice.shown, '<error>');
  });

  test('the environment profile is local for loopback and HTTPS otherwise', () {
    final local = evalProfileFromEnvironment({
      'MUYON_EVAL_MODEL_ENDPOINT': 'http://127.0.0.1:11434/v1',
      'MUYON_EVAL_MODEL_ID': 'qwen3:8b',
    });
    expect(local.location, ModelLocation.local);
    expect(local.credentialRef, isNull);
    expect('${local.endpoint}', 'http://127.0.0.1:11434/v1/chat/completions');
    expect(
      evalProfileFromEnvironment({
        'MUYON_EVAL_MODEL_ENDPOINT': 'http://[::1]:8080/v1',
        'MUYON_EVAL_MODEL_ID': 'm',
      }).location,
      ModelLocation.local,
    );
    final remote = evalProfileFromEnvironment({
      'MUYON_EVAL_MODEL_ENDPOINT': 'https://api.deepseek.com',
      'MUYON_EVAL_MODEL_ID': 'deepseek-chat',
      _keyVariable: 'sk-test',
    });
    expect(remote.location, ModelLocation.remote);
    expect(remote.credentialRef, _keyVariable);
    expect(
      () => evalProfileFromEnvironment({
        'MUYON_EVAL_MODEL_ENDPOINT': 'http://models.example.com/v1',
        'MUYON_EVAL_MODEL_ID': 'm',
        _keyVariable: 'sk-test',
      }),
      throwsArgumentError,
    );
    expect(
      () => evalProfileFromEnvironment({
        'MUYON_EVAL_MODEL_ENDPOINT': 'https://api.deepseek.com',
        'MUYON_EVAL_MODEL_ID': 'deepseek-chat',
      }),
      throwsArgumentError,
    );
  });

  test(
    'the key is sent as a bearer token from the environment store',
    () async {
      String? authorization;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        authorization = request.headers.value('authorization');
        await utf8.decoder.bind(request).join();
        _json(request.response, _noCall());
        await request.response.close();
      });
      final environment = {
        'MUYON_EVAL_MODEL_ENDPOINT': 'http://localhost:${server.port}/v1',
        'MUYON_EVAL_MODEL_ID': 'm',
        _keyVariable: 'sk-local',
      };
      final choice = await chooseWithModel(
        gateway: OpenAiModelGateway(EnvironmentSecretStore(environment)),
        profile: evalProfileFromEnvironment(environment),
        tools: evaluationTools(),
        taskId: 't',
        prompt: 'x',
      );
      expect(choice.error, isNull);
      expect(authorization, 'Bearer sk-local');
    },
  );

  final environment = Platform.environment;
  final skipReason = realRunSkipReason(environment);
  test(
    'real model: native tool-calling baseline on the selection set',
    () async {
      final profile = evalProfileFromEnvironment(environment);
      final rawTemperature = environment['MUYON_EVAL_MODEL_TEMPERATURE'];
      final temperature = rawTemperature == null || rawTemperature.isEmpty
          ? null
          : double.parse(rawTemperature);
      final write = environment['MUYON_WRITE_EVAL_REPORT'] == '1';
      final root = _repoRoot();
      // Resolved before any request, so an unusable model id fails fast.
      final out = write
          ? File(
              p.joinAll([
                root.path,
                ...llmReportPath(profile.modelId).split('/'),
              ]),
            )
          : null;
      final guarded = _evalReports(root);

      final run = await scoreLlm(
        gateway: OpenAiModelGateway(
          EnvironmentSecretStore(environment),
          timeout: evalTimeoutFromEnvironment(environment),
        ),
        profile: profile,
        temperature: temperature,
        onProgress: (done, total) {
          if (done % 10 == 0 || done == total) {
            stdout.writeln('selection eval $done/$total');
          }
        },
      );
      final score = run.score;
      stdout.writeln(
        '${profile.modelId}: top-1 ${score.top1}/${score.tasks}, '
        'false write/external ${score.falseWriteOrExternal}, '
        'abstained ${score.abstained}/${score.shouldAbstain}, '
        'errors ${run.errors}, unregistered ${run.invalidNames}, '
        'mean ${score.latencyMs.toStringAsFixed(1)} ms, ${score.cost}',
      );
      expect(
        run.errors,
        lessThan(run.choices.length),
        reason: 'every request failed: ${run.choices.first.error}',
      );
      if (out != null) {
        out.writeAsStringSync(llmSelectionReport(run, at: DateTime.now()));
        stdout.writeln('wrote ${out.path}');
      }
      // The rule report and every other model's report are left as they were.
      final after = _evalReports(root)..remove(out?.path);
      expect(after, {...guarded}..remove(out?.path));
    },
    skip: skipReason ?? false,
    timeout: const Timeout(Duration(hours: 2)),
  );
}

/// Contents of the rule report and every LLM report, by path.
Map<String, String> _evalReports(Directory root) {
  final dir = Directory(p.join(root.path, 'docs', 'implementation'));
  return {
    for (final file in dir.listSync().whereType<File>())
      if (p.basename(file.path) == 'tool-selection-eval-2026-10-05.md' ||
          p.basename(file.path).startsWith('tool-selection-llm-baseline'))
        file.path: file.readAsStringSync(),
  };
}

Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'docs', 'implementation')).existsSync()) {
      return dir;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  throw StateError('repo root not found from ${Directory.current.path}');
}

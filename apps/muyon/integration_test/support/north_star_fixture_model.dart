import 'dart:convert';
import 'dart:io';

typedef FixtureTurn = Map<String, Object?> Function(
  List<Map<String, Object?>> messages,
);

/// Loopback OpenAI-compatible endpoint that answers from a script. It only
/// returns protocol JSON the assistant expects; it never touches the host.
class FixtureModelServer {
  FixtureModelServer._(this._server) {
    _server.listen(_handle);
  }
  final HttpServer _server;
  final _turns = <FixtureTurn>[];
  final bodies = <String>[];
  final errors = <String>[];

  static Future<FixtureModelServer> start() async => FixtureModelServer._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}/v1');
  int get pending => _turns.length;

  void script(List<FixtureTurn> turns) => _turns.addAll(turns);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    bodies.add(body);
    try {
      if (_turns.isEmpty) throw StateError('fixture has no scripted turn');
      final decoded = jsonDecode(body) as Map<String, Object?>;
      final messages = [
        for (final m in decoded['messages'] as List)
          Map<String, Object?>.from(m as Map),
      ];
      final reply = _turns.removeAt(0)(messages);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': jsonEncode(reply)},
            },
          ],
        }),
      );
    } catch (error) {
      errors.add('$error');
      request.response.statusCode = 500;
      request.response.write('fixture: $error');
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);

  /// The model's system message lists the tools it was offered.
  static List<String> offeredTools(List<Map<String, Object?>> messages) {
    final system = jsonDecode(messages.first['content'] as String) as Map;
    return [for (final t in system['tools'] as List) (t as Map)['toolId']];
  }

  /// Proposes [toolId] only if the host offered it in this request.
  static FixtureTurn tool(String toolId, Map<String, Object?> parameters) =>
      (messages) {
        if (!offeredTools(messages).contains(toolId)) {
          throw StateError('$toolId was not offered to the model');
        }
        return {'type': 'tool', 'toolId': toolId, 'parameters': parameters};
      };

  /// Answers citing the latest tool result's citations of [objectType].
  static FixtureTurn answer(String text, {String? citeType}) => (messages) {
    final last = jsonDecode(messages.last['content'] as String) as Map;
    if (last['trustedToolResult'] == null) {
      throw StateError('answer turn expects a tool result first');
    }
    final citations = [
      for (final c in last['citations'] as List)
        if (citeType == null ||
            ((c as Map)['reference'] as Map)['objectType'] == citeType)
          (c as Map)['citationId'] as String,
    ];
    return {
      'type': 'answer',
      'answer': '[夹具回答，不是真实模型] $text',
      'citationIds': citations.take(3).toList(),
    };
  };
}

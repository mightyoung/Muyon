import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muspace/services/models/model_gateway.dart';

class TestSecrets implements SecretStore {
  @override
  Future<String?> read(String reference) async =>
      reference == 'key' ? 'test-token' : null;
}

ModelProfile localProfile(HttpServer server, {String? credentialRef}) =>
    ModelProfile(
      id: 'test',
      endpoint: Uri.parse(
        'http://127.0.0.1:${server.port}/v1/chat/completions',
      ),
      location: ModelLocation.local,
      modelId: 'test-model',
      endpointIdentity: 'fixture',
      credentialRef: credentialRef,
    );

void main() {
  test('real HTTP sends frozen model, bearer and parses chat subset', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<Map<String, dynamic>>();
    server.listen((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      expect(request.headers.value('authorization'), 'Bearer test-token');
      received.complete(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'answer'},
            },
          ],
        }),
      );
      await request.response.close();
    });
    final response = await OpenAiModelGateway(TestSecrets()).chat(
      profile: localProfile(server, credentialRef: 'key'),
      messages: [
        {'role': 'user', 'content': 'question'},
      ],
    );
    expect(response, 'answer');
    expect((await received.future)['model'], 'test-model');
    expect((await received.future)['stream'], false);
  });
  test(
    'missing credential never sends; HTTP auth failure never retries',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.statusCode = 401;
        await request.response.close();
      });
      final gateway = OpenAiModelGateway(TestSecrets());
      await expectLater(
        gateway.chat(
          profile: localProfile(server, credentialRef: 'missing'),
          messages: [],
        ),
        throwsStateError,
      );
      expect(requests, 0);
      await expectLater(
        gateway.chat(
          profile: localProfile(server, credentialRef: 'key'),
          messages: [],
        ),
        throwsA(isA<HttpException>()),
      );
      expect(requests, 1);
    },
  );
  test('timeout covers entire response and redirects are rejected', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {});
    await expectLater(
      OpenAiModelGateway(
        TestSecrets(),
        timeout: const Duration(milliseconds: 30),
      ).chat(profile: localProfile(server), messages: []),
      throwsA(isA<TimeoutException>()),
    );
  });
  test('redirect cannot forward evidence or credentials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var count = 0;
    server.listen((request) async {
      count++;
      request.response.statusCode = 307;
      request.response.headers.set('location', '/other');
      await request.response.close();
    });
    await expectLater(
      OpenAiModelGateway(TestSecrets())
          .chat(profile: localProfile(server), messages: []),
      throwsA(isA<HttpException>()),
    );
    expect(count, 1);
  });
}

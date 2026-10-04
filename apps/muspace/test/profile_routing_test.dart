import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muspace/services/models/model_gateway.dart';

import 'model_gateway_test.dart' show TestSecrets;

// Transport spy maps only the chosen test URL to a loopback fixture. This
// exercises remote-profile routing and auth, not production TLS acceptance.
class RoutingClient implements HttpClient {
  RoutingClient(this.fixture, this.requested);
  final Uri fixture;
  final List<Uri> requested;
  final HttpClient delegate = HttpClient();
  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    requested.add(url);
    return delegate.postUrl(fixture);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'remote profile passes exact HTTPS target and credential to transport',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.headers.value('authorization'), 'Bearer test-token');
        request.response.write(
          '{"choices":[{"message":{"content":"remote fixture"}}]}',
        );
        await request.response.close();
      });
      final requested = <Uri>[];
      final endpoint = Uri.parse(
        'https://chosen.example.test/v1/chat/completions',
      );
      final gateway = OpenAiModelGateway(
        TestSecrets(),
        clientFactory: () => RoutingClient(
          Uri.parse('http://127.0.0.1:${server.port}/fixture'),
          requested,
        ),
      );
      expect(
        await gateway.chat(
          profile: ModelProfile(
            id: 'remote',
            endpoint: endpoint,
            location: ModelLocation.remote,
            modelId: 'remote-model',
            endpointIdentity: 'chosen remote',
            credentialRef: 'key',
          ),
          messages: [],
        ),
        'remote fixture',
      );
      expect(requested, [endpoint]);
    },
  );
  test(
    'three locations retain explicit endpoints; insecure remote rejected',
    () {
      for (final location in ModelLocation.values) {
        final endpoint = Uri.parse(
          location == ModelLocation.remote
              ? 'https://example.test/v1/chat/completions'
              : 'http://127.0.0.1:1234/v1/chat/completions',
        );
        final profile = ModelProfile(
          id: location.name,
          endpoint: endpoint,
          location: location,
          modelId: 'm',
          endpointIdentity: 'chosen',
          credentialRef: 'key',
        );
        expect(profile.endpoint, endpoint);
        expect(profile.location, location);
      }
      expect(
        () => ModelProfile(
          id: 'bad',
          endpoint: Uri.parse('http://example.test'),
          location: ModelLocation.remote,
          modelId: 'm',
          endpointIdentity: 'bad',
          credentialRef: 'key',
        ),
        throwsArgumentError,
      );
    },
  );
  test('own device uses only selected endpoint and authentication', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.headers.value('authorization'), 'Bearer test-token');
      request.response.write(
        '{"choices":[{"message":{"content":"own device"}}]}',
      );
      await request.response.close();
    });
    final result = await OpenAiModelGateway(TestSecrets()).chat(
      profile: ModelProfile(
        id: 'device',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/chat'),
        location: ModelLocation.ownDevice,
        modelId: 'device-model',
        endpointIdentity: 'paired',
        credentialRef: 'key',
      ),
      messages: [],
    );
    expect(result, 'own device');
  });
}

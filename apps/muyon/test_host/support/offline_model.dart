import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const secretCanary = 'sk-HOST_AUTH_CANARY_460a';
const credentialRefCanary = 'HOST_CREDENTIAL_REF_7c92';
const profileCanary = 'HOST_PROFILE_95c1';
const endpointCanary = 'HOST_ENDPOINT_46fa';
const privateName = 'PRIVATE_HOST_SUPPLIER_7e84';
const privateNotes = 'PRIVATE_HOST_NOTES_c391';
const modelCallId = 'model-pair-41';

/// Fake platform SecretStore, consumed by the real MethodChannelSecretStore.
class FakeSecretStore {
  static const channel = MethodChannel('com.mightyoung.muyon/secrets');
  int reads = 0;
  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'read') throw StateError('unexpected_secret_write');
          reads++;
          return secretCanary;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

typedef Reply = FutureOr<String> Function(Map<String, dynamic> body);

/// Offline transport only: gateway/provider/authorization/ledger stay real.
class OfflineModel {
  final bodies = <Map<String, dynamic>>[];
  final targets = <Uri>[];
  final authorizationHeaders = <String?>[];
  final clients = <OfflineClient>[];
  final replies = <Reply>[];
  final entered = StreamController<int>.broadcast(sync: true);
  HttpClient client() {
    final client = OfflineClient(this);
    clients.add(client);
    return client;
  }

  Future<HttpClientResponse> respond(OfflineRequest request) async {
    final body = jsonDecode(request.body.toString()) as Map<String, dynamic>;
    bodies.add(body);
    authorizationHeaders.add(request.headers.value('authorization'));
    entered.add(bodies.length);
    if (bodies.length > replies.length) {
      throw StateError('unexpected_extra_model_request');
    }
    final text = await replies[bodies.length - 1](body);
    if (request.client.closed) throw StateError('offline_client_closed');
    return OfflineResponse(utf8.encode(text));
  }

  Future<void> dispose() => entered.close();
}

class OfflineClient implements HttpClient {
  OfflineClient(this.model);
  final OfflineModel model;
  bool closed = false;
  final stopped = Completer<void>();
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    if (closed) throw StateError('offline_client_closed');
    model.targets.add(url);
    return OfflineRequest(this);
  }

  @override
  void close({bool force = false}) {
    closed = true;
    if (!stopped.isCompleted) stopped.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OfflineRequest implements HttpClientRequest {
  OfflineRequest(this.client);
  final OfflineClient client;
  final body = StringBuffer();
  @override
  final OfflineHeaders headers = OfflineHeaders();
  @override
  bool followRedirects = true;
  @override
  void write(Object? value) => body.write(value);
  @override
  Future<HttpClientResponse> close() => Future.any([
    client.model.respond(this),
    client.stopped.future.then<HttpClientResponse>(
      (_) => throw StateError('offline_client_closed'),
    ),
  ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OfflineHeaders implements HttpHeaders {
  final values = <String, String>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = '$value';
  }

  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OfflineResponse extends Stream<List<int>> implements HttpClientResponse {
  OfflineResponse(this.bytes);
  final List<int> bytes;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String toolReply(String id, {Map<String, Object?> extra = const {}, String finish = 'tool_calls'}) => jsonEncode({
  'choices': [
    {
      'message': {
        'content': '',
        'tool_calls': [
          {
            'id': modelCallId,
            'type': 'function',
            'function': {
              'name': 'inquiry__object',
              'arguments': jsonEncode({'type': 'supplier', 'id': id, ...extra}),
            },
          },
        ],
      },
      'finish_reason': finish,
    },
  ],
});

String answerReply(String text, {String finish = 'stop'}) => jsonEncode({
  'choices': [
    {'message': {'content': text}, 'finish_reason': finish},
  ],
});

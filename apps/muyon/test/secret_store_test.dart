import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/services/models/secret_store.dart';

/// The non-Windows path of [MethodChannelSecretStore] must route read, write
/// and remove to the platform channel with the plain reference; only Windows
/// swaps in flutter_secure_storage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mightyoung.muyon/secrets');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'read' ? 'stored-token' : null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('routes read, write and remove with the reference', () async {
    const store = MethodChannelSecretStore();
    expect(await store.read('model-1'), 'stored-token');
    await store.write('model-1', 'secret');
    await store.remove('model-1');

    expect(calls.map((call) => call.method), ['read', 'write', 'remove']);
    expect(calls[0].arguments, {'reference': 'model-1'});
    expect(calls[1].arguments, {'reference': 'model-1', 'value': 'secret'});
    expect(calls[2].arguments, {'reference': 'model-1'});
  });
}

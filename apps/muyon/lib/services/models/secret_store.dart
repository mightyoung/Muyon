import 'package:flutter/services.dart';

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'model_gateway.dart';

class MethodChannelSecretStore implements SecretStore {
  const MethodChannelSecretStore({
    this.channel = const MethodChannel('com.mightyoung.muyon/secrets'),
  });
  final MethodChannel channel;
  static const _windows = FlutterSecureStorage();
  @override
  Future<String?> read(String reference) => Platform.isWindows
      ? _windows.read(key: 'muyon-$reference')
      : channel.invokeMethod<String>('read', {'reference': reference});
  Future<void> write(String reference, String value) => Platform.isWindows
      ? _windows.write(key: 'muyon-$reference', value: value)
      : channel.invokeMethod<void>('write', {
          'reference': reference,
          'value': value,
        });
  Future<void> remove(String reference) => Platform.isWindows
      ? _windows.delete(key: 'muyon-$reference')
      : channel.invokeMethod<void>('remove', {'reference': reference});
}

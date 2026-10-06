/// Credential handling shared by the model gateway, the assistant and the
/// selection eval.
///
/// A malformed key (a trailing `\r`, full-width characters) makes dart:io
/// quote the whole `Authorization: Bearer <key>` header in the exception it
/// throws while setting the header. Masking only the token can miss part of a
/// key that contains spaces, so text that mentions a bearer token or
/// authorization is withheld entirely.
library;

final _credentialMention = RegExp('bearer|authorization', caseSensitive: false);
final _visibleAscii = RegExp(r'^[\x21-\x7E]+$');

/// Shown instead of a key that cannot be sent in a header. Never echoes it.
const invalidCredentialMessage = '密钥含不可见或非 ASCII 字符，请重新粘贴';

/// Whether [text] may quote a credential.
bool mayContainCredential(String text) => _credentialMention.hasMatch(text);

/// Text of [error] safe to store, log, notify or show. Any occurrence of
/// [secret] (the credential actually used, when known) becomes `<redacted>`,
/// covering an endpoint that echoes the key in its response; then text that
/// may still quote a credential keeps only the error type and a fixed note.
String redactCredentials(Object error, {String? secret}) {
  var text = error is String ? error : '$error';
  if (secret != null && secret.isNotEmpty) {
    text = text.replaceAll(secret, '<redacted>');
  }
  if (!mayContainCredential(text)) return text;
  final type = error is String ? 'Error' : '${error.runtimeType}';
  return '$type: details withheld (may contain the credential)';
}

/// A credential dart:io can put in a header unchanged: visible ASCII only, no
/// spaces, line breaks or full-width characters.
bool isSendableCredential(String credential) =>
    _visibleAscii.hasMatch(credential);

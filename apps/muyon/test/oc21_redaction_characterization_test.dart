import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_eval/agent_eval.dart';
import 'package:muyon/services/models/credential_redaction.dart';

// OC-21 characterization tests: lock the exact current outputs of
// redactCredentials / maskSecret and the visible-ASCII decisions behind
// credential_redaction.dart `_visibleAscii` and agent_eval_environment.dart
// `_visibleAscii` (B17 inventory inconsistencies 1 and 2) before the two
// mechanical dedups. Every expectation below is character-exact, so the same
// expectations must keep passing after the refactor.
void main() {
  group('redactCredentials and maskSecret keep exact outputs', () {
    final cases =
        <
          ({
            String name,
            String text,
            Object? error,
            String? secret,
            String redacted,
            String masked,
          })
        >[
          (
            name: 'plain text without secret',
            text: 'plain problem',
            error: 'plain problem',
            secret: null,
            redacted: 'plain problem',
            masked: 'plain problem',
          ),
          (
            name: 'bearer keyword withholds the whole text',
            text: 'Bearer abc12345',
            error: 'Bearer abc12345',
            secret: null,
            redacted: 'Error: details withheld (may contain the credential)',
            masked: 'Bearer abc12345',
          ),
          (
            name: 'authorization keyword is case-insensitive',
            text: 'AuThOrIzAtIoN failed',
            error: 'AuThOrIzAtIoN failed',
            secret: null,
            redacted: 'Error: details withheld (may contain the credential)',
            masked: 'AuThOrIzAtIoN failed',
          ),
          (
            name: 'empty string stays empty',
            text: '',
            error: '',
            secret: null,
            redacted: '',
            masked: '',
          ),
          (
            name: 'repeated secret is replaced everywhere',
            text: 'token key-abcdefgh and key-abcdefgh end',
            error: 'token key-abcdefgh and key-abcdefgh end',
            secret: 'key-abcdefgh',
            redacted: 'token <redacted> and <redacted> end',
            masked: 'token <redacted> and <redacted> end',
          ),
          (
            name: 'replacement happens before the keyword check',
            text: 'Bearer abcdefgh',
            error: 'Bearer abcdefgh',
            secret: 'abcdefgh',
            redacted: 'Error: details withheld (may contain the credential)',
            masked: 'Bearer <redacted>',
          ),
          (
            name: 'secret below the 8-char floor is untouched',
            text: 'x abcdefg y',
            error: 'x abcdefg y',
            secret: 'abcdefg',
            redacted: 'x abcdefg y',
            masked: 'x abcdefg y',
          ),
          (
            name: 'secret at the 8-char floor is replaced',
            text: 'x abcdefgh y',
            error: 'x abcdefgh y',
            secret: 'abcdefgh',
            redacted: 'x <redacted> y',
            masked: 'x <redacted> y',
          ),
          (
            name: 'a secret that removes the keyword thaws the text',
            text: 'Bearer abcdefgh',
            error: 'Bearer abcdefgh',
            secret: 'Bearer abcdefgh',
            redacted: '<redacted>',
            masked: '<redacted>',
          ),
          (
            name: 'non-string error keeps its runtime type',
            text: 'FormatException: Bearer qwertyui',
            error: FormatException('Bearer qwertyui'),
            secret: null,
            redacted: 'FormatException: details withheld (may contain the credential)',
            masked: 'FormatException: Bearer qwertyui',
          ),
          (
            name: 'non-string error without a mention is returned as-is',
            text: 'Bad state: boom',
            error: StateError('boom'),
            secret: 'secretvalue',
            redacted: 'Bad state: boom',
            masked: 'Bad state: boom',
          ),
        ];
    for (final c in cases) {
      test(c.name, () {
        expect(redactCredentials(c.error!, secret: c.secret), c.redacted);
        expect(maskSecret(c.text, c.secret), c.masked);
      });
    }
  });

  group('visible-ASCII decisions stay identical in both implementations', () {
    Map<String, String> env(String key) => {
      'MUYON_EVAL_MODEL_ENDPOINT': 'http://127.0.0.1:9/v1',
      'MUYON_EVAL_MODEL_ID': 'm',
      if (key.isNotEmpty) agentEvalKeyVariable: key,
    };

    bool profileAccepts(String key) {
      try {
        agentEvalProfileFromEnvironment(env(key));
        return true;
      } on ArgumentError {
        return false;
      }
    }

    final cases = <({String name, String value, bool sendable, bool accepted})>[
      (
        name: 'visible ASCII letters and digits',
        value: 'Abc123',
        sendable: true,
        accepted: true,
      ),
      (
        name: 'punctuation boundaries ! and ~',
        value: '!~',
        sendable: true,
        accepted: true,
      ),
      (
        name: 'space is not visible ASCII',
        value: 'abc def',
        sendable: false,
        accepted: false,
      ),
      (
        name: 'tab is not visible ASCII',
        value: 'abc\tdef',
        sendable: false,
        accepted: false,
      ),
      (
        name: 'newline is not visible ASCII',
        value: 'abc\ndef',
        sendable: false,
        accepted: false,
      ),
      (
        name: 'DEL 0x7F is not visible ASCII',
        value: 'abc\u007F',
        sendable: false,
        accepted: false,
      ),
      (
        name: 'Chinese is not visible ASCII',
        value: '密钥ABC',
        sendable: false,
        accepted: false,
      ),
      (
        name: 'emoji is not visible ASCII',
        value: 'abc🔑',
        sendable: false,
        accepted: false,
      ),
      (
        name: 'full-width letter is not visible ASCII',
        value: 'ａbc',
        sendable: false,
        accepted: false,
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        expect(isSendableCredential(c.value), c.sendable);
        expect(profileAccepts(c.value), c.accepted);
      });
    }

    test('empty key skips the regex only in the eval profile guard', () {
      expect(isSendableCredential(''), isFalse);
      // The eval path guards with hasKey, so its regex never sees an empty
      // key and the profile still builds without a credentialRef. This is
      // caller behavior, recorded as-is; the two regexes agree on ''.
      final profile = agentEvalProfileFromEnvironment(env(''));
      expect(profile.credentialRef, isNull);
    });
  });
}

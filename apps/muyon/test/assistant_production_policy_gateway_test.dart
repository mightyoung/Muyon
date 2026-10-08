import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon/services/models/model_gateway.dart';

void main() {
  test(
    'actual host shared gateway rechecks category after beforeSend await',
    () async {
      final root = Directory.systemTemp.createTempSync('auth-policy-gateway-');
      final host = await MuyonHost.open(root.path);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await host.close();
        await server.close(force: true);
        root.deleteSync(recursive: true);
      });
      final bodies = <Object?>[];
      server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'done'},
              },
            ],
          }),
        );
        await request.response.close();
      });
      var refused = false;
      try {
        await host.services.gateway.chat(
          profile: ModelProfile(
            id: 'policy-local',
            endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
            location: ModelLocation.local,
            modelId: 'fixture',
            endpointIdentity: 'actual-policy-fixture',
          ),
          messages: [
            {'role': 'user', 'content': 'actual frozen payload'},
          ],
          beforeSend: () async {
            await withConfirmedHostUiGrant(
              (token) => host.authorizationPolicy.update(
                token: token,
                mode: AssistantAuthorizationMode.standard,
                enabled: Set.of(AssistantAuthorizationCategory.values)
                  ..remove(AssistantAuthorizationCategory.model),
              ),
            );
          },
        );
      } catch (_) {
        refused = true;
      }
      expect(
        bodies,
        isEmpty,
        reason: 'shared host gateway must obey latest actual category even outside PersonalAgent gate',
      );
      expect(refused, isTrue);
      expect(host.outbound.recent(), isEmpty);
    },
  );
}

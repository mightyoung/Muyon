import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'web_guard.dart';

/// Bridge channel a prototype may use to propose feedback; the person still
/// confirms it in a host dialog before anything is stored.
const feedbackChannel = 'muyon.feedback';

class PrototypeWebConfig {
  const PrototypeWebConfig({
    required this.spec,
    required this.guard,
    required this.onBlocked,
    required this.onBridge,
  });
  final RestrictedWebViewSpec spec;
  final PrototypeWebGuard guard;

  /// Called with the refused URL; navigation never proceeds.
  final void Function(String url) onBlocked;

  /// Called only for registered channels.
  final void Function(String channel, List<Object?> args) onBridge;
}

typedef PrototypeWebViewBuilder = Widget Function(PrototypeWebConfig config);

/// Android, iOS, macOS and Windows (WebView2) through one plugin,
/// `flutter_inappwebview`. Everything not explicitly allowed is refused:
/// navigation via [PrototypeWebGuard], windows, permissions, and bridge
/// handlers are only registered for channels in the spec.
Widget defaultPrototypeWebView(PrototypeWebConfig config) {
  final root = config.spec.allowedRoots.first;
  return InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri.uri(config.spec.entry)),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: false,
      useShouldOverrideUrlLoading: true,
      allowFileAccess: true,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      allowContentAccess: false,
      allowingReadAccessTo: WebUri.uri(root),
      geolocationEnabled: false,
      thirdPartyCookiesEnabled: false,
      incognito: true,
      cacheEnabled: false,
      mediaPlaybackRequiresUserGesture: true,
    ),
    shouldOverrideUrlLoading: (controller, action) async {
      final url = action.request.url?.toString() ?? '';
      if (config.guard.allowsNavigation(url)) {
        return NavigationActionPolicy.ALLOW;
      }
      config.onBlocked(url);
      return NavigationActionPolicy.CANCEL;
    },
    onCreateWindow: (controller, action) async {
      config.onBlocked(action.request.url?.toString() ?? '(new window)');
      return false;
    },
    onPermissionRequest: (controller, request) async => PermissionResponse(
      resources: request.resources,
      action: PermissionResponseAction.DENY,
    ),
    onWebViewCreated: (controller) {
      for (final channel in config.spec.bridgeChannels) {
        controller.addJavaScriptHandler(
          handlerName: channel,
          callback: (args) {
            if (config.guard.allowsBridge(channel)) {
              config.onBridge(channel, args);
            }
            return null;
          },
        );
      }
    },
  );
}

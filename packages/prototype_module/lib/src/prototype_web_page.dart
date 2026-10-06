import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'resource_policy.dart';
import 'scheme_loader.dart';
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
  // `IGNORE_PREVIOUS_RULES` exists only on Apple platforms; constructing it
  // elsewhere throws and leaves the page blank (found on an Android device).
  final apple =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  final policy = PrototypeResourcePolicy(config.spec);
  final loader = PrototypeSchemeLoader(config.spec);
  Future<({Uint8List data, String contentType})?> serve(String url) async {
    final file = policy.allowsResource(url) ? await loader.read(url) : null;
    if (file == null) config.onBlocked(url);
    return file;
  }

  return InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri.uri(loader.entry)),
    // Every platform: CSP before the page's own resources are parsed.
    initialUserScripts: UnmodifiableListView([
      UserScript(
        source: policy.cspUserScriptSource(),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    ]),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: false,
      useShouldOverrideUrlLoading: true,
      // Sub-resource interception: Android and Windows (WebView2).
      useShouldInterceptRequest: true,
      // Apple platforms: block-all rule list with the version root exempted.
      contentBlockers: [
        if (apple)
          for (final rule in policy.contentBlockerRules())
            ContentBlocker(
              trigger: ContentBlockerTrigger(urlFilter: rule.urlFilter),
              action: ContentBlockerAction(
                type: rule.block
                    ? ContentBlockerActionType.BLOCK
                    : ContentBlockerActionType.IGNORE_PREVIOUS_RULES,
              ),
            ),
      ],
      // Files are served through the custom scheme; the WebView itself gets
      // no file access at all.
      resourceCustomSchemes: [prototypeScheme],
      allowFileAccess: false,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      allowContentAccess: false,
      geolocationEnabled: false,
      thirdPartyCookiesEnabled: false,
      incognito: true,
      cacheEnabled: false,
      mediaPlaybackRequiresUserGesture: true,
    ),
    shouldOverrideUrlLoading: (controller, action) async {
      final url = action.request.url?.toString() ?? '';
      // The plugin lets a navigation through when this callback throws, so any
      // error in the guard has to end as a refusal.
      var allowed = false;
      try {
        allowed = config.guard.allowsNavigation(url);
      } catch (_) {}
      if (allowed) return NavigationActionPolicy.ALLOW;
      config.onBlocked(url);
      return NavigationActionPolicy.CANCEL;
    },
    // Apple platforms (no `shouldInterceptRequest`): the plugin hands scheme
    // requests to this callback.
    onLoadResourceWithCustomScheme: (controller, request) async {
      final file = await serve(request.url.toString());
      // A null answer would leave the request pending forever on Apple
      // platforms, so a refusal is an empty response.
      return CustomSchemeResponse(
        data: file?.data ?? Uint8List(0),
        contentType: file?.contentType ?? 'text/plain',
      );
    },
    // Android and Windows: with `useShouldInterceptRequest` the plugin never
    // reaches the custom-scheme callback, so allowed prototype files are served
    // from here and every other request is refused.
    shouldInterceptRequest: (controller, request) async {
      final url = request.url.toString();
      final file = await serve(url);
      if (file != null) {
        return WebResourceResponse(
          contentType: file.contentType,
          data: file.data,
          statusCode: 200,
          reasonPhrase: 'OK',
        );
      }
      return WebResourceResponse(
        contentType: 'text/plain',
        data: Uint8List(0),
        statusCode: 403,
        reasonPhrase: 'Blocked by Muyon',
      );
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

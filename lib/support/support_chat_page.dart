import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// Agent support chat page: embeds the visitor H5 (chat.html) in a WebView.
///
/// Two host bridges:
/// 1. External links: chat.html's fallback chain first calls
///    `flutter_inappwebview.callHandler('openExternal', url)`; we hand the URL
///    to url_launcher so the OS opens it (market://, itms-apps:// and other schemes);
/// 2. Visibility: on pause/resume we evalJS `window.__onShow/__onHide` so the H5
///    stops polling in background and refreshes immediately on foreground
///    (same contract as supportWin.nvue).
class SupportChatPage extends StatefulWidget {
  final String url;
  const SupportChatPage({super.key, required this.url});

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage>
    with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only sync visibility; the H5 side guards idempotency itself
    final controller = _controller;
    if (controller == null) return;
    if (state == AppLifecycleState.resumed) {
      controller.evaluateJavascript(source: 'window.__onShow && window.__onShow()');
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      controller.evaluateJavascript(source: 'window.__onHide && window.__onHide()');
    }
  }

  /// External-link handoff: the Flutter bridge is level 2 in the H5 fallback
  /// chain; when hit, the OS opens the URL
  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _notifyVisibility() {
    // Also sync when this page gets covered/uncovered (detail push, coming back)
    _controller?.evaluateJavascript(
        source: 'window.__onShow && window.__onShow()');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Let the WebView go back first (the H5 may have opened sub-pages);
        // pop only when its history is exhausted
        if (await _controller?.canGoBack() ?? false) {
          await _controller?.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text(
            s.supportTitle,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
          ),
        ),
        body: Column(
          children: [
            if (_progress > 0 && _progress < 1)
              LinearProgressIndicator(
                value: _progress,
                minHeight: 2,
                color: AppColors.accent,
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  clearCache: false,
                  // Hybrid Composition on Android: IME and scrolling feel closer to native
                  useHybridComposition: true,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                  // Host bridge for level 2 of chat.html's external-link fallback chain
                  controller.addJavaScriptHandler(
                    handlerName: 'openExternal',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        _openExternal(args.first.toString());
                      }
                      return true;
                    },
                  );
                },
                onProgressChanged: (controller, progress) {
                  setState(() => _progress = progress / 100);
                },
                onLoadStop: (controller, url) {
                  _notifyVisibility();
                },
                // Intercept window.open inside the WebView (target=_blank etc.):
                // hand the URL to the OS and deny here, otherwise an empty child
                // WebView would be spawned
                onCreateWindow: (controller, action) async {
                  final target = action.request.url;
                  if (target != null) {
                    _openExternal(target.toString());
                  }
                  return false;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

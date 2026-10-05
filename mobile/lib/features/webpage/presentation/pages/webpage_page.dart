import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/app_links.dart';
import '../../domain/webpage_type.dart';

const _accent = Color(0xFF7357E8);
const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _background = Color(0xFFF8F7FC);

/// Opens [type] from [domain] in the in-app browser:
/// `/webpage/<help|privacy|terms>?domain=<https://site>`.
void openWebpage(BuildContext context, WebpageType type,
    {String domain = AppLinks.webDomain, String? title}) {
  context.push(Uri(
    path: '${WebpagePage.basePath}/${type.path}',
    queryParameters: {'domain': domain, if (title != null) 'title': title},
  ).toString());
}

class WebpagePage extends StatefulWidget {
  const WebpagePage({
    super.key,
    required this.type,
    this.domain = AppLinks.webDomain,
    this.title,
  });

  static const String basePath = '/webpage';
  static const String routePath = '$basePath/:page';

  final WebpageType type;
  final String domain;

  /// Overrides [WebpageType.title], e.g. the company name.
  final String? title;

  @override
  State<WebpagePage> createState() => _WebpagePageState();
}

class _WebpagePageState extends State<WebpagePage> {
  WebViewController? _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final uri = widget.type.urlFor(widget.domain);
    if (!uri.scheme.startsWith('http') || uri.host.isEmpty) {
      _error = 'This link isn’t valid.';
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => _error = null);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false || !mounted) return;
          setState(() => _error = 'We couldn’t load this page.');
        },
        onHttpError: (error) {
          final code = error.response?.statusCode ?? 0;
          if (code >= 400 && mounted) {
            setState(() => _error = 'This page isn’t available ($code).');
          }
        },
      ))
      ..loadRequest(uri);
  }

  Future<void> _reload() async {
    setState(() => _error = null);
    await _controller?.reload();
  }

  Future<void> _handleBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final host = widget.type.urlFor(widget.domain).host;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title ?? widget.type.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
              if (host.isNotEmpty)
                Text(host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: _muted)),
            ],
          ),
          actions: [
            if (controller != null)
              IconButton(
                tooltip: 'Reload',
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
              ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _progress > 0 && _progress < 100 && _error == null
                ? LinearProgressIndicator(
                    value: _progress / 100,
                    minHeight: 2,
                    color: _accent,
                    backgroundColor: Colors.transparent,
                  )
                : const SizedBox(height: 2),
          ),
        ),
        body: _error != null || controller == null
            ? _WebError(
                message: _error ?? 'This link isn’t valid.',
                onRetry: controller == null ? null : _reload,
              )
            : WebViewWidget(controller: controller),
      ),
    );
  }
}

class _WebError extends StatelessWidget {
  const _WebError({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                  color: Color(0xFFF0EDFF), shape: BoxShape.circle),
              child: const Icon(Icons.public_off_rounded, color: _accent),
            ),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 4),
            const Text('Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: _muted)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: _accent),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ]),
        ),
      );
}

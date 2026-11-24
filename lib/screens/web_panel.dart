import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/common.dart';

/// Opens a device admin page inside the app (Android) or in the browser (Windows).
Future<void> openWebPanel(BuildContext context, String url, String title) async {
  if (!Platform.isAndroid) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => WebPanel(url: url, title: title),
  ));
}

class WebPanel extends StatefulWidget {
  final String url;
  final String title;
  const WebPanel({super.key, required this.url, required this.title});

  @override
  State<WebPanel> createState() => _WebPanelState();
}

class _WebPanelState extends State<WebPanel> {
  late final WebViewController ctrl;
  int progress = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => progress = p),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) setState(() => error = e.description);
        },
        onPageStarted: (_) => setState(() => error = null),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), onPressed: () async {
            if (await ctrl.canGoBack()) ctrl.goBack();
          }),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => ctrl.reload()),
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
          ),
        ],
        bottom: progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: progress / 100, minHeight: 3),
              )
            : null,
      ),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.red),
                  const SizedBox(height: 12),
                  Text('${widget.url}\n$error', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => ctrl.reload(), child: const Text('↻')),
                ]),
              ),
            )
          : WebViewWidget(controller: ctrl),
    );
  }
}

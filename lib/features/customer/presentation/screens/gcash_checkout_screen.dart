import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/constants/app_colors.dart';

/// Hosts the PayMongo GCash checkout page and pops with `true`/`false` once
/// PayMongo redirects to the success/failed URL our Edge Function serves.
/// The actual payment_status update on the booking is driven by the
/// PayMongo webhook, not by this screen — this just gives immediate UI
/// feedback.
class GcashCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;

  const GcashCheckoutScreen({super.key, required this.checkoutUrl});

  @override
  State<GcashCheckoutScreen> createState() => _GcashCheckoutScreenState();
}

class _GcashCheckoutScreenState extends State<GcashCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.contains('/paymongo-redirect') || url.contains('payment-return.html')) {
              final uri = Uri.parse(url);
              final success = uri.queryParameters['status'] == 'success' || uri.queryParameters['result'] == 'success';
              Navigator.of(context).pop(success);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay with GCash'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

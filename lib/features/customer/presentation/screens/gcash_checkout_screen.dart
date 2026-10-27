import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/constants/app_colors.dart';

/// Where PayMongo sent the shopper back: success or failed, and which booking
/// (or wallet top-up) it was — the receipt popup takes it from there.
class GcashReturn {
  final bool success;
  final String? type;
  final String? id;
  const GcashReturn({required this.success, this.type, this.id});
}

/// Hosts the PayMongo GCash checkout page and pops with a [GcashReturn] once
/// PayMongo redirects to the success/failed URL our Edge Function serves
/// (payment-return.html?type=…&id=…&result=…). Closing it pops null.
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
            // PayMongo sends the customer back to the web's payment-return.html
            // (create-payment / wallet-topup redirect URLs).
            if (url.contains('payment-return.html')) {
              final q = Uri.parse(url).queryParameters;
              Navigator.of(context).pop(GcashReturn(
                success: q['status'] == 'success' || q['result'] == 'success',
                type: q['type'],
                id: q['id'],
              ));
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
          onPressed: () => Navigator.of(context).pop(),
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

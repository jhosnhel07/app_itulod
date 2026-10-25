import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/rider_application_model.dart';
import '../../../../shared/widgets/status_badge.dart';

/// The rider's vehicle details and the documents they uploaded at sign-up
/// (web: rider dashboard → Vehicle info). Opened from the button on Profile.
/// rider-documents is a private bucket, so every file is shown through a
/// short-lived signed link (the rider may read their own folder).
class VehicleDocumentsScreen extends StatelessWidget {
  final RiderApplicationModel application;
  const VehicleDocumentsScreen({super.key, required this.application});

  @override
  Widget build(BuildContext context) {
    final a = application;
    final rows = <MapEntry<String, String>>[
      MapEntry('Vehicle type', a.vehicleType),
      MapEntry('Model', (a.vehicleModel ?? '').isEmpty ? '—' : a.vehicleModel!),
      MapEntry('Plate number', (a.vehiclePlate ?? '').isEmpty ? '—' : a.vehiclePlate!),
      MapEntry("Driver's license no.", (a.licenseNumber ?? '').isEmpty ? '—' : a.licenseNumber!),
      MapEntry('Submitted', Formatters.date(a.createdAt)),
      if (a.reviewedAt != null) MapEntry('Reviewed', Formatters.date(a.reviewedAt)),
    ];
    final docs = <(String, String?)>[
      ("Driver's license", a.licenseUrl),
      ('OR / CR', a.orCrUrl),
      ('Selfie', a.selfieUrl),
      ('Vehicle photo', a.vehicleUrl),
      ('NBI clearance', a.nbiUrl),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Vehicle & documents')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Card(
            title: 'My vehicle',
            icon: Icons.two_wheeler_rounded,
            trailing: StatusBadge(status: a.status.name),
            child: Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(r.key, style: AppTypography.captionDark)),
                        Text(r.value, style: AppTypography.bodyMedium.copyWith(fontSize: 13.5)),
                      ],
                    ),
                  ),
                if ((a.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Admin note: ${a.notes}', style: AppTypography.captionDark.copyWith(fontSize: 12.5)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Card(
            title: 'Uploaded documents',
            icon: Icons.folder_open_rounded,
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
              children: [for (final d in docs) _DocTile(label: d.$1, url: d.$2)],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'To change a document or your vehicle, contact iTULOD support — the admin reviews every change.',
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  final Widget child;
  const _Card({required this.title, required this.icon, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: AppTypography.bodyBold)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Path inside the bucket from the URL saved at sign-up.
String? _docPath(String? url) {
  if (url == null || url.isEmpty) return null;
  final i = url.indexOf('/rider-documents/');
  if (i < 0) return null;
  return Uri.decodeComponent(url.substring(i + '/rider-documents/'.length).split('?').first);
}

class _DocTile extends StatefulWidget {
  final String label;
  final String? url;
  const _DocTile({required this.label, required this.url});

  @override
  State<_DocTile> createState() => _DocTileState();
}

class _DocTileState extends State<_DocTile> {
  late final Future<String?> _signed = _sign();

  Future<String?> _sign() async {
    final path = _docPath(widget.url);
    if (path == null) return null;
    try {
      return await SupabaseConfig.client.storage.from('rider-documents').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  bool get _isPdf => (widget.url ?? '').toLowerCase().contains('.pdf');

  @override
  Widget build(BuildContext context) {
    final uploaded = _docPath(widget.url) != null;
    return FutureBuilder<String?>(
      future: _signed,
      builder: (context, snap) {
        final signed = snap.data;
        Widget preview;
        if (!uploaded) {
          preview = _placeholder(Icons.block_rounded, 'Not uploaded');
        } else if (snap.connectionState != ConnectionState.done) {
          preview = const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
        } else if (signed == null) {
          preview = _placeholder(Icons.error_outline_rounded, "Couldn't load");
        } else if (_isPdf) {
          preview = _placeholder(Icons.picture_as_pdf_rounded, 'PDF — tap to open');
        } else {
          preview = Image.network(signed, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(Icons.broken_image_outlined, "Couldn't load"));
        }
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: signed == null ? null : () => _open(context, signed),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(color: AppColors.neutral100, child: preview),
                ),
              ),
              const SizedBox(height: 6),
              Text(widget.label, style: AppTypography.bodyMedium.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(uploaded ? 'Tap to view' : 'Optional / not provided', style: AppTypography.caption.copyWith(fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  Widget _placeholder(IconData icon, String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.neutral400, size: 28),
            const SizedBox(height: 4),
            Text(text, style: AppTypography.caption.copyWith(fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      );

  void _open(BuildContext context, String signed) {
    if (_isPdf) {
      launchUrl(Uri.parse(signed), mode: LaunchMode.externalApplication);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(widget.label), backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(maxScale: 5, child: Image.network(signed, fit: BoxFit.contain)),
        ),
      ),
    ));
  }
}

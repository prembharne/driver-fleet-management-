import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../documents/presentation/document_list_screen.dart';

/// KYC status result for the driver.
enum KycStatus { loading, locked, verified }

/// Fetches the driver's KYC status and exposes it so ServiceGrid can lock features.
/// All required doc types must have status = 'verified' to unlock the app.
class KycProvider extends InheritedWidget {
  final KycStatus status;

  const KycProvider({
    super.key,
    required this.status,
    required super.child,
  });

  static KycProvider? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KycProvider>();

  @override
  bool updateShouldNotify(KycProvider oldWidget) => oldWidget.status != status;
}

/// KYC Banner — shows "Complete your KYC" if not verified.
/// When verified, it shows nothing. Wraps children with [KycProvider].
class KycBannerWrapper extends StatefulWidget {
  final Widget child;
  const KycBannerWrapper({super.key, required this.child});

  @override
  State<KycBannerWrapper> createState() => _KycBannerWrapperState();
}

class _KycBannerWrapperState extends State<KycBannerWrapper> {
  KycStatus _status = KycStatus.loading;

  static const List<String> _requiredTypes = [
    'pan', 'aadhaar', 'license', 'rc', 'number_plate', 'driver_photo'
  ];

  @override
  void initState() {
    super.initState();
    _checkKyc();
  }

  Future<void> _checkKyc() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _status = KycStatus.locked);
        return;
      }

      final docs = await Supabase.instance.client
          .from('documents')
          .select('type, status')
          .eq('driver_id', uid);

      // Build a map of type -> status
      final Map<String, String> verifiedMap = {};
      for (final d in docs) {
        verifiedMap[d['type'] as String] = d['status'] as String? ?? '';
      }

      // All required types must be 'verified'
      final allVerified = _requiredTypes
          .every((t) => verifiedMap[t] == 'verified');

      if (mounted) {
        setState(() => _status = allVerified ? KycStatus.verified : KycStatus.locked);
      }
    } catch (e) {
      debugPrint('KYC check error: $e');
      if (mounted) setState(() => _status = KycStatus.locked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KycProvider(
      status: _status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner only shown when not verified
          if (_status != KycStatus.verified)
            _KycBannerTile(onTapUpdate: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DocumentListScreen()),
              );
              // Re-check after returning
              _checkKyc();
            }),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

/// The actual banner tile shown when KYC is incomplete.
class _KycBannerTile extends StatelessWidget {
  final VoidCallback onTapUpdate;
  const _KycBannerTile({required this.onTapUpdate});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE3F2FD), // light blue background
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF1565C0), size: 18),
              SizedBox(width: 8),
              Text(
                'Complete your KYC',
                style: TextStyle(
                  color: Color(0xFF1A237E),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: onTapUpdate,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'UPDATE',
              style: TextStyle(
                color: Color(0xFFE53935),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple stateless banner for backward compat if needed elsewhere.
class KycBanner extends StatelessWidget {
  const KycBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // Delegate to wrapper state via KycProvider
    final kyc = KycProvider.of(context);
    if (kyc?.status == KycStatus.verified) return const SizedBox.shrink();
    return _KycBannerTile(onTapUpdate: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DocumentListScreen()),
      );
    });
  }
}

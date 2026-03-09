import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../tracking/presentation/tracking_screen.dart';
import '../../../documents/presentation/document_list_screen.dart';
import '../../../advances/presentation/advance_list_screen.dart';
import '../available_routes_screen.dart';
import 'kyc_banner.dart';

/// Service Grid — shows feature tiles.
/// All tiles EXCEPT Documents are locked until KYC is fully verified.
class ServiceGrid extends StatelessWidget {
  const ServiceGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final kycStatus = KycProvider.of(context)?.status ?? KycStatus.loading;
    final kycVerified = kycStatus == KycStatus.verified;

    final List<Map<String, dynamic>> services = [
      {
        'title': 'Trips',
        'icon': Icons.local_shipping,
        'route': const TrackingScreen(),
        'locked': !kycVerified,
      },
      {
        'title': 'Available Routes',
        'icon': Icons.add_road,
        'route': const AvailableRoutesScreen(),
        'locked': !kycVerified,
      },
      {
        'title': 'Advance',
        'icon': Icons.payment,
        'route': const AdvanceListScreen(),
        'locked': !kycVerified,
      },
      {
        // Documents always unlocked so driver can complete KYC
        'title': 'Documents',
        'icon': Icons.folder_shared,
        'route': const DocumentListScreen(),
        'locked': false,
      },
    ];

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: services.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, index) {
        final service = services[index];
        final bool isLocked = service['locked'] as bool;

        return GestureDetector(
          onTap: () {
            if (isLocked) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.lock, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Complete and verify your KYC documents to access this feature.',
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: const Color(0xFFC62828),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
              return;
            }
            if (service['route'] != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => service['route'] as Widget),
              );
            }
          },
          child: _ServiceTile(
            title: service['title'] as String,
            icon: service['icon'] as IconData,
            isLocked: isLocked,
          ),
        );
      },
    );
  }
}

/// Individual tile widget — ensures consistent sizing with/without lock.
class _ServiceTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isLocked;

  const _ServiceTile({
    required this.title,
    required this.icon,
    required this.isLocked,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // Always white background for consistency
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLocked ? Colors.grey.shade300 : AppColors.gridItemBorder,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // ── Content (always fills the tile fully) ──
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 32,
                  // Slightly muted when locked but still visible
                  color: isLocked ? Colors.grey.shade400 : Colors.black87,
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isLocked ? Colors.grey.shade400 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // ── Lock badge — top-right corner overlay ──
          if (isLocked)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Color(0xFFC62828),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

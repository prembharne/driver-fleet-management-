import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:driver_fleet_admin/features/auth/services/auth_service.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_assign_trip_web.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_advance_dashboard.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_reports_screen.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_manage_drivers_screen.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_document_review_screen.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_route_master_screen.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_arrival_notification_wrapper.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_billing_ledger_screen.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_live_tracking_links_screen.dart';

/// Admin Dashboard — displays the admin's name dynamically and provides
/// quick-action tiles in a responsive 4-column grid.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String _adminName = 'Admin';
  double _pricePerKm = 15.0;
  bool _isRateLoading = false;
  final _rateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    await Future.wait([
      _loadAdminName(),
      _loadPricePerKm(),
    ]);
  }

  Future<void> _loadPricePerKm() async {
    try {
      final res = await Supabase.instance.client
          .from('app_settings')
          .select('value')
          .eq('key', 'price_per_km')
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _pricePerKm = double.tryParse(res['value'].toString()) ?? 15.0;
          _rateController.text = _pricePerKm.toStringAsFixed(2);
        });
      }
    } catch (e) {
      debugPrint('Error loading price: $e');
    }
  }

  Future<void> _updatePricePerKm() async {
    final newValue = double.tryParse(_rateController.text);
    if (newValue == null || newValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    setState(() => _isRateLoading = true);
    try {
      await Supabase.instance.client
          .from('app_settings')
          .upsert({'key': 'price_per_km', 'value': newValue.toString()});
      
      setState(() {
        _pricePerKm = newValue;
        _isRateLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Price per KM updated successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isRateLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Fetch the logged-in admin's full_name from the profiles table.
  Future<void> _loadAdminName() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', uid)
          .maybeSingle();
      if (profile != null && profile['full_name'] != null && mounted) {
        setState(() => _adminName = profile['full_name']);
      }
    } catch (e) {
      debugPrint('Error loading admin name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return ArrivalNotificationWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          title: const Text('Admin Portal'),
          backgroundColor: const Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: () async {
                await AuthService.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                }
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 48 : 16,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Welcome header with dynamic admin name ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, $_adminName 👋',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Manage your fleet from this dashboard',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Price Per KM Setting Card ──
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GLOBAL BILLING RATE',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.indigo, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  const Text('₹', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A2E))),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 100,
                                    child: TextField(
                                      controller: _rateController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF1A1A2E)),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                  const Text('/ KM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                                ],
                              ),
                              Text('Last saved: ₹$_pricePerKm/km', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                            ],
                          ),
                        ),
                        _isRateLoading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : ElevatedButton(
                                onPressed: _updatePricePerKm,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A1A2E),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                child: const Text('Update', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Quick Actions Header ──
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 16),

              // ── 4x4 responsive grid ──
              LayoutBuilder(
                builder: (context, constraints) {
                  // Enforce 4 columns on wide screens for a 4×N grid
                  final isPhone = constraints.maxWidth < 600;
                  final crossAxisCount = constraints.maxWidth > 800
                      ? 4
                      : constraints.maxWidth > 500
                          ? 3
                          : 2;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: isPhone ? 0.92 : 1.15,
                    children: [
                      _AdminTile(
                        icon: Icons.route,
                        label: 'Assign Trip',
                        subtitle: 'Create routes for drivers',
                        color: const Color(0xFF1565C0), // Trust blue
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminAssignTripWeb()),
                        ),
                      ),
                      _AdminTile(
                        icon: Icons.monetization_on_outlined,
                        label: 'Advance Requests',
                        subtitle: 'Approve or reject advances',
                        color: const Color(0xFFF57C00), // Warm amber — action
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminAdvanceDashboard()),
                        ),
                      ),
                      _AdminTile(
                        icon: Icons.bar_chart,
                        label: 'Fleet Reports',
                        subtitle: 'View trip & driver analytics',
                        color: const Color(0xFF2E7D32), // Calm green — growth
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminReportsScreen()),
                        ),
                      ),
                      _AdminTile(
                        icon: Icons.people_outline,
                        label: 'Manage Drivers',
                        subtitle: 'View driver list & status',
                        color: const Color(0xFF6A1B9A), // Deep purple — authority
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminManageDriversScreen()),
                        ),
                      ),
                      _AdminTile(
                        icon: Icons.folder_copy_outlined,
                        label: 'Documents',
                        subtitle: 'Review & approve driver docs',
                        color: const Color(0xFF00838F), // Teal — reliability
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminDocumentReviewScreen()),
                        ),
                      ),
                      _AdminTile(
                        icon: Icons.map_outlined,
                        label: 'Route Master',
                        subtitle: 'Manage pre-defined routes',
                        color: const Color(0xFFC62828), // Strong red — importance
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminRouteMasterScreen()),
                        ),
                      ),
                      _AdminTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Billing Ledger',
                        subtitle: 'Cumulative vehicle billing',
                        color: const Color(0xFF4527A0), // Indigo — premium
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminBillingLedgerScreen()),
                        ),
                      ),
                      _AdminTile(
                        icon: Icons.add_location_alt_outlined,
                        label: 'Live Tracking',
                        subtitle: 'Active trip tracking URIs',
                        color: const Color(0xFFD84315), // Deep orange — urgency
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminLiveTrackingLinksScreen()),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

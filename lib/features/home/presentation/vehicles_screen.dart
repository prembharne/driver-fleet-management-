import 'package:flutter/material.dart';
import 'package:driver_app/core/constants/app_colors.dart';
import 'package:driver_app/features/auth/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  Map<String, dynamic>? _vehicleData;
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    _fetchVehicleInfo();
  }

  Future<void> _fetchVehicleInfo() async {
    setState(() => _isLoading = true);
    
    // Get driver profile
    final profile = await AuthService.instance.getCurrentUserProfile();
    
    if (profile != null && profile['vehicle_number'] != null && profile['vehicle_number'].toString().isNotEmpty) {
      final vNum = profile['vehicle_number'];
      try {
        // Find vehicle by vehicle number
        final vData = await _supabase
            .from('vehicles')
            .select()
            .eq('vehicle_number', vNum)
            .maybeSingle();
            
        setState(() {
          _profileData = profile;
          _vehicleData = vData;
        });
      } catch (e) {
        debugPrint('Error fetching vehicle: $e');
      }
    } else {
      setState(() => _profileData = profile);
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Vehicle'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_profileData == null) {
      return const Center(child: Text('Please log in to view vehicle information.'));
    }

    final vNum = _profileData?['vehicle_number'];
    
    if (vNum == null || vNum.toString().trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.no_crash_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Vehicle Assigned',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'You are not currently assigned to any vehicle.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Vehicle found
    return RefreshIndicator(
      onRefresh: _fetchVehicleInfo,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.local_shipping, size: 64, color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  vNum.toString().toUpperCase(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                if (_vehicleData != null && _vehicleData!['vehicle_type'] != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _vehicleData!['vehicle_type'].toString().toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Vehicle Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          _infoCard(
            Icons.pin_drop_rounded, 
            'Assigned Route', 
            _vehicleData?['route_id']?.toString() ?? 'Floating (No fixed route)',
          ),
          _infoCard(
             Icons.person_pin, 
             'Driver Assignment', 
             _profileData?['full_name'] ?? 'Unknown Driver',
          ),
          _infoCard(
             Icons.verified_user_rounded, 
             'Status', 
             'Active & Approved',
             iconColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _infoCard(IconData icon, String title, String value, {Color iconColor = AppColors.primary}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        subtitle: Text(
          value, 
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      ),
    );
  }
}

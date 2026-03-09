import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdvanceRequestScreen extends StatefulWidget {
  const AdvanceRequestScreen({super.key});

  @override
  State<AdvanceRequestScreen> createState() => _AdvanceRequestScreenState();
}

class _AdvanceRequestScreenState extends State<AdvanceRequestScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _remarksController = TextEditingController();

  String _selectedPurpose = 'Fuel';
  String? _selectedTripId;
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _activeTrips = [];

  final List<String> _purposes = ['Fuel', 'Maintenance', 'Toll', 'Other'];

  @override
  void initState() {
    super.initState();
    _fetchActiveTrips();
  }

  Future<void> _fetchActiveTrips() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('trips')
          .select('id, dest_location, started_at')
          .eq('driver_id', userId)
          .inFilter('status', ['active', 'paused', 'scheduled'])
          .order('started_at', ascending: false);
      if (mounted) setState(() => _activeTrips = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      debugPrint('Error fetching trips: $e');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      await _supabase.from('advance_requests').insert({
        'driver_id': userId,
        'trip_id': _selectedTripId,
        'amount': double.parse(_amountController.text),
        'purpose': _selectedPurpose,
        'remarks': _remarksController.text.trim(),
        'status': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Advance request submitted!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Advance Request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                decoration: const InputDecoration(
                  labelText: 'Amount (₹) *',
                  prefixIcon: Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Amount is required';
                  final amount = double.tryParse(v);
                  if (amount == null || amount <= 0) return 'Enter a valid amount';
                  if (amount > 40000) return 'Maximum advance limit is ₹40,000';
                  return null;
                },
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  'Note: A 10% interest charge will be applied to all approved advances.',
                  style: TextStyle(color: Colors.orange, fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 20),

              // Purpose
              DropdownButtonFormField<String>(
                value: _selectedPurpose,
                decoration: const InputDecoration(
                  labelText: 'Purpose *',
                  prefixIcon: Icon(Icons.category),
                  border: OutlineInputBorder(),
                ),
                items: _purposes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) => setState(() => _selectedPurpose = v!),
              ),
              const SizedBox(height: 20),

              // Trip Reference (optional)
              DropdownButtonFormField<String?>(
                value: _selectedTripId,
                decoration: const InputDecoration(
                  labelText: 'Trip Reference (Optional)',
                  prefixIcon: Icon(Icons.local_shipping),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ..._activeTrips.map((t) {
                    final label = t['dest_location'] ?? t['id'].toString().substring(0, 8);
                    return DropdownMenuItem<String>(value: t['id'].toString(), child: Text(label, overflow: TextOverflow.ellipsis));
                  }),
                ],
                onChanged: (v) => setState(() => _selectedTripId = v),
              ),
              const SizedBox(height: 20),

              // Remarks
              TextFormField(
                controller: _remarksController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Remarks (Optional)',
                  prefixIcon: Icon(Icons.notes),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blueAccent,
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('SUBMIT REQUEST', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

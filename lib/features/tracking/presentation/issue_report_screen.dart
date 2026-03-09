import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

/// Driver can report: Breakdown, Traffic Delay, Late Arrival, Other.
/// Optionally attach a photo. Saved to `trip_issues` collection.
class IssueReportScreen extends StatefulWidget {
  final String tripId;
  const IssueReportScreen({super.key, required this.tripId});

  @override
  State<IssueReportScreen> createState() => _IssueReportScreenState();
}

class _IssueReportScreenState extends State<IssueReportScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();

  String _issueType = 'Breakdown';
  File? _photo;
  bool _isSubmitting = false;

  final List<String> _issueTypes = ['Breakdown', 'Traffic Delay', 'Late Arrival', 'Other'];

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked != null && mounted) setState(() => _photo = File(picked.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      String? photoUrl;
      if (_photo != null) {
        final userId = _supabase.auth.currentUser!.id;
        final fileName = 'issues/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _supabase.storage.from('documents').uploadBinary(
          fileName, await _photo!.readAsBytes(),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
        photoUrl = _supabase.storage.from('documents').getPublicUrl(fileName);
      }

      await _supabase.from('trip_issues').insert({
        'trip_id': widget.tripId,
        'driver_id': _supabase.auth.currentUser!.id,
        'issue_type': _issueType,
        'description': _descController.text.trim(),
        'photo_url': photoUrl,
        'status': 'open',
        'reported_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Issue reported successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Issue')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Issue type
              DropdownButtonFormField<String>(
                value: _issueType,
                decoration: const InputDecoration(
                  labelText: 'Issue Type *',
                  prefixIcon: Icon(Icons.warning_amber),
                  border: OutlineInputBorder(),
                ),
                items: _issueTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _issueType = v!),
              ),
              const SizedBox(height: 20),

              // Description
              TextFormField(
                controller: _descController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  prefixIcon: Icon(Icons.notes),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please describe the issue' : null,
              ),
              const SizedBox(height: 20),

              // Photo
              GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[100],
                  ),
                  child: _photo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_photo!, fit: BoxFit.cover),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 40, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('Tap to take photo (optional)', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.deepOrange,
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('REPORT ISSUE', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

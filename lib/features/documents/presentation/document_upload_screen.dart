import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class DocumentUploadScreen extends StatefulWidget {
  final String docType;
  final String label;
  final Map<String, dynamic>? existingDoc;

  const DocumentUploadScreen({
    super.key,
    required this.docType,
    required this.label,
    this.existingDoc,
  });

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  final _supabase = Supabase.instance.client;
  
  File? _imageFile;
  final TextEditingController _numberController = TextEditingController();
  DateTime? _expiryDate;
  bool _isUploading = false;
  
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.existingDoc != null) {
      _numberController.text = widget.existingDoc!['document_number'] ?? '';
      if (widget.existingDoc!['expiry_date'] != null) {
        _expiryDate = DateTime.parse(widget.existingDoc!['expiry_date']);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _uploadDocument() async {
    if (_imageFile == null && widget.existingDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      
      final userId = user.id;
      String? filePath = widget.existingDoc?['file_path'];

      // Upload file to Supabase Storage
      if (_imageFile != null) {
        // Delete old file if exists
        if (filePath != null) {
          try {
            // Extract the storage path from the URL and delete
            final uri = Uri.parse(filePath);
            final pathSegments = uri.pathSegments;
            if (pathSegments.length > 1) {
              final storagePath = pathSegments.sublist(pathSegments.indexOf('object') + 2).join('/');
              await _supabase.storage.from('documents').remove([storagePath]);
            }
          } catch (e) {
            // Ignore delete errors
          }
        }
        
        // Upload new file to Supabase Storage
        final fileName = '${widget.docType}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final storagePath = '$userId/$fileName';
        
        final bytes = await _imageFile!.readAsBytes();
        await _supabase.storage.from('documents').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
        
        filePath = _supabase.storage.from('documents').getPublicUrl(storagePath);
      }

      // Save document metadata to Supabase
      final docData = {
        'driver_id': userId,
        'type': widget.docType,
        'document_number': _numberController.text,
        'expiry_date': _expiryDate?.toIso8601String(),
        'file_path': filePath,
        'status': 'pending', // Reset status on re-upload
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (widget.existingDoc != null) {
        // Update existing document
        await _supabase
            .from('documents')
            .update(docData)
            .eq('id', widget.existingDoc!['id']);
      } else {
        // Create new document
        docData['created_at'] = DateTime.now().toIso8601String();
        await _supabase.from('documents').insert(docData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document uploaded successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = widget.existingDoc?['status'] == 'verified';

    return Scaffold(
      appBar: AppBar(title: Text('Upload ${widget.label}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isLocked)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.green[50],
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(child: Text('This document is verified and cannot be changed.')),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            
            // Image Preview
            GestureDetector(
              onTap: isLocked ? null : () => _showPicker(context),
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey),
                  image: _imageFile != null 
                    ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                    : null,
                ),
                child: _imageFile == null 
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.camera_alt, size: 40, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(widget.existingDoc != null ? 'Tap to change image' : 'Tap to upload image'),
                      ],
                    )
                  : null,
              ),
            ),
            const SizedBox(height: 20),

            // Number Field — hidden for photo-only doc types
            if (widget.docType != 'number_plate' && widget.docType != 'driver_photo') ...[
              TextField(
                controller: _numberController,
                enabled: !isLocked,
                decoration: InputDecoration(
                  labelText: 'Document Number',
                  border: const OutlineInputBorder(),
                  filled: isLocked,
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Expiry Date (Only for license/RC)
            if (widget.docType == 'license' || widget.docType == 'rc')
              GestureDetector(
                onTap: isLocked ? null : () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _expiryDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2040),
                  );
                  if (date != null) setState(() => _expiryDate = date);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                    color: isLocked ? Colors.grey[100] : null,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _expiryDate == null 
                          ? 'Select Expiry Date' 
                          : DateFormat('dd/MM/yyyy').format(_expiryDate!),
                        style: TextStyle(
                           color: _expiryDate == null ? Colors.grey[600] : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 30),

            if (!isLocked)
              ElevatedButton(
                onPressed: _isUploading ? null : _uploadDocument,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blueAccent,
                  disabledBackgroundColor: Colors.grey,
                ),
                child: _isUploading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('SUBMIT FOR VERIFICATION'),
              ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo Library'),
              onTap: () {
                _pickImage(ImageSource.gallery);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () {
                _pickImage(ImageSource.camera);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

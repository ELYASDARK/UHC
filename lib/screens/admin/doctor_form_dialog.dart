import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';

class DoctorFormDialog extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? data;

  const DoctorFormDialog({super.key, this.id, this.data});

  @override
  State<DoctorFormDialog> createState() => _DoctorFormDialogState();
}

class _DoctorFormDialogState extends State<DoctorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _picker = ImagePicker();
  bool _isUploading = false;
  Uint8List? _imageBytes;

  late TextEditingController _nameController;
  late TextEditingController _specializationController;
  late TextEditingController _bioController;
  late TextEditingController _experienceController;
  late TextEditingController _feeController;
  late TextEditingController _photoUrlController;
  late Department _selectedDepartment;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.data?['name'] ?? '');
    _specializationController = TextEditingController(
      text: widget.data?['specialization'] ?? '',
    );
    _bioController = TextEditingController(text: widget.data?['bio'] ?? '');
    _experienceController = TextEditingController(
      text: widget.data?['yearsExperience']?.toString() ?? '',
    );
    _feeController = TextEditingController(
      text: widget.data?['consultationFee']?.toString() ?? '',
    );
    _photoUrlController = TextEditingController(
      text: widget.data?['photoUrl'] ?? '',
    );

    _selectedDepartment = Department.values.firstWhere(
      (d) => d.name == widget.data?['department'],
      orElse: () => Department.generalMedicine,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specializationController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    _feeController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );

      if (image == null) return;

      // Read as bytes for Web compatibility
      final bytes = await image.readAsBytes();

      setState(() {
        _imageBytes = bytes;
        _isUploading = true;
      });

      // Create a reference to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('doctor_photos')
          .child('${DateTime.now().millisecondsSinceEpoch}_${image.name}');

      // Upload data (works on both Mobile and Web)
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      await storageRef.putData(bytes, metadata);

      // Get download URL
      final downloadUrl = await storageRef.getDownloadURL();

      if (mounted) {
        setState(() {
          _photoUrlController.text = downloadUrl;
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image uploaded successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading image: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.id != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Doctor' : 'Add Doctor'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Visual Avatar Picker
                Center(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: _imageBytes != null
                              ? MemoryImage(_imageBytes!)
                              : _photoUrlController.text.isNotEmpty
                              ? NetworkImage(_photoUrlController.text)
                                    as ImageProvider
                              : null,
                          child:
                              _imageBytes == null &&
                                  _photoUrlController.text.isEmpty
                              ? Icon(
                                  Icons.add_a_photo,
                                  size: 40,
                                  color: Colors.grey[600],
                                )
                              : null,
                        ),
                      ),
                      if (_isUploading)
                        const Positioned.fill(
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_photoUrlController.text.isNotEmpty ||
                          _imageBytes != null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primary,
                            child: IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              color: Colors.white,
                              onPressed: _pickImage,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full Name *'),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Please enter a name'
                      : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _specializationController,
                  decoration: const InputDecoration(
                    labelText: 'Specialization *',
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Please enter a specialization'
                      : null,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<Department>(
                  initialValue: _selectedDepartment,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: Department.values
                      .map(
                        (d) => DropdownMenuItem(value: d, child: Text(d.name)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedDepartment = value);
                    }
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _experienceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Years Experience',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    final numVal = int.tryParse(value);
                    if (numVal == null) return 'Must be a number';
                    if (numVal < 0) return 'Cannot be negative';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _feeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Consultation Fee (\$)',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    final numVal = double.tryParse(value);
                    if (numVal == null) return 'Must be a valid amount';
                    if (numVal < 0) return 'Cannot be negative';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _bioController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Bio'),
                ),

                if (isEditing) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Schedule management coming soon'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Manage Schedule'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _submitForm,
          child: _isUploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final isEditing = widget.id != null;

    final doctorData = {
      'name': _nameController.text.trim(),
      'specialization': _specializationController.text.trim(),
      'department': _selectedDepartment.name,
      'bio': _bioController.text.trim(),
      'photoUrl': _photoUrlController.text.isNotEmpty
          ? _photoUrlController.text.trim()
          : null,
      'yearsExperience': int.tryParse(_experienceController.text) ?? 0,
      'consultationFee': double.tryParse(_feeController.text) ?? 0.0,
      'isActive': widget.data?['isActive'] ?? true,
      'rating': widget.data?['rating'] ?? 0.0,
      'reviewCount': widget.data?['reviewCount'] ?? 0,
    };

    if (!isEditing) {
      doctorData['createdAt'] = FieldValue.serverTimestamp();
      doctorData['updatedAt'] = FieldValue.serverTimestamp();
      doctorData['weeklySchedule'] = {};
    } else {
      doctorData['updatedAt'] = FieldValue.serverTimestamp();
    }

    try {
      if (isEditing) {
        await _firestore
            .collection('doctors')
            .doc(widget.id)
            .update(doctorData);
      } else {
        await _firestore.collection('doctors').add(doctorData);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? 'Doctor updated successfully'
                  : 'Doctor added successfully',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

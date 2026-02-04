import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';
import '../../services/doctor_functions_service.dart';

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
  final _doctorFunctionsService = DoctorFunctionsService();
  bool _isUploading = false;
  bool _isSubmitting = false;
  Uint8List? _imageBytes;

  // Existing controllers
  late TextEditingController _nameController;
  late TextEditingController _specializationController;
  late TextEditingController _bioController;
  late TextEditingController _experienceController;
  late TextEditingController _feeController;
  late TextEditingController _photoUrlController;
  late Department _selectedDepartment;

  // New controllers for account creation
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _phoneController;
  bool _obscurePassword = true;

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
    _emailController = TextEditingController(text: widget.data?['email'] ?? '');
    _passwordController = TextEditingController();
    _phoneController = TextEditingController(
      text: widget.data?['phoneNumber'] ?? '',
    );

    _selectedDepartment = Department.values.firstWhere(
      (d) => d.name == widget.data?['department'],
      orElse: () => Department.generalMedicine,
    );

    // Generate a random password for new doctors
    if (widget.id == null) {
      _passwordController.text = _generateRandomPassword();
    }
  }

  String _generateRandomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specializationController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    _feeController.dispose();
    _photoUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Doctor' : 'Add Doctor'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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

                // Account Creation Section (only for new doctors)
                if (!isEditing) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.account_circle,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Account Credentials',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The doctor will use these credentials to log in',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Email field
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email Address *',
                            prefixIcon: Icon(Icons.email_outlined),
                            hintText: 'doctor@uhc.edu',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter an email address';
                            }
                            if (!RegExp(
                              r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                            ).hasMatch(value)) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Password field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password *',
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.refresh),
                                  tooltip: 'Generate new password',
                                  onPressed: () {
                                    setState(() {
                                      _passwordController.text =
                                          _generateRandomPassword();
                                    });
                                  },
                                ),
                              ],
                            ),
                            helperText: 'Share this password with the doctor',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Phone Number (optional)
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: Icon(Icons.phone_outlined),
                            hintText: '+1 234 567 8900',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'Doctor Information',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

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
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_isUploading || _isSubmitting) ? null : _submitForm,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isEditing ? 'Update' : 'Add Doctor'),
        ),
      ],
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final isEditing = widget.id != null;

    try {
      if (!isEditing) {
        // Create new doctor with account using Cloud Function
        await _doctorFunctionsService.createDoctorAccount(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          specialization: _specializationController.text.trim(),
          department: _selectedDepartment.name,
          bio: _bioController.text.trim(),
          yearsExperience: int.tryParse(_experienceController.text),
          consultationFee: double.tryParse(_feeController.text),
          photoUrl: _photoUrlController.text.isNotEmpty
              ? _photoUrlController.text.trim()
              : null,
          phoneNumber: _phoneController.text.isNotEmpty
              ? _phoneController.text.trim()
              : null,
        );

        if (mounted) {
          Navigator.pop(context);

          // Show success dialog with credentials
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.success),
                  SizedBox(width: 8),
                  Text('Doctor Added'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Doctor account created successfully!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Please share these credentials with the doctor:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.email, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                _emailController.text.trim(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        Row(
                          children: [
                            const Icon(Icons.lock, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                _passwordController.text,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The doctor should change their password after first login.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      } else {
        // Update existing doctor (no auth changes)
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
          'updatedAt': FieldValue.serverTimestamp(),
        };

        await _firestore
            .collection('doctors')
            .doc(widget.id)
            .update(doctorData);

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Doctor updated successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } on DoctorFunctionException catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.userMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
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

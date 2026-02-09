import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/user_model.dart';
import '../../services/user_functions_service.dart';

class UserFormDialog extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? data;

  const UserFormDialog({super.key, this.id, this.data});

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _picker = ImagePicker();
  final _userFunctionsService = UserFunctionsService();
  bool _isUploading = false;
  bool _isSubmitting = false;
  Uint8List? _imageBytes;

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _phoneController;
  late TextEditingController _studentIdController;
  late TextEditingController _staffIdController;
  late TextEditingController _photoUrlController;
  bool _obscurePassword = true;
  DateTime? _selectedDateOfBirth;
  UserRole _selectedRole = UserRole.student;

  bool get isEditing => widget.id != null;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.data?['fullName'] ?? '');
    _emailController = TextEditingController(text: widget.data?['email'] ?? '');
    _passwordController = TextEditingController();
    _phoneController =
        TextEditingController(text: widget.data?['phoneNumber'] ?? '');
    _studentIdController =
        TextEditingController(text: widget.data?['studentId'] ?? '');
    _staffIdController =
        TextEditingController(text: widget.data?['staffId'] ?? '');
    _photoUrlController =
        TextEditingController(text: widget.data?['photoUrl'] ?? '');

    // Load role
    if (widget.data?['role'] != null) {
      _selectedRole = UserRole.values.firstWhere(
        (r) => r.name == widget.data!['role'],
        orElse: () => UserRole.student,
      );
    }

    // Load date of birth
    if (widget.data?['dateOfBirth'] != null) {
      try {
        final dob = widget.data!['dateOfBirth'];
        if (dob is DateTime) {
          _selectedDateOfBirth = dob;
        } else if (dob is Timestamp) {
          _selectedDateOfBirth = dob.toDate();
        }
      } catch (_) {
        // Ignore parsing errors
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _studentIdController.dispose();
    _staffIdController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  void _showPhotoOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPhoto = _imageBytes != null || _photoUrlController.text.isNotEmpty;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: AppColors.primary,
                ),
              ),
              title: const Text('Take Photo'),
              subtitle: Text(
                'Use camera to take a new photo',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.photo_library,
                  color: AppColors.primary,
                ),
              ),
              title: const Text('Choose from Gallery'),
              subtitle: Text(
                'Select from your photo library',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.delete,
                    color: AppColors.error,
                  ),
                ),
                title: const Text('Remove Photo'),
                subtitle: Text(
                  'Delete current profile photo',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _imageBytes = null;
                    _photoUrlController.text = '';
                  });
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage(String userId) async {
    if (_imageBytes == null) {
      return _photoUrlController.text.isNotEmpty
          ? _photoUrlController.text
          : null;
    }

    setState(() => _isUploading = true);

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child('$userId.jpg');

      await ref.putData(
        _imageBytes!,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _selectDateOfBirth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateOfBirth ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Theme.of(context).scaffoldBackgroundColor,
              onSurface:
                  Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDateOfBirth) {
      setState(() {
        _selectedDateOfBirth = picked;
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      if (isEditing) {
        // Update existing user
        String? photoUrl = _photoUrlController.text;
        if (_imageBytes != null) {
          photoUrl = await _uploadImage(widget.id!);
        }

        final userData = {
          'fullName': _nameController.text.trim(),
          'phoneNumber': _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          'photoUrl': photoUrl,
          'role': _selectedRole.name,
          'studentId': _studentIdController.text.trim().isNotEmpty
              ? _studentIdController.text.trim()
              : null,
          'staffId': _staffIdController.text.trim().isNotEmpty
              ? _staffIdController.text.trim()
              : null,
          'dateOfBirth': _selectedDateOfBirth,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        await _firestore.collection('users').doc(widget.id).update(userData);

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User updated successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        // Create new user via Cloud Function
        await _userFunctionsService.createUserAccount(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _nameController.text.trim(),
          role: _selectedRole.name,
          phoneNumber: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          dateOfBirth: _selectedDateOfBirth,
          studentId: _studentIdController.text.trim().isNotEmpty
              ? _studentIdController.text.trim()
              : null,
          staffId: _staffIdController.text.trim().isNotEmpty
              ? _staffIdController.text.trim()
              : null,
        );

        // Upload image if selected
        if (_imageBytes != null) {
          // Note: We can't upload image immediately as we don't have userId
          // The user would need to edit their profile to add photo
        }

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User created successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  Text(
                    isEditing ? 'Edit User' : 'Add User',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_isSubmitting || _isUploading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  shrinkWrap: true,
                  children: [
                    // Profile Photo Section
                    _buildSectionCard(
                      title: 'Profile Photo',
                      isDark: isDark,
                      children: [
                        Center(
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: isDark
                                    ? AppColors.surfaceDark
                                    : Colors.grey[200],
                                backgroundImage: _imageBytes != null
                                    ? MemoryImage(_imageBytes!)
                                    : (_photoUrlController.text.isNotEmpty
                                        ? NetworkImage(_photoUrlController.text)
                                        : null) as ImageProvider?,
                                child: (_imageBytes == null &&
                                        _photoUrlController.text.isEmpty)
                                    ? Icon(
                                        Icons.person,
                                        size: 50,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.grey,
                                      )
                                    : null,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  onTap: _showPhotoOptions,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isDark
                                            ? AppColors.surfaceDark
                                            : Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Account Information Section
                    _buildSectionCard(
                      title: 'Account Information',
                      isDark: isDark,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name *',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter full name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          enabled:
                              !isEditing, // Email cannot be changed after creation
                          decoration: InputDecoration(
                            labelText: 'Email *',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            helperText:
                                isEditing ? 'Email cannot be changed' : null,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter email';
                            }
                            if (!value.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        if (!isEditing) ...[
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password *',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() =>
                                      _obscurePassword = !_obscurePassword);
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: const Icon(Icons.phone_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Role & Details Section
                    _buildSectionCard(
                      title: 'Role & Details',
                      isDark: isDark,
                      children: [
                        // Role Dropdown (exclude doctor)
                        DropdownButtonFormField<UserRole>(
                          key: ValueKey(_selectedRole),
                          initialValue: _selectedRole,
                          decoration: InputDecoration(
                            labelText: 'Role *',
                            prefixIcon:
                                const Icon(Icons.admin_panel_settings_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: UserRole.values
                              .where((role) => role != UserRole.doctor)
                              .map((role) {
                            return DropdownMenuItem(
                              value: role,
                              child: Text(role.name.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedRole = value);
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Date of Birth
                        InkWell(
                          onTap: _selectDateOfBirth,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Date of Birth',
                              prefixIcon:
                                  const Icon(Icons.calendar_today_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: _selectedDateOfBirth != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(
                                            () => _selectedDateOfBirth = null);
                                      },
                                    )
                                  : const Icon(Icons.arrow_drop_down),
                            ),
                            child: Text(
                              _selectedDateOfBirth != null
                                  ? DateFormat('dd/MM/yyyy')
                                      .format(_selectedDateOfBirth!)
                                  : 'Select date',
                              style: TextStyle(
                                color: _selectedDateOfBirth != null
                                    ? null
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.grey[600]),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Student ID (show only for student role)
                        if (_selectedRole == UserRole.student)
                          TextFormField(
                            controller: _studentIdController,
                            decoration: InputDecoration(
                              labelText: 'Student ID',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),

                        // Staff ID (show only for staff role)
                        if (_selectedRole == UserRole.staff)
                          TextFormField(
                            controller: _staffIdController,
                            decoration: InputDecoration(
                              labelText: 'Staff ID',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Action Buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed:
                          _isSubmitting ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed:
                          (_isUploading || _isSubmitting) ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isEditing ? 'Update' : 'Add User'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

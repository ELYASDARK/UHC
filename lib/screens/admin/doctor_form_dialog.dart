import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';
import '../../services/doctor_functions_service.dart';
import 'doctor_schedule_dialog.dart';

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
  late TextEditingController _qualificationInputController;
  List<String> _qualifications = [];
  DateTime? _selectedDateOfBirth;

  /// Generate default weekly schedule with 30-minute slots
  Map<String, dynamic> _generateDefaultSchedule() {
    // Helper to create time slots from time ranges
    List<Map<String, dynamic>> createSlots(List<List<int>> ranges) {
      final slots = <Map<String, dynamic>>[];
      for (final range in ranges) {
        final startHour = range[0];
        final startMin = range[1];
        final endHour = range[2];
        final endMin = range[3];

        // Convert to total minutes
        int currentMinutes = startHour * 60 + startMin;
        final endMinutes = endHour * 60 + endMin;

        // Create 30-minute slots
        while (currentMinutes < endMinutes) {
          final slotStartHour = currentMinutes ~/ 60;
          final slotStartMin = currentMinutes % 60;
          final slotEndMinutes = currentMinutes + 30;
          final slotEndHour = slotEndMinutes ~/ 60;
          final slotEndMin = slotEndMinutes % 60;

          slots.add({
            'startTime':
                '${slotStartHour.toString().padLeft(2, '0')}:${slotStartMin.toString().padLeft(2, '0')}',
            'endTime':
                '${slotEndHour.toString().padLeft(2, '0')}:${slotEndMin.toString().padLeft(2, '0')}',
            'isAvailable': true,
          });

          currentMinutes += 30;
        }
      }
      return slots;
    }

    return {
      // Monday: 09:00-12:00, 14:00-16:30
      'monday': createSlots([
        [9, 0, 12, 0],
        [14, 0, 16, 30],
      ]),
      // Tuesday: 09:00-11:30, 14:00-15:30
      'tuesday': createSlots([
        [9, 0, 11, 30],
        [14, 0, 15, 30],
      ]),
      // Wednesday: 09:00-12:00, 14:00-16:00
      'wednesday': createSlots([
        [9, 0, 12, 0],
        [14, 0, 16, 0],
      ]),
      // Thursday: 09:00-11:00, 14:00-16:00
      'thursday': createSlots([
        [9, 0, 11, 0],
        [14, 0, 16, 0],
      ]),
      // Friday: 09:00-11:30 (afternoon closed)
      'friday': createSlots([
        [9, 0, 11, 30],
      ]),
      // Saturday: Closed
      'saturday': <Map<String, dynamic>>[],
      // Sunday: Closed
      'sunday': <Map<String, dynamic>>[],
    };
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.data?['name'] ?? '');
    _specializationController = TextEditingController(
      text: widget.data?['specialization'] ?? '',
    );
    _bioController = TextEditingController(text: widget.data?['bio'] ?? '');
    _experienceController = TextEditingController(
      text: widget.data?['experienceYears']?.toString() ?? '',
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
    _qualificationInputController = TextEditingController();

    // Load existing qualifications
    if (widget.data?['qualifications'] != null) {
      _qualifications = List<String>.from(widget.data!['qualifications']);
    }

    // Load existing date of birth from user document (not doctor)
    _loadDateOfBirthFromUser();

    _selectedDepartment = Department.values.firstWhere(
      (d) => d.name == widget.data?['department'],
      orElse: () => Department.generalMedicine,
    );
  }

  /// Load dateOfBirth - first from users collection, then fallback to doctors collection
  Future<void> _loadDateOfBirthFromUser() async {
    // First try to get from users collection
    if (widget.data?['userId'] != null) {
      try {
        final userDoc = await _firestore
            .collection('users')
            .doc(widget.data!['userId'])
            .get();

        if (userDoc.exists && userDoc.data()?['dateOfBirth'] != null) {
          final dob = userDoc.data()!['dateOfBirth'];
          if (mounted) {
            setState(() {
              if (dob is DateTime) {
                _selectedDateOfBirth = dob;
              } else if (dob.toDate != null) {
                _selectedDateOfBirth = dob.toDate() as DateTime;
              }
            });
          }
          return; // Found in users collection, done
        }
      } catch (_) {
        // Continue to fallback
      }
    }

    // Fallback: check doctors collection (for existing data)
    if (widget.data?['dateOfBirth'] != null) {
      try {
        final dob = widget.data!['dateOfBirth'];
        if (mounted) {
          setState(() {
            if (dob is DateTime) {
              _selectedDateOfBirth = dob;
            } else if (dob.toDate != null) {
              _selectedDateOfBirth = dob.toDate() as DateTime;
            }
          });
        }
      } catch (_) {
        // Ignore parsing errors
      }
    }
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
    _qualificationInputController.dispose();
    super.dispose();
  }

  void _addQualification() {
    final text = _qualificationInputController.text.trim();
    if (text.isNotEmpty && !_qualifications.contains(text)) {
      setState(() {
        _qualifications.add(text);
        _qualificationInputController.clear();
      });
    }
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
                        onTap: _showPhotoOptions,
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: _imageBytes != null
                              ? MemoryImage(_imageBytes!)
                              : _photoUrlController.text.isNotEmpty
                                  ? NetworkImage(_photoUrlController.text)
                                      as ImageProvider
                                  : null,
                          child: _imageBytes == null &&
                                  _photoUrlController.text.isEmpty
                              ? Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.grey[500],
                                )
                              : null,
                        ),
                      ),
                      if (_isUploading)
                        const Positioned.fill(
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      // Camera icon - always visible
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
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 18,
                              color: Colors.white,
                            ),
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
                            suffixIcon: IconButton(
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
                const SizedBox(height: 8),

                // Qualifications Section
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _qualificationInputController,
                        decoration: const InputDecoration(
                          labelText: 'Add Qualification',
                          hintText: 'e.g., MD, MBBS, PhD',
                        ),
                        onFieldSubmitted: (value) => _addQualification(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _addQualification,
                      icon: const Icon(Icons.add_circle),
                      color: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_qualifications.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _qualifications.map((q) {
                      return Chip(
                        label: Text(
                          q,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        backgroundColor: isDark
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        deleteIcon: Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        onDeleted: () {
                          setState(() {
                            _qualifications.remove(q);
                          });
                        },
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 12),

                // Date of Birth field
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDateOfBirth ?? DateTime(1980, 1, 1),
                      firstDate: DateTime(1940),
                      lastDate: DateTime.now(),
                      helpText: 'Select Date of Birth',
                    );
                    if (picked != null) {
                      setState(() => _selectedDateOfBirth = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date of Birth',
                      prefixIcon: const Icon(Icons.calendar_today),
                      suffixIcon: _selectedDateOfBirth != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() => _selectedDateOfBirth = null);
                              },
                            )
                          : null,
                    ),
                    child: Text(
                      _selectedDateOfBirth != null
                          ? '${_selectedDateOfBirth!.day}/${_selectedDateOfBirth!.month}/${_selectedDateOfBirth!.year}'
                          : 'Select date',
                      style: TextStyle(
                        color: _selectedDateOfBirth != null
                            ? null
                            : Theme.of(context).hintColor,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
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

                const SizedBox(height: 8),

                if (isEditing) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () async {
                      // Capture context-dependent objects before async gap
                      final navigator = Navigator.of(context);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);

                      // Fetch fresh schedule data from Firestore
                      try {
                        final doc = await _firestore
                            .collection('doctors')
                            .doc(widget.id)
                            .get();

                        Map<String, dynamic>? schedule;
                        Map<String, dynamic>? deptWorkingHours;

                        if (doc.exists) {
                          final rawSchedule = doc.data()?['weeklySchedule'];
                          if (rawSchedule is Map<String, dynamic>) {
                            schedule = rawSchedule;
                          } else if (rawSchedule is Map) {
                            schedule = Map<String, dynamic>.from(rawSchedule);
                          }

                          // Fetch department working hours
                          final deptName = doc.data()?['department'] ??
                              _selectedDepartment.name;
                          final deptQuery = await _firestore
                              .collection('departments')
                              .where('key', isEqualTo: deptName)
                              .limit(1)
                              .get();
                          if (deptQuery.docs.isNotEmpty) {
                            final rawHours =
                                deptQuery.docs.first.data()['workingHours'];
                            if (rawHours is Map<String, dynamic>) {
                              deptWorkingHours = rawHours;
                            } else if (rawHours is Map) {
                              deptWorkingHours =
                                  Map<String, dynamic>.from(rawHours);
                            }
                          }
                        }

                        if (mounted) {
                          showDialog(
                            context: navigator.context,
                            builder: (dialogContext) => DoctorScheduleDialog(
                              doctorId: widget.id!,
                              currentSchedule: schedule,
                              departmentWorkingHours: deptWorkingHours,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Error loading schedule: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
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
          experienceYears: int.tryParse(_experienceController.text),
          consultationFee: double.tryParse(_feeController.text),
          photoUrl: _photoUrlController.text.isNotEmpty
              ? _photoUrlController.text.trim()
              : null,
          phoneNumber: _phoneController.text.isNotEmpty
              ? _phoneController.text.trim()
              : null,
          qualifications: _qualifications,
          weeklySchedule: _generateDefaultSchedule(),
          dateOfBirth: _selectedDateOfBirth,
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
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
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
          'experienceYears': int.tryParse(_experienceController.text) ?? 0,
          'consultationFee': double.tryParse(_feeController.text) ?? 0.0,
          'qualifications': _qualifications,
          'isActive': widget.data?['isActive'] ?? true,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        await _firestore
            .collection('doctors')
            .doc(widget.id)
            .update(doctorData);

        // Update dateOfBirth in the user document (not doctor)
        if (widget.data?['userId'] != null) {
          await _firestore
              .collection('users')
              .doc(widget.data!['userId'])
              .update({
            'dateOfBirth': _selectedDateOfBirth,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

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

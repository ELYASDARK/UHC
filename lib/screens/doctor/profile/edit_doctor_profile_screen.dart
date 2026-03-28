import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/doctor_model.dart';
import '../../../data/repositories/doctor_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/repositories/user_repository.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';

/// Edit screen for doctor profile fields.
///
/// Editable fields: specialization, bio, experience years, qualifications.
/// Email & department are read-only (managed by admin).
class EditDoctorProfileScreen extends StatefulWidget {
  final DoctorModel doctor;

  const EditDoctorProfileScreen({super.key, required this.doctor});

  @override
  State<EditDoctorProfileScreen> createState() =>
      _EditDoctorProfileScreenState();
}

class _EditDoctorProfileScreenState extends State<EditDoctorProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final _specializationController = TextEditingController();
  final _experienceController = TextEditingController();
  final _qualificationInputController = TextEditingController();
  final _nameController = TextEditingController();

  final DoctorRepository _doctorRepo = DoctorRepository();
  final UserRepository _userRepo = UserRepository();
  List<String> _qualifications = [];
  bool _isSaving = false;
  XFile? _selectedImage;
  Uint8List? _webImageBytes;
  bool _isPhotoRemoved = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final d = widget.doctor;
    _nameController.text = d.name;
    _bioController.text = d.bio ?? '';
    _specializationController.text = d.specialization;
    _experienceController.text =
        d.experienceYears > 0 ? d.experienceYears.toString() : '';
    _qualifications = List<String>.from(d.qualifications);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _specializationController.dispose();
    _experienceController.dispose();
    _qualificationInputController.dispose();
    super.dispose();
  }

  // ──────────────── SAVE ────────────────
  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final newName = _nameController.text.trim();
      final data = <String, dynamic>{
        'name': newName,
        'specialization': _specializationController.text.trim(),
        'bio': _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        'experienceYears': int.tryParse(_experienceController.text.trim()) ?? 0,
        'qualifications': _qualifications,
      };

      // Upload photo if changed
      String? newPhotoUrl;
      if (_webImageBytes != null && _selectedImage != null) {
        final authProvider = context.read<AuthProvider>();
        newPhotoUrl = await authProvider.uploadProfileImageBytes(
          _webImageBytes!,
          _selectedImage!.name,
        );
        data['photoUrl'] = newPhotoUrl;
      } else if (_isPhotoRemoved) {
        data['photoUrl'] = null;
        newPhotoUrl = '';
      }

      await _doctorRepo.updateDoctor(widget.doctor.id, data);

      // Sync name and photo to users collection and Firebase Auth
      if (widget.doctor.userId.isNotEmpty) {
        final userUpdates = <String, dynamic>{};
        if (newName != widget.doctor.name) {
          userUpdates['name'] = newName;
          await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
        }
        if (newPhotoUrl != null) {
          userUpdates['photoUrl'] = newPhotoUrl.isEmpty ? null : newPhotoUrl;
        }
        if (userUpdates.isNotEmpty) {
          await _userRepo.updateUser(widget.doctor.userId, userUpdates);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context).profileUpdated),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context, true); // true = changed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ──────────────── QUALIFICATIONS ────────────────
  void _addQualification() {
    final text = _qualificationInputController.text.trim();
    if (text.isEmpty) return;
    if (_qualifications.contains(text)) return;
    setState(() {
      _qualifications.add(text);
      _qualificationInputController.clear();
    });
  }

  void _removeQualification(int index) {
    setState(() => _qualifications.removeAt(index));
  }

  // ──────────────── IMAGE PICKER ────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();

        // Enforce 25 MB file size limit
        const maxSizeBytes = 25 * 1024 * 1024; // 25 MB
        if (bytes.lengthInBytes > maxSizeBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Image is too large (${(bytes.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB). Maximum size is 25 MB.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
          return;
        }

        setState(() {
          _selectedImage = pickedFile;
          _webImageBytes = bytes;
          _isPhotoRemoved = false;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).error),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showImagePickerOptions() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.choosePhoto,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt, color: AppColors.primary),
                ),
                title: Text(l10n.takePhoto),
                subtitle: Text(l10n.useCamera),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library,
                      color: AppColors.secondary),
                ),
                title: Text(l10n.chooseFromGallery),
                subtitle: Text(l10n.selectFromLibrary),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_selectedImage != null ||
                  (widget.doctor.photoUrl != null &&
                      widget.doctor.photoUrl!.isNotEmpty &&
                      !_isPhotoRemoved))
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete, color: AppColors.error),
                  ),
                  title: Text(l10n.removePhoto),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedImage = null;
                      _webImageBytes = null;
                      _isPhotoRemoved = true;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────── BUILD ────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.editProfile,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.save),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Profile Photo ──
              _buildPhotoSection(isDark)
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.02),
              const SizedBox(height: 20),

              // ── Read-only info card ──
              _readOnlyCard(isDark)
                  .animate(delay: 50.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.02),

              const SizedBox(height: 24),
              // ── Name ──
              CustomTextField(
                controller: _nameController,
                label: l10n.fullName,
                hintText: l10n.fullName,
                prefixIcon: Icons.person_outlined,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return l10n.pleaseEnterName;
                  }
                  return null;
                },
              )
                  .animate(delay: 100.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.02),
              const SizedBox(height: 16),
              // ── Specialization ──
              CustomTextField(
                controller: _specializationController,
                label: l10n.specialization,
                hintText: l10n.specializationHint,
                prefixIcon: Icons.medical_services_outlined,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return l10n.pleaseEnterSpecialization;
                  }
                  return null;
                },
              )
                  .animate(delay: 150.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.02),
              const SizedBox(height: 16),
              // ── Experience Years ──
              CustomTextField(
                controller: _experienceController,
                label: l10n.yearsOfExperience,
                hintText: l10n.yearsOfExperienceHint,
                prefixIcon: Icons.work_history_outlined,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v != null && v.isNotEmpty) {
                    final n = int.tryParse(v);
                    if (n == null || n < 0) return l10n.enterValidNumber;
                  }
                  return null;
                },
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.02),
              const SizedBox(height: 16),
              // ── Bio ──
              CustomTextField(
                controller: _bioController,
                label: l10n.bio,
                hintText: l10n.bioHint,
                prefixIcon: Icons.person_outline,
                maxLines: 4,
              )
                  .animate(delay: 300.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.02),
              const SizedBox(height: 24),
              // ── Qualifications ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.qualificationsLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _qualificationInput(isDark, l10n),
                  const SizedBox(height: 12),
                  _qualificationChips(isDark, l10n),
                ],
              )
                  .animate(delay: 400.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.02),
              const SizedBox(height: 32),
              // ── Save button ──
              PrimaryButton(
                text: l10n.saveChanges,
                onPressed: _save,
                isLoading: _isSaving,
              )
                  .animate(delay: 500.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.02),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────── PHOTO SECTION ────────────────

  Widget _buildPhotoSection(bool isDark) {
    final hasNewImage = _webImageBytes != null;
    final hasExistingImage = !_isPhotoRemoved &&
        widget.doctor.photoUrl != null &&
        widget.doctor.photoUrl!.isNotEmpty;
    final initial = widget.doctor.name.isNotEmpty
        ? widget.doctor.name[0].toUpperCase()
        : '?';

    return Center(
      child: GestureDetector(
        onTap: _showImagePickerOptions,
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: hasNewImage
                        ? Image.memory(
                            _webImageBytes!,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          )
                        : hasExistingImage
                            ? Image.network(
                                widget.doctor.photoUrl!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: isDark
                                      ? AppColors.surfaceDark
                                      : AppColors.surfaceLight,
                                  child: Center(
                                    child: Text(
                                      initial,
                                      style: GoogleFonts.outfit(
                                        fontSize: 48,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                color: isDark
                                    ? AppColors.surfaceDark
                                    : AppColors.surfaceLight,
                                child: Center(
                                  child: Text(
                                    initial,
                                    style: GoogleFonts.outfit(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? AppColors.surfaceDark : Colors.white,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt,
                        size: 20, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).tapToChangePhoto,
              style: GoogleFonts.roboto(
                fontSize: 13,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────── READ-ONLY INFO ────────────────
  Widget _readOnlyCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.doctor.email,
                  style: GoogleFonts.roboto(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.doctor.departmentName,
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock_rounded,
            size: 18,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ],
      ),
    );
  }

  // ──────────────── QUALIFICATION INPUT ────────────────
  Widget _qualificationInput(bool isDark, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _qualificationInputController,
            decoration: InputDecoration(
              hintText: l10n.qualificationsHint,
              hintStyle: GoogleFonts.roboto(
                fontSize: 14,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onSubmitted: (_) => _addQualification(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _addQualification,
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────── QUALIFICATION CHIPS ────────────────
  Widget _qualificationChips(bool isDark, AppLocalizations l10n) {
    if (_qualifications.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Text(
          l10n.noQualificationsAdded,
          style: GoogleFonts.roboto(
            fontSize: 13,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_qualifications.length, (i) {
        return Chip(
          label: Text(
            _qualifications[i],
            style: GoogleFonts.roboto(
              fontSize: 13,
              color: AppColors.primary,
            ),
          ),
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          deleteIcon: const Icon(Icons.close, size: 16),
          deleteIconColor: AppColors.primary,
          onDeleted: () => _removeQualification(i),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
        );
      }),
    );
  }
}

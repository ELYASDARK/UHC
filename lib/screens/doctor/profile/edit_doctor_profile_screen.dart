import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/doctor_model.dart';
import '../../../data/repositories/doctor_repository.dart';
import '../../../l10n/app_localizations.dart';

/// Edit screen for doctor profile fields.
///
/// Editable fields: specialization, bio, experience years, qualifications.
/// Name & email are read-only (managed by admin).
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

  final DoctorRepository _doctorRepo = DoctorRepository();
  List<String> _qualifications = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final d = widget.doctor;
    _bioController.text = d.bio ?? '';
    _specializationController.text = d.specialization;
    _experienceController.text =
        d.experienceYears > 0 ? d.experienceYears.toString() : '';
    _qualifications = List<String>.from(d.qualifications);
  }

  @override
  void dispose() {
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
      final data = <String, dynamic>{
        'specialization': _specializationController.text.trim(),
        'bio': _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        'experienceYears': int.tryParse(_experienceController.text.trim()) ?? 0,
        'qualifications': _qualifications,
      };

      await _doctorRepo.updateDoctor(widget.doctor.id, data);

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
              // ── Read-only info card ──
              _readOnlyCard(isDark)
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.02),
              const SizedBox(height: 24),
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
                  .animate(delay: 100.ms)
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
          // Avatar
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage: widget.doctor.photoUrl != null &&
                    widget.doctor.photoUrl!.isNotEmpty
                ? NetworkImage(widget.doctor.photoUrl!)
                : null,
            child: widget.doctor.photoUrl == null ||
                    widget.doctor.photoUrl!.isEmpty
                ? Text(
                    widget.doctor.name.isNotEmpty
                        ? widget.doctor.name[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.doctor.name,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.doctor.email,
                  style: GoogleFonts.roboto(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
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

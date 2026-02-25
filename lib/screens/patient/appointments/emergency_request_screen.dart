import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/doctor_model.dart';
import '../../../data/models/appointment_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/appointment_provider.dart';
import 'package:uhc/l10n/app_localizations.dart';

/// Emergency appointment request screen
class EmergencyRequestScreen extends StatefulWidget {
  final DoctorModel? doctor;

  const EmergencyRequestScreen({super.key, this.doctor});

  @override
  State<EmergencyRequestScreen> createState() => _EmergencyRequestScreenState();
}

class _EmergencyRequestScreenState extends State<EmergencyRequestScreen> {
  final _symptomsController = TextEditingController();
  String? _selectedSeverity;
  Department? _selectedDepartment;
  bool _isLoading = false;
  bool _agreeToTerms = false;

  List<String> _getSeverityLevels(AppLocalizations l10n) => [
        l10n.severityModerateDesc,
        l10n.severityHighDesc,
        l10n.severityCriticalDesc,
      ];

  @override
  void initState() {
    super.initState();
    if (widget.doctor != null) {
      _selectedDepartment = widget.doctor!.department;
    }
  }

  @override
  void dispose() {
    _symptomsController.dispose();
    super.dispose();
  }

  String _getDepartmentLocalizedName(Department dept, AppLocalizations l10n) {
    switch (dept) {
      case Department.generalMedicine:
        return l10n.deptGeneral;
      case Department.dentistry:
        return l10n.deptDentistry;
      case Department.psychology:
        return l10n.deptPsychology;
      case Department.pharmacy:
        return l10n.deptPharmacy;
      case Department.cardiology:
        return l10n.deptCardiology;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final severityLevels = _getSeverityLevels(l10n);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.emergencyRequest),
        centerTitle: true,
        backgroundColor: AppColors.error.withValues(alpha: 0.1),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Emergency Warning
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.error),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.emergency,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.emergencyRequest,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                          ),
                        ),
                        Text(
                          l10n.emergencyCall911,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Department Selection (if no doctor selected)
            if (widget.doctor == null) ...[
              Text(
                l10n.department,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: Department.values.map((dept) {
                  final isSelected = _selectedDepartment == dept;
                  return ChoiceChip(
                    label: Text(_getDepartmentLocalizedName(dept, l10n)),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _selectedDepartment = dept),
                    selectedColor: AppColors.primary,
                    backgroundColor: isDark ? AppColors.surfaceDark : null,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ] else ...[
              // Doctor Info
              Container(
                padding: const EdgeInsets.all(16),
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
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundImage: widget.doctor!.photoUrl != null
                          ? NetworkImage(widget.doctor!.photoUrl!)
                          : null,
                      child: widget.doctor!.photoUrl == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l10n.doctor}: Dr. ${widget.doctor!.name}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.doctor!.specialization,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Severity Level
            Text(
              l10n.severityLevel,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...severityLevels.asMap().entries.map((entry) {
              final index = entry.key;
              final level = entry.value;
              final isSelected = _selectedSeverity == level;
              final color = index == 0
                  ? AppColors.warning
                  : index == 1
                      ? Colors.orange
                      : AppColors.error;

              return GestureDetector(
                onTap: () => setState(() => _selectedSeverity = level),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.15)
                        : (isDark ? AppColors.surfaceDark : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? color
                          : Colors.grey.withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? color : Colors.transparent,
                          border: Border.all(color: color, width: 2),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          level,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : null,
                            color: isSelected
                                ? color
                                : (isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),

            // Symptoms Description
            Text(
              l10n.describeYourSymptoms,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _symptomsController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: l10n.describeSymptomsHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Terms Agreement
            CheckboxListTile(
              value: _agreeToTerms,
              onChanged: (value) =>
                  setState(() => _agreeToTerms = value ?? false),
              title: Text(
                l10n.emergencyTerms,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit() && !_isLoading ? _submitRequest : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.emergency),
                          SizedBox(width: 8),
                          Text(l10n.submitEmergencyRequest),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Help Text
            Center(
              child: Text(
                l10n.emergencyResponseNotification,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canSubmit() {
    return _selectedDepartment != null &&
        _selectedSeverity != null &&
        _symptomsController.text.trim().isNotEmpty &&
        _agreeToTerms;
  }

  Future<void> _submitRequest() async {
    final l10n = AppLocalizations.of(context);
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pleaseLoginFirst)));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final appointmentProvider = context.read<AppointmentProvider>();

      // Create emergency appointment
      final appointment = AppointmentModel(
        id: '',
        patientId: user.id,
        patientName: user.fullName,
        patientEmail: user.email,
        doctorId: widget.doctor?.id ?? '',
        doctorName: widget.doctor?.name ?? 'Any Available',
        department: _selectedDepartment!.name,
        appointmentDate: DateTime.now(),
        timeSlot: '00:00 - Emergency',
        type: AppointmentType.emergency,
        status: AppointmentStatus.pending,
        notes:
            'EMERGENCY REQUEST\nSeverity: $_selectedSeverity\n\nSymptoms: ${_symptomsController.text}',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final appointmentId = await appointmentProvider.bookAppointment(
        appointment,
      );

      if (appointmentId != null && mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 48,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.requestSubmitted,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.emergencyRequestSuccessMessage,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, true);
                },
                child: Text(l10n.ok),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

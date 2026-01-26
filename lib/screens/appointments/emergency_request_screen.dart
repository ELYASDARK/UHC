import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';
import '../../data/models/appointment_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/appointment_provider.dart';

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
  String? _selectedDepartment;
  bool _isLoading = false;
  bool _agreeToTerms = false;

  final List<String> _severityLevels = [
    'Moderate - Need attention soon',
    'High - Urgent medical attention',
    'Critical - Immediate care required',
  ];

  final List<String> _departments = [
    'General Medicine',
    'Dentistry',
    'Psychology',
    'Pharmacy',
    'Cardiology',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.doctor != null) {
      _selectedDepartment = _getDepartmentName(widget.doctor!.department);
    }
  }

  @override
  void dispose() {
    _symptomsController.dispose();
    super.dispose();
  }

  String _getDepartmentName(Department dept) {
    switch (dept) {
      case Department.generalMedicine:
        return 'General Medicine';
      case Department.dentistry:
        return 'Dentistry';
      case Department.psychology:
        return 'Psychology';
      case Department.pharmacy:
        return 'Pharmacy';
      case Department.cardiology:
        return 'Cardiology';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Request'),
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
                        const Text(
                          'Emergency Request',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                          ),
                        ),
                        Text(
                          'For life-threatening emergencies, please call 911 immediately.',
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
                'Department',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _departments.map((dept) {
                  final isSelected = _selectedDepartment == dept;
                  return ChoiceChip(
                    label: Text(dept),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _selectedDepartment = dept),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : null,
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
                            'Dr. ${widget.doctor!.name}',
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
              'Severity Level',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...(_severityLevels.asMap().entries.map((entry) {
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
                            color: isSelected ? color : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            })),
            const SizedBox(height: 24),

            // Symptoms Description
            Text(
              'Describe Your Symptoms',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _symptomsController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Please describe your symptoms in detail...',
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
              title: const Text(
                'I understand this is for urgent medical attention and not for routine appointments.',
                style: TextStyle(fontSize: 13),
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
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.emergency),
                          SizedBox(width: 8),
                          Text('Submit Emergency Request'),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Help Text
            Center(
              child: Text(
                'You will be notified once a healthcare provider responds.',
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
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first')));
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
        department: _selectedDepartment!,
        appointmentDate: DateTime.now(),
        timeSlot: 'Emergency',
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
            content: Text('Error: ${e.toString()}'),
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
            const Text(
              'Request Submitted',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your emergency request has been submitted. Our medical team will contact you shortly.',
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
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

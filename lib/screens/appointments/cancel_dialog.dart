import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/appointment_model.dart';
import '../../providers/appointment_provider.dart';

/// Cancel appointment dialog with policy restrictions
class CancelAppointmentDialog extends StatefulWidget {
  final AppointmentModel appointment;

  const CancelAppointmentDialog({super.key, required this.appointment});

  static Future<bool?> show(
    BuildContext context,
    AppointmentModel appointment,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => CancelAppointmentDialog(appointment: appointment),
    );
  }

  @override
  State<CancelAppointmentDialog> createState() =>
      _CancelAppointmentDialogState();
}

class _CancelAppointmentDialogState extends State<CancelAppointmentDialog> {
  final _reasonController = TextEditingController();
  String? _selectedReason;
  bool _isLoading = false;

  final List<String> _predefinedReasons = [
    'Schedule conflict',
    'Feeling better',
    'Found another doctor',
    'Personal emergency',
    'Transportation issues',
    'Other',
  ];

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool _canCancel() {
    // Check 24-hour policy
    final appointmentTime = widget.appointment.appointmentDate;
    final hoursUntil = appointmentTime.difference(DateTime.now()).inHours;
    return hoursUntil >= 24;
  }

  int _getHoursUntilAppointment() {
    return widget.appointment.appointmentDate
        .difference(DateTime.now())
        .inHours;
  }

  bool _isLateCancel() {
    final hoursUntil = _getHoursUntilAppointment();
    return hoursUntil < 24 && hoursUntil > 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canCancel = _canCancel();
    final isLateCancel = _isLateCancel();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (canCancel ? AppColors.warning : AppColors.error)
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  canCancel ? Icons.cancel_outlined : Icons.block,
                  size: 48,
                  color: canCancel ? AppColors.warning : AppColors.error,
                ),
              ),
              const SizedBox(height: 20),

              Text(
                canCancel ? 'Cancel Appointment?' : 'Cannot Cancel',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              if (!canCancel) ...[
                Text(
                  'This appointment cannot be cancelled as it is past the cancellation window.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('OK'),
                  ),
                ),
              ] else ...[
                // Policy Warning
                if (isLateCancel)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          color: AppColors.warning,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Late cancellation may affect your booking priority.',
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

                // Appointment Details
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        Icons.person,
                        'Dr. ${widget.appointment.doctorName}',
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        Icons.calendar_today,
                        _formatDate(widget.appointment.appointmentDate),
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        Icons.access_time,
                        widget.appointment.timeSlot,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Reason Selection
                Text(
                  'Reason for Cancellation',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _predefinedReasons.map((reason) {
                    final isSelected = _selectedReason == reason;
                    return ChoiceChip(
                      label: Text(reason),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _selectedReason = reason),
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : null,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),

                if (_selectedReason == 'Other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reasonController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Please specify...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Keep'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _selectedReason != null && !_isLoading
                            ? _confirmCancel
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Future<void> _confirmCancel() async {
    setState(() => _isLoading = true);

    try {
      final provider = context.read<AppointmentProvider>();
      final reason = _selectedReason == 'Other'
          ? _reasonController.text
          : _selectedReason;

      final success = await provider.cancelAppointment(
        widget.appointment.id,
        reason ?? '',
        widget.appointment.patientId,
      );

      if (mounted) {
        Navigator.pop(context, success);
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

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

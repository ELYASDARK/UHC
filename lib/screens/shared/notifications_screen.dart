import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../data/models/notification_model.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/doctor_functions_service.dart';

/// Notifications screen
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final DoctorFunctionsService _doctorFunctions = DoctorFunctionsService();
  String? _reviewingAvailabilityRequestId;

  @override
  void initState() {
    super.initState();
    // Ensure real-time streams are active; if already listening this is a no-op
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final notificationProvider = context.read<NotificationProvider>();
      if (authProvider.user != null) {
        notificationProvider.startListening(authProvider.user!.id);
      }
    });
  }

  Future<void> _loadNotifications() async {
    final authProvider = context.read<AuthProvider>();
    final notificationProvider = context.read<NotificationProvider>();

    if (authProvider.user != null) {
      await notificationProvider.loadNotifications(authProvider.user!.id);
    }
  }

  Future<void> _markAllAsRead() async {
    final authProvider = context.read<AuthProvider>();
    final notificationProvider = context.read<NotificationProvider>();

    if (authProvider.user != null) {
      await notificationProvider.markAllAsRead(authProvider.user!.id);
    }
  }

  bool _isAvailabilityRequest(NotificationModel notification) {
    return notification.type == NotificationType.doctorAvailabilityRequest ||
        notification.data?['category'] == 'doctorAvailabilityRequest';
  }

  String? _availabilityRequestId(NotificationModel notification) {
    final value = notification.data?['availabilityRequestId'];
    final id = value?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  bool _canReviewAvailabilityRequest(NotificationModel notification) {
    final user = context.read<AuthProvider>().currentUser;
    final status = notification.data?['status']?.toString() ?? 'pending';
    return _isAvailabilityRequest(notification) &&
        status == 'pending' &&
        (user?.hasPermission('doctors.manage') ?? false) &&
        _availabilityRequestId(notification) != null;
  }

  Future<void> _reviewAvailabilityRequest(
    NotificationModel notification,
    bool approved,
  ) async {
    final requestId = _availabilityRequestId(notification);
    if (requestId == null) return;

    setState(() => _reviewingAvailabilityRequestId = requestId);
    try {
      final result = await _doctorFunctions.reviewDoctorAvailabilityRequest(
        requestId: requestId,
        approved: approved,
      );
      if (!mounted) return;
      await context.read<NotificationProvider>().markAsRead(notification.id);
      if (!mounted) return;
      final cancelledCount =
          (result['cancelledAppointments'] as num?)?.toInt() ?? 0;
      final cancellationError = result['cancellationError']?.toString();
      final message = approved
          ? cancellationError != null && cancellationError.isNotEmpty
              ? 'Approved. Appointment cleanup needs review.'
              : 'Approved. $cancelledCount appointment(s) were cancelled.'
          : 'Request rejected.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              approved && cancellationError != null && cancellationError.isNotEmpty
                  ? AppColors.warning
                  : AppColors.success,
        ),
      );
    } on DoctorFunctionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to review request: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _reviewingAvailabilityRequestId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.notifications,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, _) {
              if (provider.unreadCount > 0) {
                return TextButton(
                  onPressed: _markAllAsRead,
                  child: Text(l10n.markAllRead),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.notifications.isEmpty) {
            return _buildEmptyState(isDark);
          }

          return RefreshIndicator(
            onRefresh: _loadNotifications,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: provider.notifications.length,
              itemBuilder: (context, index) {
                final n = provider.notifications[index];
                return ResponsiveContent(
                  maxWidth: 900,
                  child: _NotificationCard(
                    notification: n,
                    isDark: isDark,
                    onTap: () => _onNotificationTap(n),
                    onConfirmDismiss: () => _onConfirmNotificationDismiss(n),
                    showAvailabilityActions:
                        _canReviewAvailabilityRequest(n),
                    isReviewing: _reviewingAvailabilityRequestId ==
                        _availabilityRequestId(n),
                    onApprove: () => _reviewAvailabilityRequest(n, true),
                    onReject: () => _reviewAvailabilityRequest(n, false),
                  ),
                )
                    .animate(delay: Duration(milliseconds: index * 50))
                    .fadeIn(duration: 300.ms);
              },
            ),
          );
        },
      ),
    );
  }

  void _onNotificationTap(NotificationModel notification) {
    final notificationProvider = context.read<NotificationProvider>();

    // Mark as read
    if (!notification.isRead) {
      notificationProvider.markAsRead(notification.id);
    }

    _showNotificationDetails(notification);
  }

  void _showNotificationDetails(NotificationModel notification) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = _notificationColor(notification.type);
    final details = <Widget>[
      _detailLine('Type', _notificationTypeLabel(notification.type)),
      _detailLine('Received', _formatDateTime(notification.createdAt)),
      if (notification.scheduledFor != null)
        _detailLine(
            'Scheduled for', _formatDateTime(notification.scheduledFor!)),
      if (notification.reminderType != null &&
          notification.reminderType != ReminderType.immediate)
        _detailLine('Reminder', _reminderLabel(notification.reminderType!)),
    ];
    if (_isAvailabilityRequest(notification)) {
      final data = notification.data ?? const <String, dynamic>{};
      details.addAll([
        _detailLine('Doctor', data['doctorName']?.toString() ?? 'Doctor'),
        _detailLine('Status', data['status']?.toString() ?? 'pending'),
        if ((data['reason']?.toString() ?? '').isNotEmpty)
          _detailLine('Note', data['reason'].toString()),
      ]);
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(_notificationIcon(notification.type), color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                notification.title,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  notification.body,
                  style: GoogleFonts.roboto(
                    fontSize: 15,
                    height: 1.45,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 18),
                ...details,
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.roboto(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: GoogleFonts.roboto(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    return DateFormat('MMM d, yyyy \'at\' HH:mm').format(value);
  }

  String _notificationTypeLabel(NotificationType type) {
    final words = type.name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    );
    return words[0].toUpperCase() + words.substring(1);
  }

  String _reminderLabel(ReminderType reminderType) {
    switch (reminderType) {
      case ReminderType.oneWeek:
        return '1 week reminder';
      case ReminderType.oneDay:
        return '1 day reminder';
      case ReminderType.oneHour:
        return '1 hour reminder';
      case ReminderType.immediate:
        return 'Immediate';
    }
  }

  IconData _notificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.appointmentReminder:
        return Icons.access_time;
      case NotificationType.appointmentConfirmation:
        return Icons.check_circle;
      case NotificationType.appointmentCancellation:
        return Icons.cancel;
      case NotificationType.appointmentRescheduled:
        return Icons.update;
      case NotificationType.appointmentCompleted:
        return Icons.task_alt;
      case NotificationType.appointmentNoShow:
        return Icons.person_off;
      case NotificationType.healthTip:
        return Icons.lightbulb;
      case NotificationType.dailySummary:
        return Icons.calendar_month;
      case NotificationType.adminAnnouncement:
        return Icons.campaign;
      case NotificationType.doctorAvailabilityRequest:
        return Icons.priority_high_rounded;
      case NotificationType.doctorAvailabilityDecision:
        return Icons.verified_user_rounded;
      default:
        return Icons.notifications;
    }
  }

  Color _notificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.appointmentReminder:
        return AppColors.primary;
      case NotificationType.appointmentConfirmation:
        return Colors.green;
      case NotificationType.appointmentCancellation:
        return Colors.red;
      case NotificationType.appointmentRescheduled:
        return Colors.orange;
      case NotificationType.appointmentCompleted:
        return Colors.green;
      case NotificationType.appointmentNoShow:
        return Colors.deepOrange;
      case NotificationType.healthTip:
        return Colors.purple;
      case NotificationType.dailySummary:
        return AppColors.primary;
      case NotificationType.adminAnnouncement:
        return AppColors.info;
      case NotificationType.doctorAvailabilityRequest:
        return AppColors.warning;
      case NotificationType.doctorAvailabilityDecision:
        return AppColors.secondary;
      default:
        return AppColors.primary;
    }
  }

  Future<bool> _onConfirmNotificationDismiss(
    NotificationModel notification,
  ) async {
    final notificationProvider = context.read<NotificationProvider>();
    final l10n = AppLocalizations.of(context);
    try {
      // The user requested: wait for deleteNotification to return true
      await notificationProvider.deleteNotification(notification.id);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.error), backgroundColor: AppColors.error),
        );
      }
      return false;
    }
  }

  Widget _buildEmptyState(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _loadNotifications,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noNotifications,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.noNotificationsDesc,
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final bool isDark;
  final VoidCallback? onTap;
  final Future<bool> Function()? onConfirmDismiss;
  final bool showAvailabilityActions;
  final bool isReviewing;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;

  const _NotificationCard({
    required this.notification,
    required this.isDark,
    this.onTap,
    this.onConfirmDismiss,
    this.showAvailabilityActions = false,
    this.isReviewing = false,
    this.onApprove,
    this.onReject,
  });

  bool get _isAvailabilityRequest =>
      notification.type == NotificationType.doctorAvailabilityRequest ||
      notification.data?['category'] == 'doctorAvailabilityRequest';

  String get _availabilityStatus =>
      notification.data?['status']?.toString() ?? 'pending';

  String get _availabilityReason =>
      notification.data?['reason']?.toString() ?? '';

  String get _availabilityDoctorName =>
      notification.data?['doctorName']?.toString() ?? 'Doctor';

  IconData _getNotificationIcon() {
    switch (notification.type) {
      case NotificationType.appointmentReminder:
        return Icons.access_time;
      case NotificationType.appointmentConfirmation:
        return Icons.check_circle;
      case NotificationType.appointmentCancellation:
        return Icons.cancel;
      case NotificationType.appointmentRescheduled:
        return Icons.update;
      case NotificationType.appointmentCompleted:
        return Icons.task_alt;
      case NotificationType.appointmentNoShow:
        return Icons.person_off;
      case NotificationType.healthTip:
        return Icons.lightbulb;
      case NotificationType.dailySummary:
        return Icons.calendar_month;
      case NotificationType.adminAnnouncement:
        return Icons.campaign;
      case NotificationType.doctorAvailabilityRequest:
        return Icons.priority_high_rounded;
      case NotificationType.doctorAvailabilityDecision:
        return Icons.verified_user_rounded;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor() {
    switch (notification.type) {
      case NotificationType.appointmentReminder:
        return AppColors.primary;
      case NotificationType.appointmentConfirmation:
        return Colors.green;
      case NotificationType.appointmentCancellation:
        return Colors.red;
      case NotificationType.appointmentRescheduled:
        return Colors.orange;
      case NotificationType.appointmentCompleted:
        return Colors.green;
      case NotificationType.appointmentNoShow:
        return Colors.deepOrange;
      case NotificationType.healthTip:
        return Colors.purple;
      case NotificationType.dailySummary:
        return AppColors.primary;
      case NotificationType.adminAnnouncement:
        return AppColors.info;
      case NotificationType.doctorAvailabilityRequest:
        return AppColors.warning;
      case NotificationType.doctorAvailabilityDecision:
        return AppColors.secondary;
      default:
        return AppColors.primary;
    }
  }

  String _getReminderLabel() {
    if (notification.reminderType == null) return '';

    switch (notification.reminderType!) {
      case ReminderType.oneWeek:
        return '1 week reminder';
      case ReminderType.oneDay:
        return '1 day reminder';
      case ReminderType.oneHour:
        return '1 hour reminder';
      case ReminderType.immediate:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getNotificationColor();
    final reminderLabel = _getReminderLabel();
    final child = GestureDetector(
      onTap: onTap,
      child: _isAvailabilityRequest
          ? _buildAvailabilityRequestCard(context, iconColor)
          : _buildStandardCard(iconColor, reminderLabel),
    );

    if (_isAvailabilityRequest && _availabilityStatus == 'pending') {
      return child;
    }

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (onConfirmDismiss != null) {
          return await onConfirmDismiss!();
        }
        return false;
      },
      onDismissed: (
        _,
      ) {}, // Handled in confirmDismiss implies the item is removed from data source, causing rebuild
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: child,
    );
  }

  Widget _buildStandardCard(Color iconColor, String reminderLabel) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: notification.isRead
            ? (isDark ? AppColors.surfaceDark : AppColors.surfaceLight)
            : iconColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: !notification.isRead
            ? Border.all(color: iconColor.withValues(alpha: 0.2), width: 1)
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_getNotificationIcon(), color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!notification.isRead)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                if (reminderLabel.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      reminderLabel,
                      style: GoogleFonts.roboto(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: iconColor,
                      ),
                    ),
                  ),
                Text(
                  notification.body,
                  style: GoogleFonts.roboto(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            notification.timeAgo,
            style: GoogleFonts.roboto(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityRequestCard(BuildContext context, Color iconColor) {
    final isPending = _availabilityStatus == 'pending';
    final statusColor = _availabilityStatus == 'approved'
        ? AppColors.success
        : _availabilityStatus == 'rejected'
            ? AppColors.error
            : AppColors.warning;
    final background = isDark
        ? statusColor.withValues(alpha: 0.12)
        : statusColor.withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: isPending ? 0.65 : 0.35),
          width: isPending ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getNotificationIcon(), color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Doctor availability request',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _statusChip(_availabilityStatus, statusColor),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dr. $_availabilityDoctorName',
                      style: GoogleFonts.roboto(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                notification.timeAgo,
                style: GoogleFonts.roboto(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            notification.body,
            style: GoogleFonts.roboto(
              fontSize: 13,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              height: 1.35,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (_availabilityReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _availabilityReason,
                style: GoogleFonts.roboto(
                  fontSize: 13,
                  height: 1.35,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (showAvailabilityActions && isPending) ...[
            const SizedBox(height: 14),
            if (isReviewing)
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          side: const BorderSide(
                            color: AppColors.primary,
                            width: 1.4,
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Reject'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: onApprove,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve'),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status, Color color) {
    final normalized = status.isEmpty ? 'pending' : status;
    final label = normalized[0].toUpperCase() + normalized.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.roboto(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

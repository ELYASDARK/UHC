import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/notification_model.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';

/// Notifications screen
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Defer loading to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotifications();
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
              padding: const EdgeInsets.all(16),
              itemCount: provider.notifications.length,
              itemBuilder: (context, index) {
                final n = provider.notifications[index];
                return _NotificationCard(
                      notification: n,
                      isDark: isDark,
                      onTap: () => _onNotificationTap(n),
                      onDismiss: () => _onNotificationDismiss(n),
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
  }

  Future<void> _onNotificationDismiss(NotificationModel notification) async {
    final notificationProvider = context.read<NotificationProvider>();
    await notificationProvider.deleteNotification(notification.id);
  }

  Widget _buildEmptyState(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return Center(
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
            style: GoogleFonts.roboto(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const _NotificationCard({
    required this.notification,
    required this.isDark,
    this.onTap,
    this.onDismiss,
  });

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
      case NotificationType.healthTip:
        return Icons.lightbulb;
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
      case NotificationType.healthTip:
        return Colors.purple;
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

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss?.call(),
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
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
        ),
      ),
    );
  }
}

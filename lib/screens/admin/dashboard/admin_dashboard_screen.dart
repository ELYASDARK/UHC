import '../../../core/widgets/session_stream_builder.dart';
import 'package:uhc/core/utils/app_messages.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/admin_statistics_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../departments/department_management_screen.dart';
import '../doctors/doctor_management_screen.dart';
import '../users/user_management_screen.dart';
import '../notifications/admin_notification_sender_screen.dart';
import '../analytics/appointment_analytics_screen.dart';
import '../reports/reports_screen.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/widgets/role_english_ltr_scope.dart';

/// Admin dashboard with overview and navigation
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.statistics});

  final AdminStatisticsService? statistics;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _firestore = FirebaseFirestore.instance;
  late AdminStatisticsService _statistics;
  String? _session;
  bool _initialized = false;
  final _loading = <String>{};
  final _failed = <String>{};
  final _waiting = <String>{};
  final _values = <String, int>{};
  Future<void>? _activeLoad;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<AuthProvider>().user;
    final session = '${user?.id}:${user?.isActive}:'
        '${user?.hasPermission('users.view')}:'
        '${[
      'appointments.view',
      'analytics.view',
      'reports.view'
    ].any((key) => user?.hasPermission(key) ?? false)}';
    if (!_initialized || session != _session) {
      _initialized = true;
      _session = session;
      _generation++;
      _activeLoad = null;
      _values.clear();
      _loading.clear();
      _failed.clear();
      _waiting.clear();
      _statistics = widget.statistics ?? AdminStatisticsService();
      _loadDashboardStats();
    }
  }

  Future<void> _loadDashboardStats({bool failedOnly = false}) {
    if (_activeLoad != null) return _activeLoad!;
    final user = context.read<AuthProvider>().user;
    final uid = user?.id;
    final generation = ++_generation;
    final groups = <String, Future<Map<String, int>> Function()>{
      if (user?.hasPermission('users.view') ?? false)
        'users': () async => {'users': await _statistics.users()},
      if (user?.isActive ?? false)
        'doctors': () async => {'doctors': await _statistics.doctors()},
      if (['appointments.view', 'analytics.view', 'reports.view']
          .any((key) => user?.hasPermission(key) ?? false))
        'appointments': () async {
          final result = await _statistics.analytics('dashboard');
          return {
            for (final key in ['total', 'pending', 'today', 'completed'])
              key: (result[key] as num).toInt()
          };
        },
    };
    if (failedOnly) groups.removeWhere((key, _) => !_failed.contains(key));
    setState(() {
      _loading.addAll(groups.keys);
      _failed.removeAll(groups.keys);
      _waiting.removeAll(groups.keys);
      for (final key in groups.keys) {
        for (final value in key == 'appointments'
            ? ['total', 'pending', 'today', 'completed']
            : [key]) {
          _values.remove(value);
        }
      }
    });
    Future<void> load(
        String key, Future<Map<String, int>> Function() request) async {
      try {
        final values = await request().timeout(AdminStatisticsService.timeout);
        if (!mounted ||
            generation != _generation ||
            context.read<AuthProvider>().user?.id != uid) {
          return;
        }
        setState(() => _values.addAll(values));
      } catch (error) {
        if (!mounted ||
            generation != _generation ||
            context.read<AuthProvider>().user?.id != uid) {
          return;
        }
        setState(() {
          _failed.add(key);
          if (error is StatisticsRequestsPending) _waiting.add(key);
        });
      } finally {
        if (mounted && generation == _generation) {
          setState(() => _loading.remove(key));
        }
      }
    }

    final request = Future.wait(
        groups.entries.map((entry) => load(entry.key, entry.value)));
    _activeLoad = request;
    return request.whenComplete(() {
      if (identical(_activeLoad, request)) _activeLoad = null;
    });
  }

  String _stat(String key, String group) {
    if (_loading.contains(group)) return 'Loading...';
    if (_failed.contains(group)) return 'Unavailable';
    final value = _values[key];
    return value == null ? 'No access' : NumberFormat.compact().format(value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RoleEnglishLtrScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          centerTitle: true,
        ),
        body: RefreshIndicator(
          onRefresh: () => _loadDashboardStats(),
          child: ResponsivePage(
            physics: const AlwaysScrollableScrollPhysics(),
            maxWidth: 1280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_failed.isNotEmpty)
                  Row(children: [
                    Expanded(
                        child: Text(_waiting.isNotEmpty
                            ? 'Statistics are still waiting for the server. Check your connection or reopen this screen.'
                            : 'Some statistics are unavailable.')),
                    TextButton(
                        onPressed: _loading.isEmpty
                            ? () => _loadDashboardStats(failedOnly: true)
                            : null,
                        child: const Text('Retry statistics')),
                  ]),
                // Stats Grid
                _buildStatsGrid(isDark),
                const SizedBox(height: 24),

                // Quick Actions
                Text(
                  'Quick Actions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                _buildQuickActions(isDark),
                const SizedBox(height: 24),

                // Recent Activity
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                _buildRecentActivity(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(bool isDark) {
    return ResponsiveGrid(
      phoneColumns: 2,
      tabletColumns: 3,
      laptopColumns: 3,
      desktopColumns: 6,
      childAspectRatio: 1.4,
      children: [
        _buildStatCard(
          isDark: isDark,
          title: 'Total Users',
          value: _stat('users', 'users'),
          icon: Icons.people,
          color: AppColors.primary,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Total Doctors',
          value: _stat('doctors', 'doctors'),
          icon: Icons.medical_services,
          color: AppColors.secondary,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Appointments',
          value: _stat('total', 'appointments'),
          icon: Icons.calendar_today,
          color: AppColors.tertiary,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Booked',
          value: _stat('pending', 'appointments'),
          icon: Icons.pending_actions,
          color: AppColors.warning,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Today',
          value: _stat('today', 'appointments'),
          icon: Icons.today,
          color: AppColors.success,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Completed',
          value: _stat('completed', 'appointments'),
          icon: Icons.check_circle,
          color: AppColors.info,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required bool isDark,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(bool isDark) {
    final user = context.read<AuthProvider>().currentUser;
    final canSendNotifications =
        user?.hasPermission('notifications.send') ?? false;

    final actions = <Widget>[
      _buildActionCard(
        isDark: isDark,
        title: 'Manage Doctors',
        icon: Icons.medical_services,
        color: AppColors.primary,
        isEnabled: user?.hasPermission('doctors.view') ?? false,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DoctorManagementScreen()),
        ),
      ),
      _buildActionCard(
        isDark: isDark,
        title: 'Manage Users',
        icon: Icons.people,
        color: AppColors.secondary,
        isEnabled: user?.hasPermission('users.view') ?? false,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserManagementScreen()),
        ),
      ),
      _buildActionCard(
        isDark: isDark,
        title: 'Analytics',
        icon: Icons.analytics,
        color: AppColors.tertiary,
        isEnabled: user?.hasPermission('analytics.view') ?? false,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AppointmentAnalyticsScreen(),
          ),
        ),
      ),
      _buildActionCard(
        isDark: isDark,
        title: 'Reports',
        icon: Icons.description,
        color: Colors.purple,
        isEnabled: user?.hasPermission('reports.view') ?? false,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReportsScreen()),
        ),
      ),
      _buildActionCard(
        isDark: isDark,
        title: 'Send Notification',
        icon: Icons.campaign,
        color: Colors.deepOrange,
        isEnabled: canSendNotifications,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AdminNotificationSenderScreen(),
          ),
        ),
      ),
      _buildActionCard(
        isDark: isDark,
        title: 'Departments',
        icon: Icons.business,
        color: Colors.indigo,
        isEnabled: user?.hasPermission('departments.view') ?? false,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DepartmentManagementScreen(),
          ),
        ),
      ),
    ];

    return ResponsiveGrid(
      phoneColumns: 2,
      tabletColumns: 3,
      laptopColumns: 4,
      desktopColumns: 4,
      childAspectRatio: 2.5,
      children: actions,
    );
  }

  Widget _buildActionCard({
    required bool isDark,
    required String title,
    required IconData icon,
    required Color color,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    final effectiveColor =
        isEnabled ? color : Color.lerp(color, Colors.grey, 0.35)!;

    return InkWell(
      onTap: isEnabled ? onTap : _showPermissionDenied,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: isEnabled ? 0.1 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: effectiveColor.withValues(alpha: isEnabled ? 0.3 : 0.22),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: effectiveColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: effectiveColor,
                ),
              ),
            ),
            Icon(
              isEnabled ? Icons.arrow_forward_ios : Icons.lock_outline,
              size: isEnabled ? 14 : 16,
              color: effectiveColor,
            ),
          ],
        ),
      ),
    );
  }

  void _showPermissionDenied() {
    AppMessages.show(
      context,
      SnackBar(
        content: Text(AppMessages.localizations(context).noPermissionForAction),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildRecentActivity(bool isDark) {
    final user = context.read<AuthProvider>().user;
    if (!(user?.hasPermission('appointments.view') ?? false) &&
        !(user?.hasPermission('reports.view') ?? false)) {
      return const Text(
          'Clinical activity requires appointment or report access.');
    }
    if (!(user?.googleEmail?.isNotEmpty ?? false)) {
      return const Text('Link your Google account to view clinical activity.');
    }
    return SessionStreamBuilder<QuerySnapshot>(
      permission: user!.hasPermission('appointments.view')
          ? 'appointments.view'
          : 'reports.view',
      queryKey: 'recent-activity',
      createStream: () => _firestore
          .collection('appointments')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildRecentActivitySkeleton(isDark);
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('No recent activity')),
          );
        }

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
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: snapshot.data!.docs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final status = data['status'] ?? 'pending';
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

              return Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(
                      status,
                    ).withValues(alpha: 0.15),
                    child: Icon(
                      _getStatusIcon(status),
                      color: _getStatusColor(status),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    data['patientName'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Dr. ${data['doctorName'] ?? 'Unknown'} • ${data['timeSlot'] ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              _getStatusColor(status).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status == 'pending'
                              ? 'BOOKED'
                              : status.toString().toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(status),
                          ),
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          _formatTime(createdAt),
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'confirmed':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'cancelled':
        return AppColors.error;
      case 'completed':
        return AppColors.info;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'confirmed':
        return Icons.check_circle;
      case 'pending':
        return Icons.schedule;
      case 'cancelled':
        return Icons.cancel;
      case 'completed':
        return Icons.done_all;
      default:
        return Icons.help;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  Widget _buildRecentActivitySkeleton(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          3,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                const LoadingSkeleton(width: 40, height: 40, borderRadius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      LoadingSkeleton(width: 120, height: 16),
                      SizedBox(height: 8),
                      LoadingSkeleton(width: 80, height: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const LoadingSkeleton(width: 60, height: 20, borderRadius: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

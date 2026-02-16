import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/user_model.dart';
import 'department_management_screen.dart';
import 'doctor_management_screen.dart';
import 'user_management_screen.dart';
import 'appointment_analytics_screen.dart';
import 'reports_screen.dart';
import '../../core/widgets/loading_skeleton.dart';

/// Admin dashboard with overview and navigation
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;

  // Stats
  int _totalUsers = 0;
  int _totalDoctors = 0;
  int _totalAppointments = 0;
  int _pendingAppointments = 0;
  int _todayAppointments = 0;
  double _monthlyRevenue = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardStats();
  }

  Future<void> _loadDashboardStats() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Define all futures to run in parallel
      final futures = [
        // 0: Total Users (Students)
        _firestore
            .collection('users')
            .where('role', isEqualTo: UserRole.student.name)
            .count()
            .get(),
        // 1: Total Doctors
        _firestore.collection('doctors').count().get(),
        // 2: Total Appointments
        _firestore.collection('appointments').count().get(),
        // 3: Pending Appointments
        _firestore
            .collection('appointments')
            .where('status', isEqualTo: 'pending')
            .count()
            .get(),
        // 4: Today's Appointments
        _firestore
            .collection('appointments')
            .where(
              'appointmentDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where('appointmentDate', isLessThan: Timestamp.fromDate(endOfDay))
            .count()
            .get(),
      ];

      // Wait for all futures to complete
      final results = await Future.wait(futures);

      _totalUsers = results[0].count ?? 0;
      _totalDoctors = results[1].count ?? 0;
      _totalAppointments = results[2].count ?? 0;
      _pendingAppointments = results[3].count ?? 0;
      _todayAppointments = results[4].count ?? 0;

      // Calculate monthly revenue (mock calculation based on total appointments)
      _monthlyRevenue = _totalAppointments * 50.0;
    } catch (e) {
      debugPrint('Error loading dashboard stats: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        centerTitle: true,
      ),
      body: _isLoading
          ? _buildDashboardSkeleton(isDark)
          : RefreshIndicator(
              onRefresh: _loadDashboardStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
    );
  }

  Widget _buildStatsGrid(bool isDark) {
    // Number formatters
    final numberFormat = NumberFormat.compact(); // 1.2K, 1M, etc.
    final currencyFormat = NumberFormat.simpleCurrency(decimalDigits: 0);
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1200 ? 6 : (width > 600 ? 3 : 2);

    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _buildStatCard(
          isDark: isDark,
          title: 'Total Users',
          value: numberFormat.format(_totalUsers),
          icon: Icons.people,
          color: AppColors.primary,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Total Doctors',
          value: numberFormat.format(_totalDoctors),
          icon: Icons.medical_services,
          color: AppColors.secondary,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Appointments',
          value: numberFormat.format(_totalAppointments),
          icon: Icons.calendar_today,
          color: AppColors.tertiary,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Pending',
          value: numberFormat.format(_pendingAppointments),
          icon: Icons.pending_actions,
          color: AppColors.warning,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Today',
          value: numberFormat.format(_todayAppointments),
          icon: Icons.today,
          color: AppColors.success,
        ),
        _buildStatCard(
          isDark: isDark,
          title: 'Revenue',
          value: currencyFormat.format(_monthlyRevenue),
          icon: Icons.attach_money,
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
                  fontSize: 24,
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
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1200 ? 4 : (width > 600 ? 3 : 2);

    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: [
        _buildActionCard(
          isDark: isDark,
          title: 'Manage Doctors',
          icon: Icons.medical_services,
          color: AppColors.primary,
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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReportsScreen()),
          ),
        ),
        _buildActionCard(
          isDark: isDark,
          title: 'Departments',
          icon: Icons.business,
          color: Colors.teal,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const DepartmentManagementScreen(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required bool isDark,
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('appointments')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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

              return ListTile(
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
                        color: _getStatusColor(status).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toString().toUpperCase(),
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

  Widget _buildDashboardSkeleton(bool isDark) {
    final width = MediaQuery.of(context).size.width;
    final statsCrossAxisCount = width > 1200 ? 6 : (width > 600 ? 3 : 2);
    final actionsCrossAxisCount = width > 1200 ? 4 : (width > 600 ? 3 : 2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Grid Skeleton
          GridView.count(
            crossAxisCount: statsCrossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: List.generate(
              6,
              (index) => LoadingSkeleton(
                height: 100,
                borderRadius: 16,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Quick Actions Skeleton
          const LoadingSkeleton(width: 150, height: 24),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: actionsCrossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.5,
            children: List.generate(
              4,
              (index) => LoadingSkeleton(
                height: 60,
                borderRadius: 12,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Recent Activity Skeleton
          const LoadingSkeleton(width: 150, height: 24),
          const SizedBox(height: 12),
          _buildRecentActivitySkeleton(isDark),
        ],
      ),
    );
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

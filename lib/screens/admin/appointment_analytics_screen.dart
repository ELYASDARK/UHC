import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';

/// Appointment analytics screen for admin
class AppointmentAnalyticsScreen extends StatefulWidget {
  const AppointmentAnalyticsScreen({super.key});

  @override
  State<AppointmentAnalyticsScreen> createState() =>
      _AppointmentAnalyticsScreenState();
}

class _AppointmentAnalyticsScreenState
    extends State<AppointmentAnalyticsScreen> {
  final _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  String _selectedPeriod = 'week';

  // Analytics data
  Map<String, int> _statusDistribution = {};
  Map<String, int> _departmentDistribution = {};
  Map<String, int> _dailyAppointments = {};
  int _totalAppointments = 0;
  int _completedAppointments = 0;
  int _cancelledAppointments = 0;
  double _completionRate = 0;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      DateTime startDate;

      switch (_selectedPeriod) {
        case 'week':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          startDate = DateTime(now.year, now.month - 1, now.day);
          break;
        case 'year':
          startDate = DateTime(now.year - 1, now.month, now.day);
          break;
        default:
          startDate = now.subtract(const Duration(days: 7));
      }

      final snapshot = await _firestore
          .collection('appointments')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .get();

      _totalAppointments = snapshot.docs.length;
      _statusDistribution = {};
      _departmentDistribution = {};
      _dailyAppointments = {};
      _completedAppointments = 0;
      _cancelledAppointments = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Status distribution
        final status = data['status'] ?? 'pending';
        _statusDistribution[status] = (_statusDistribution[status] ?? 0) + 1;
        if (status == 'completed') _completedAppointments++;
        if (status == 'cancelled') _cancelledAppointments++;

        // Department distribution
        final department = data['department'] ?? 'Unknown';
        _departmentDistribution[department] =
            (_departmentDistribution[department] ?? 0) + 1;

        // Daily appointments
        final date = (data['appointmentDate'] as Timestamp?)?.toDate();
        if (date != null) {
          final dayKey = '${date.month}/${date.day}';
          _dailyAppointments[dayKey] = (_dailyAppointments[dayKey] ?? 0) + 1;
        }
      }

      _completionRate = _totalAppointments > 0
          ? (_completedAppointments / _totalAppointments) * 100
          : 0;
    } catch (e) {
      debugPrint('Error loading analytics: $e');
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
        title: const Text('Appointment Analytics'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalytics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Period Selector
                  _buildPeriodSelector(isDark),
                  const SizedBox(height: 24),

                  // Summary Cards
                  _buildSummaryCards(isDark),
                  const SizedBox(height: 24),

                  // Status Distribution
                  Text(
                    'Status Distribution',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatusChart(isDark),
                  const SizedBox(height: 24),

                  // Department Distribution
                  Text(
                    'By Department',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDepartmentChart(isDark),
                  const SizedBox(height: 24),

                  // Daily Trend
                  Text(
                    'Daily Trend',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDailyTrend(isDark),
                ],
              ),
            ),
    );
  }

  Widget _buildPeriodSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildPeriodButton('Week', 'week', isDark),
          _buildPeriodButton('Month', 'month', isDark),
          _buildPeriodButton('Year', 'year', isDark),
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String label, String value, bool isDark) {
    final isSelected = _selectedPeriod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedPeriod = value);
          _loadAnalytics();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                isDark: isDark,
                title: 'Total',
                value: _totalAppointments.toString(),
                icon: Icons.calendar_today,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                isDark: isDark,
                title: 'Completed',
                value: _completedAppointments.toString(),
                icon: Icons.check_circle,
                color: AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                isDark: isDark,
                title: 'Cancelled',
                value: _cancelledAppointments.toString(),
                icon: Icons.cancel,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                isDark: isDark,
                title: 'Rate',
                value: '${_completionRate.toStringAsFixed(0)}%',
                icon: Icons.trending_up,
                color: AppColors.info,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
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
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
    );
  }

  Widget _buildStatusChart(bool isDark) {
    if (_statusDistribution.isEmpty) {
      return _buildEmptyState('No data available');
    }

    final total = _statusDistribution.values.fold(0, (a, b) => a + b);

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
        children: _statusDistribution.entries.map((entry) {
          final percentage = (entry.value / total) * 100;
          final color = _getStatusColor(entry.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.key.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text('${entry.value} (${percentage.toStringAsFixed(0)}%)'),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: color.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDepartmentChart(bool isDark) {
    if (_departmentDistribution.isEmpty) {
      return _buildEmptyState('No data available');
    }

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
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _departmentDistribution.entries.map((entry) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry.value.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDailyTrend(bool isDark) {
    if (_dailyAppointments.isEmpty) {
      return _buildEmptyState('No data available');
    }

    final maxValue = _dailyAppointments.values.reduce((a, b) => a > b ? a : b);
    final sortedEntries = _dailyAppointments.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      height: 200,
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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: sortedEntries.take(7).map((entry) {
          final height = maxValue > 0 ? (entry.value / maxValue) * 120 : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    entry.value.toString(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.key,
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
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.surfaceDark
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
      ),
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
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/admin_statistics_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/widgets/role_english_ltr_scope.dart';

enum _AnalyticsError { noAccess, pending, unavailable, cancelled }

/// Appointment analytics screen for admin
class AppointmentAnalyticsScreen extends StatefulWidget {
  const AppointmentAnalyticsScreen({super.key, this.statistics});

  final AdminStatisticsService? statistics;

  @override
  State<AppointmentAnalyticsScreen> createState() =>
      _AppointmentAnalyticsScreenState();
}

class _AppointmentAnalyticsScreenState
    extends State<AppointmentAnalyticsScreen> {
  bool _isLoading = true;
  String _selectedPeriod = 'week';
  late AdminStatisticsService _statistics;
  String? _session;
  bool _initialized = false;
  bool _canRead = true;
  _AnalyticsError? _error;
  bool _truncated = false;
  int _generation = 0;
  AnalyticsLoad? _load;
  String? _asOf;

  @override
  void dispose() {
    _load?.cancelled = true;
    super.dispose();
  }

  // Analytics data
  Map<String, int> _statusDistribution = {};
  Map<String, int> _departmentDistribution = {};
  Map<String, int> _dailyAppointments = {};
  int _totalAppointments = 0;
  int _completedAppointments = 0;
  int _cancelledAppointments = 0;
  double _completionRate = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider?>();
    final user = auth?.user;
    final allowed = auth == null ||
        (user != null &&
            user.isActive &&
            auth.isGoogleLinked &&
            ['analytics.view', 'appointments.view', 'reports.view']
                .any(user.hasPermission));
    final session = '${user?.id}:$allowed';
    if (!_initialized || _session != session) {
      _initialized = true;
      _session = session;
      _canRead = allowed;
      _load?.cancelled = true;
      _generation++;
      _statistics = widget.statistics ?? AdminStatisticsService();
      _statusDistribution = {};
      _departmentDistribution = {};
      _dailyAppointments = {};
      _totalAppointments = 0;
      if (allowed) {
        _loadAnalytics();
      } else {
        _isLoading = false;
        _error = _AnalyticsError.noAccess;
      }
    }
  }

  Future<void> _loadAnalytics() async {
    if (!_canRead) return;
    _load?.cancelled = true;
    final load = AnalyticsLoad();
    _load = load;
    _statistics.activeLoad = load;
    final generation = ++_generation;
    final period = _selectedPeriod;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _statistics.analytics(period);
      if (!mounted || generation != _generation) return;
      Map<String, int> counts(String key) =>
          Map<String, dynamic>.from(response[key] as Map)
              .map((key, value) => MapEntry(key, (value as num).toInt()));
      _totalAppointments = (response['total'] as num).toInt();
      _truncated = response['truncated'] == true;
      _asOf = response['asOf'] as String?;
      _statusDistribution = counts('statuses');
      _departmentDistribution = counts('departments');
      _dailyAppointments = counts('days');
      _completedAppointments = _statusDistribution['completed'] ?? 0;
      _cancelledAppointments = _statusDistribution['cancelled'] ?? 0;
      _completionRate = _totalAppointments > 0
          ? (_completedAppointments / _totalAppointments) * 100
          : 0;
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _error = error is StatisticsRequestsPending
          ? _AnalyticsError.pending
          : _AnalyticsError.unavailable;
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RoleEnglishLtrScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Appointment Analytics'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _isLoading || !_canRead ? null : _loadAnalytics,
            ),
          ],
        ),
        body: ResponsivePage(
          maxWidth: 1120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Period Selector
              _buildPeriodSelector(isDark),
              const SizedBox(height: 20),

              if (_isLoading)
                Column(children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text('Updating…'),
                  TextButton(
                      onPressed: () {
                        _load?.cancelled = true;
                        _generation++;
                        setState(() {
                          _isLoading = false;
                          _error = _AnalyticsError.cancelled;
                        });
                      },
                      child: const Text('Cancel')),
                ])
              else if (_error != null)
                Column(children: [
                  Text(switch (_error!) {
                    _AnalyticsError.noAccess =>
                      "You don't have access to this summary.",
                    _AnalyticsError.pending =>
                      'This is taking longer than usual. Check your connection and try again.',
                    _AnalyticsError.unavailable =>
                      "Couldn't load the summary. Try again.",
                    _AnalyticsError.cancelled =>
                      'Update cancelled. You can try again.',
                  }),
                  TextButton(
                      onPressed: _canRead ? _loadAnalytics : null,
                      child: const Text('Try again')),
                ])
              else ...[
                _buildSnapshotHeader(),
                if (_truncated)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Showing the 5,000 most recently added appointments. '
                          'Totals, charts and percentages apply only to those shown. '
                          'Try a shorter period to see all appointments.'),
                    ),
                  ),
                if (_totalAppointments == 0)
                  const Text('No appointments in this period.'),

                // Summary Cards
                _buildSummaryCards(isDark),
                const SizedBox(height: 20),

                // Status Distribution
                Text(
                  'Status Distribution',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                _buildStatusChart(isDark),
                const SizedBox(height: 20),

                // Department Distribution
                Text(
                  'By Department',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                _buildDepartmentChart(isDark),
                const SizedBox(height: 20),

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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSnapshotHeader() {
    final theme = Theme.of(context);
    final snapshot = DateTime.tryParse(_asOf ?? '')?.toLocal();
    final dateFormat = DateFormat.yMMMd('en');
    if (MediaQuery.alwaysUse24HourFormatOf(context)) {
      dateFormat.add_Hm();
    } else {
      dateFormat.add_jm();
    }
    final label = snapshot == null
        ? 'Update time unavailable'
        : 'Last updated: ${dateFormat.format(snapshot)}';
    final secondary = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.schedule_outlined,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.labelMedium),
                    const SizedBox(height: 2),
                    Text('Refresh to see the latest changes.',
                        style: secondary),
                  ],
                ),
              ),
            ],
          ),
        ],
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
          if (!_canRead) return;
          if (_selectedPeriod == value) return;
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
    final cards = <Widget>[
      _buildSummaryCard(
        isDark: isDark,
        title: _truncated ? 'Shown' : 'Total',
        value: _totalAppointments.toString(),
        icon: Icons.calendar_today,
        color: AppColors.primary,
      ),
      _buildSummaryCard(
        isDark: isDark,
        title: 'Completed',
        value: _completedAppointments.toString(),
        icon: Icons.check_circle,
        color: AppColors.success,
      ),
      _buildSummaryCard(
        isDark: isDark,
        title: 'Cancelled',
        value: _cancelledAppointments.toString(),
        icon: Icons.cancel,
        color: AppColors.error,
      ),
      _buildSummaryCard(
        isDark: isDark,
        title: _truncated ? 'Completion rate' : 'Rate',
        value: '${_completionRate.toStringAsFixed(0)}%',
        icon: Icons.trending_up,
        color: AppColors.info,
      ),
    ];
    final columns = UhcResponsive.columnsFor(context,
        phone: 2, tablet: 2, laptop: 4, desktop: 4);
    return Column(children: [
      for (var offset = 0; offset < cards.length; offset += columns)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0;
                        column < columns && offset + column < cards.length;
                        column++) ...[
                      if (column > 0) const SizedBox(width: 12),
                      Expanded(child: cards[offset + column]),
                    ],
                  ]),
            )),
    ]);
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
      child: UhcResponsive.isWide(context)
          ? Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.05,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.1,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
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
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        entry.key == 'pending'
                            ? 'BOOKED'
                            : entry.key.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                          '${entry.value} (${percentage.toStringAsFixed(0)}%)'),
                    ],
                  ),
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
                Flexible(
                  child: Tooltip(
                    message: entry.key,
                    child: Text(
                      entry.key,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
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

    // Determine max value safely
    final maxValue = _dailyAppointments.values.isNotEmpty
        ? _dailyAppointments.values.reduce((a, b) => a > b ? a : b)
        : 1; // Default to 1 to avoid division by zero if empty (though guarded above)

    final sortedEntries = _dailyAppointments.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      constraints: const BoxConstraints(minHeight: 200),
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
          // Calculate height with division safety
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

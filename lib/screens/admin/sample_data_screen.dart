import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/sample_data_repository.dart';

/// Screen for managing sample data in Firebase
class SampleDataScreen extends StatefulWidget {
  const SampleDataScreen({super.key});

  @override
  State<SampleDataScreen> createState() => _SampleDataScreenState();
}

class _SampleDataScreenState extends State<SampleDataScreen> {
  final _repository = SampleDataRepository();
  bool _isLoading = false;
  Map<String, int> _stats = {'doctors': 0, 'appointments': 0, 'departments': 0};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _repository.getSampleDataStats();
      setState(() => _stats = stats);
    } catch (e) {
      _showError('Failed to load stats: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sample Data'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStats),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.dataset,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sample Data Manager',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Seed or clear sample data for testing',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Current Stats
                  Text(
                    'Current Sample Data',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatsRow(isDark),
                  const SizedBox(height: 24),

                  // Seed Data Section
                  Text(
                    'Seed Sample Data',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSeedCard(
                    isDark: isDark,
                    title: 'Seed Doctors',
                    subtitle: '8 sample doctors across 4 departments',
                    icon: Icons.medical_services,
                    color: AppColors.primary,
                    onTap: _seedDoctors,
                  ),
                  const SizedBox(height: 12),
                  _buildSeedCard(
                    isDark: isDark,
                    title: 'Seed Appointments',
                    subtitle: '18 sample appointments with various statuses',
                    icon: Icons.calendar_today,
                    color: AppColors.secondary,
                    onTap: _seedAppointments,
                  ),
                  const SizedBox(height: 12),
                  _buildSeedCard(
                    isDark: isDark,
                    title: 'Seed Departments',
                    subtitle: '4 department records with metadata',
                    icon: Icons.business,
                    color: AppColors.tertiary,
                    onTap: _seedDepartments,
                  ),
                  const SizedBox(height: 12),
                  _buildSeedCard(
                    isDark: isDark,
                    title: 'Seed All Data',
                    subtitle: 'Seed doctors, appointments, and departments',
                    icon: Icons.all_inclusive,
                    color: AppColors.success,
                    onTap: _seedAll,
                  ),
                  const SizedBox(height: 24),

                  // Clear Data Section
                  Text(
                    'Clear Sample Data',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSeedCard(
                    isDark: isDark,
                    title: 'Clear All Sample Data',
                    subtitle: 'Remove all seeded sample data from Firebase',
                    icon: Icons.delete_sweep,
                    color: AppColors.error,
                    onTap: _confirmClearData,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildStatChip(
            isDark: isDark,
            label: 'Doctors',
            count: _stats['doctors'] ?? 0,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatChip(
            isDark: isDark,
            label: 'Appointments',
            count: _stats['appointments'] ?? 0,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatChip(
            isDark: isDark,
            label: 'Departments',
            count: _stats['departments'] ?? 0,
            color: AppColors.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip({
    required bool isDark,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
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

  Widget _buildSeedCard({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
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
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seedDoctors() async {
    _showLoadingDialog('Seeding doctors...');
    try {
      final count = await _repository.seedSampleDoctors();
      if (!mounted) return;
      Navigator.pop(context);
      await _loadStats();
      _showSuccess('Successfully seeded $count doctors');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Failed to seed doctors: $e');
    }
  }

  Future<void> _seedAppointments() async {
    _showLoadingDialog('Seeding appointments...');
    try {
      final count = await _repository.seedSampleAppointments();
      if (!mounted) return;
      Navigator.pop(context);
      await _loadStats();
      _showSuccess('Successfully seeded $count appointments');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Failed to seed appointments: $e');
    }
  }

  Future<void> _seedDepartments() async {
    _showLoadingDialog('Seeding departments...');
    try {
      final count = await _repository.seedSampleDepartments();
      if (!mounted) return;
      Navigator.pop(context);
      await _loadStats();
      _showSuccess('Successfully seeded $count departments');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Failed to seed departments: $e');
    }
  }

  Future<void> _seedAll() async {
    _showLoadingDialog('Seeding all data...');
    try {
      final doctors = await _repository.seedSampleDoctors();
      final departments = await _repository.seedSampleDepartments();
      final appointments = await _repository.seedSampleAppointments();
      if (!mounted) return;
      Navigator.pop(context);
      await _loadStats();
      _showSuccess(
        'Seeded: $doctors doctors, $appointments appointments, $departments departments',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Failed to seed data: $e');
    }
  }

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Sample Data'),
        content: const Text(
          'Are you sure you want to remove all sample data? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _showLoadingDialog('Clearing sample data...');
      try {
        final results = await _repository.clearSampleData();
        if (!mounted) return;
        Navigator.pop(context);
        await _loadStats();
        _showSuccess(
          'Cleared: ${results['doctors']} doctors, ${results['appointments']} appointments, ${results['departments']} departments',
        );
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        _showError('Failed to clear data: $e');
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.success),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}

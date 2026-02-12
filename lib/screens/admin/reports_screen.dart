import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';

/// Reports generation screen for admin
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _firestore = FirebaseFirestore.instance;
  bool _isGenerating = false;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _selectedReportType = 'appointments';

  final List<Map<String, dynamic>> _reportTypes = [
    {
      'id': 'appointments',
      'title': 'Appointments Report',
      'icon': Icons.calendar_today,
      'description': 'All appointments with status, doctor, and patient info',
    },
    {
      'id': 'doctors',
      'title': 'Doctors Report',
      'icon': Icons.medical_services,
      'description': 'Doctor list with specialization, department, and status',
    },
    {
      'id': 'users',
      'title': 'Users Report',
      'icon': Icons.people,
      'description': 'Registered users with roles and status',
    },
    {
      'id': 'revenue',
      'title': 'Revenue Report',
      'icon': Icons.attach_money,
      'description':
          'Financial summary based on completed appointments (estimated)',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Range Selection
            Text(
              'Date Range',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildDateRangeSelector(isDark),
            const SizedBox(height: 24),

            // Report Types
            Text(
              'Select Report Type',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._reportTypes.map((report) => _buildReportCard(report, isDark)),
            const SizedBox(height: 24),

            // Generate Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateReport,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.file_download),
                label: Text(
                  _isGenerating ? 'Generating...' : 'Generate Report',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppColors.info,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Reports are exported as CSV files that can be opened in Excel or Google Sheets.',
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
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector(bool isDark) {
    final dateFormat = DateFormat('MMM d, yyyy');

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
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _selectDate(true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start Date',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateFormat.format(_startDate),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey.withValues(alpha: 0.3),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: InkWell(
                onTap: () => _selectDate(false),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End Date',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateFormat.format(_endDate),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report, bool isDark) {
    final isSelected = _selectedReportType == report['id'];

    return GestureDetector(
      onTap: () => setState(() => _selectedReportType = report['id']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : (isDark ? AppColors.surfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
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
                color: (isSelected ? AppColors.primary : Colors.grey)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                report['icon'],
                color: isSelected ? AppColors.primary : Colors.grey,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report['title'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.primary : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    report['description'],
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
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  Future<void> _generateReport() async {
    setState(() => _isGenerating = true);

    try {
      String csvContent = '';
      String fileName = '';

      switch (_selectedReportType) {
        case 'appointments':
          csvContent = await _generateAppointmentsReport();
          fileName = 'appointments_report';
          break;
        case 'doctors':
          csvContent = await _generateDoctorsReport();
          fileName = 'doctors_report';
          break;
        case 'users':
          csvContent = await _generateUsersReport();
          fileName = 'users_report';
          break;
        case 'revenue':
          csvContent = await _generateRevenueReport();
          fileName = 'revenue_report';
          break;
      }

      // Save and share file
      final directory = await getTemporaryDirectory();
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final file = File('${directory.path}/${fileName}_$dateStr.csv');
      await file.writeAsString(csvContent);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject:
            'UHC Report - ${DateFormat('MMM d, yyyy').format(DateTime.now())}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report generated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<String> _generateAppointmentsReport() async {
    final snapshot = await _firestore
        .collection('appointments')
        .where(
          'appointmentDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate),
        )
        .where(
          'appointmentDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endDate),
        )
        .orderBy('appointmentDate', descending: true)
        .get();

    final buffer = StringBuffer();
    buffer.writeln(
      'ID,Patient Name,Patient Email,Doctor Name,Department,Date,Time Slot,Status,Type,Notes',
    );

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final date = (data['appointmentDate'] as Timestamp?)?.toDate();
      buffer.writeln(
        '${doc.id},'
        '${_escapeCsv(data['patientName'] ?? '')},'
        '${_escapeCsv(data['patientEmail'] ?? '')},'
        '${_escapeCsv(data['doctorName'] ?? '')},'
        '${_escapeCsv(data['department'] ?? '')},'
        '${date != null ? DateFormat('yyyy-MM-dd').format(date) : ''},'
        '${_escapeCsv(data['timeSlot'] ?? '')},'
        '${data['status'] ?? ''},'
        '${data['type'] ?? ''},'
        '${_escapeCsv(data['notes'] ?? '')}',
      );
    }

    return buffer.toString();
  }

  Future<String> _generateDoctorsReport() async {
    final snapshot =
        await _firestore.collection('doctors').orderBy('name').get();

    final buffer = StringBuffer();
    buffer.writeln(
      'ID,Name,Email,Specialization,Department,Experience (Years),Bio,Available,Active',
    );

    for (final doc in snapshot.docs) {
      final data = doc.data();
      buffer.writeln(
        '${doc.id},'
        '${_escapeCsv(data['name'] ?? '')},'
        '${_escapeCsv(data['email'] ?? '')},'
        '${_escapeCsv(data['specialization'] ?? '')},'
        '${_escapeCsv(data['department'] ?? '')},'
        '${data['experienceYears'] ?? 0},'
        '${_escapeCsv(data['bio'] ?? '')},'
        '${data['isAvailable'] ?? true},'
        '${data['isActive'] ?? true}',
      );
    }

    return buffer.toString();
  }

  Future<String> _generateUsersReport() async {
    final snapshot = await _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .get();

    final buffer = StringBuffer();
    buffer.writeln(
      'ID,Full Name,Email,Phone,Role,Blood Type,Active,Created At',
    );

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      buffer.writeln(
        '${doc.id},'
        '${_escapeCsv(data['fullName'] ?? '')},'
        '${_escapeCsv(data['email'] ?? '')},'
        '${_escapeCsv(data['phoneNumber'] ?? '')},'
        '${data['role'] ?? ''},'
        '${data['bloodType'] ?? ''},'
        '${data['isActive'] ?? true},'
        '${createdAt != null ? DateFormat('yyyy-MM-dd').format(createdAt) : ''}',
      );
    }

    return buffer.toString();
  }

  Future<String> _generateRevenueReport() async {
    final snapshot = await _firestore
        .collection('appointments')
        .where(
          'appointmentDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate),
        )
        .where(
          'appointmentDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endDate),
        )
        .where('status', isEqualTo: 'completed')
        .get();

    // Group by department
    final Map<String, Map<String, dynamic>> departmentStats = {};
    const consultationFee = 50.0; // Mock fee

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final department = data['department'] ?? 'Unknown';

      if (!departmentStats.containsKey(department)) {
        departmentStats[department] = {'count': 0, 'revenue': 0.0};
      }
      departmentStats[department]!['count']++;
      departmentStats[department]!['revenue'] += consultationFee;
    }

    final buffer = StringBuffer();
    buffer.writeln('Department,Appointments,Revenue (\$)');

    int totalAppointments = 0;
    double totalRevenue = 0;

    for (final entry in departmentStats.entries) {
      buffer.writeln(
        '${_escapeCsv(entry.key)},'
        '${entry.value['count']},'
        '${entry.value['revenue'].toStringAsFixed(2)}',
      );
      totalAppointments += entry.value['count'] as int;
      totalRevenue += entry.value['revenue'] as double;
    }

    buffer.writeln('');
    buffer.writeln(
      'TOTAL,$totalAppointments,${totalRevenue.toStringAsFixed(2)}',
    );
    buffer.writeln('');
    buffer.writeln(
      'Report Period: ${DateFormat('MMM d, yyyy').format(_startDate)} - ${DateFormat('MMM d, yyyy').format(_endDate)}',
    );

    return buffer.toString();
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

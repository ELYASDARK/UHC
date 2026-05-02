import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../utils/save_file.dart';

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
      'id': 'departments',
      'title': 'Departments Report',
      'icon': Icons.business,
      'description':
          'Department list with doctor count and appointment summary',
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
              child: Builder(
                builder: (context) {
                  final canExport = context.read<AuthProvider>().currentUser
                          ?.hasPermission('reports.export') ??
                      false;
                  return ElevatedButton.icon(
                    onPressed: canExport
                        ? (_isGenerating ? null : _generateReport)
                        : null,
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
                      _isGenerating
                          ? 'Generating...'
                          : canExport
                              ? 'Generate Report'
                              : 'Export Permission Required',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
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
                      'Reports are exported as Excel (.xlsx) files that can be opened in Microsoft Excel or Google Sheets.',
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

  // ---------------------------------------------------------------------------
  // Excel generation
  // ---------------------------------------------------------------------------

  Future<void> _generateReport() async {
    setState(() => _isGenerating = true);

    try {
      final workbook = xlsio.Workbook();
      String fileName = '';
      String reportTitle = '';

      switch (_selectedReportType) {
        case 'appointments':
          reportTitle = 'Appointments Report';
          fileName = 'appointments_report';
          await _fillAppointmentsSheet(workbook);
          break;
        case 'doctors':
          reportTitle = 'Doctors Report';
          fileName = 'doctors_report';
          await _fillDoctorsSheet(workbook);
          break;
        case 'users':
          reportTitle = 'Users Report';
          fileName = 'users_report';
          await _fillUsersSheet(workbook);
          break;
        case 'departments':
          reportTitle = 'Departments Report';
          fileName = 'departments_report';
          await _fillDepartmentsSheet(workbook);
          break;
      }

      // Save workbook to bytes
      final bytes = workbook.saveAsStream();
      workbook.dispose();

      // Save & share (web = download, mobile = share sheet)
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      await saveAndShareFile(
        bytes,
        '${fileName}_$dateStr.xlsx',
        subject:
            'UHC $reportTitle - ${DateFormat('MMM d, yyyy').format(DateTime.now())}',
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

  // ---------------------------------------------------------------------------
  // Paginated Firestore fetch
  // ---------------------------------------------------------------------------

  Future<List<QueryDocumentSnapshot>> _paginatedFetch(
    Query query, {
    int batchSize = 5000,
  }) async {
    final allDocs = <QueryDocumentSnapshot>[];
    DocumentSnapshot? lastDoc;

    while (true) {
      Query batchQuery = query.limit(batchSize);
      if (lastDoc != null) {
        batchQuery = batchQuery.startAfterDocument(lastDoc);
      }
      final snapshot = await batchQuery.get();
      allDocs.addAll(snapshot.docs);
      if (snapshot.docs.length < batchSize) break;
      lastDoc = snapshot.docs.last;
    }

    return allDocs;
  }

  // ---------------------------------------------------------------------------
  // Styling helpers
  // ---------------------------------------------------------------------------

  /// Hex colors for styling (#RRGGBB format for Syncfusion XlsIO)
  static const String _primaryHex = '#2196F3'; // Blue
  static const String _headerTextHex = '#FFFFFF'; // White
  static const String _subtitleHex = '#757575'; // Gray
  static const String _altRowHex = '#F5F7FA'; // Light gray bg
  static const String _borderHex = '#E0E0E0'; // Light border

  /// Sets up the sheet with a title row, subtitle, and styled header row.
  /// Returns the 0-based row index of the first data row.
  int _setupSheet({
    required xlsio.Worksheet sheet,
    required String title,
    required List<String> headers,
    required List<double> columnWidths,
  }) {
    final dateFmt = DateFormat('MMM d, yyyy');
    final periodText =
        'Period: ${dateFmt.format(_startDate)} – ${dateFmt.format(_endDate)}';
    final lastCol = headers.length;

    // Row 1 — Title
    final titleCell = sheet.getRangeByIndex(1, 1, 1, lastCol);
    titleCell.merge();
    titleCell.setText(title);
    titleCell.cellStyle.fontSize = 16;
    titleCell.cellStyle.bold = true;
    titleCell.cellStyle.fontColor = _primaryHex;
    titleCell.cellStyle.hAlign = xlsio.HAlignType.left;
    titleCell.cellStyle.vAlign = xlsio.VAlignType.center;
    sheet.getRangeByIndex(1, 1).rowHeight = 32;

    // Row 2 — Subtitle (period)
    final subtitleCell = sheet.getRangeByIndex(2, 1, 2, lastCol);
    subtitleCell.merge();
    subtitleCell.setText(periodText);
    subtitleCell.cellStyle.fontSize = 10;
    subtitleCell.cellStyle.fontColor = _subtitleHex;
    subtitleCell.cellStyle.hAlign = xlsio.HAlignType.left;

    // Row 3 — Spacer
    sheet.getRangeByIndex(3, 1).rowHeight = 8;

    // Row 4 — Headers
    for (var col = 0; col < headers.length; col++) {
      final cell = sheet.getRangeByIndex(4, col + 1);
      cell.setText(headers[col]);
      cell.cellStyle.bold = true;
      cell.cellStyle.fontSize = 11;
      cell.cellStyle.fontColor = _headerTextHex;
      cell.cellStyle.backColor = _primaryHex;
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = _borderHex;
    }
    sheet.getRangeByIndex(4, 1).rowHeight = 28;

    // Column widths
    for (var i = 0; i < columnWidths.length; i++) {
      sheet.getRangeByIndex(1, i + 1).columnWidth = columnWidths[i];
    }

    return 5; // first data row (1-indexed)
  }

  /// Apply alternating row style + borders to a data cell.
  void _styleDataCell(
    xlsio.Range cell, {
    required int rowIndex,
    xlsio.HAlignType hAlign = xlsio.HAlignType.left,
  }) {
    cell.cellStyle.fontSize = 10;
    cell.cellStyle.hAlign = hAlign;
    cell.cellStyle.vAlign = xlsio.VAlignType.center;
    cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    cell.cellStyle.borders.all.color = _borderHex;
    if (rowIndex.isOdd) {
      cell.cellStyle.backColor = _altRowHex;
    }
  }

  /// Add a summary footer row at the bottom showing total records.
  void _addFooter(xlsio.Worksheet sheet, int row, int colCount, int total) {
    final range = sheet.getRangeByIndex(row + 1, 1, row + 1, colCount);
    range.merge();
    range.setText('Total Records: $total');
    range.cellStyle.bold = true;
    range.cellStyle.fontSize = 10;
    range.cellStyle.fontColor = _subtitleHex;
    range.cellStyle.hAlign = xlsio.HAlignType.right;
  }

  // ---------------------------------------------------------------------------
  // Report builders
  // ---------------------------------------------------------------------------

  Future<void> _fillAppointmentsSheet(xlsio.Workbook workbook) async {
    final sheet = workbook.worksheets[0];
    sheet.name = 'Appointments';

    final headers = [
      'ID',
      'Patient Name',
      'Patient Email',
      'Doctor',
      'Department',
      'Date',
      'Time Slot',
      'Status',
      'Type',
      'Notes',
    ];
    final widths = [14.0, 22.0, 28.0, 22.0, 18.0, 14.0, 12.0, 12.0, 12.0, 30.0];

    final dataRow = _setupSheet(
      sheet: sheet,
      title: 'UHC — Appointments Report',
      headers: headers,
      columnWidths: widths,
    );

    final query = _firestore
        .collection('appointments')
        .where(
          'appointmentDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate),
        )
        .where(
          'appointmentDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endDate),
        )
        .orderBy('appointmentDate', descending: true);

    final docs = await _paginatedFetch(query);
    final dateFmt = DateFormat('yyyy-MM-dd');

    for (var i = 0; i < docs.length; i++) {
      final r = dataRow + i;
      final data = docs[i].data() as Map<String, dynamic>;
      final date = (data['appointmentDate'] as Timestamp?)?.toDate();

      final values = [
        docs[i].id,
        data['patientName'] ?? '',
        data['patientEmail'] ?? '',
        data['doctorName'] ?? '',
        data['department'] ?? '',
        date != null ? dateFmt.format(date) : '',
        data['timeSlot'] ?? '',
        data['status'] ?? '',
        data['type'] ?? '',
        data['notes'] ?? '',
      ];

      for (var col = 0; col < values.length; col++) {
        final cell = sheet.getRangeByIndex(r, col + 1);
        cell.setText(values[col].toString());
        _styleDataCell(cell, rowIndex: i);
      }
    }

    _addFooter(sheet, dataRow + docs.length, headers.length, docs.length);
  }

  Future<void> _fillDoctorsSheet(xlsio.Workbook workbook) async {
    final sheet = workbook.worksheets[0];
    sheet.name = 'Doctors';

    final headers = [
      'ID',
      'Name',
      'Email',
      'Specialization',
      'Department',
      'Experience (Yrs)',
      'Bio',
      'Available',
      'Active',
    ];
    final widths = [14.0, 22.0, 28.0, 22.0, 18.0, 16.0, 35.0, 11.0, 11.0];

    final dataRow = _setupSheet(
      sheet: sheet,
      title: 'UHC — Doctors Report',
      headers: headers,
      columnWidths: widths,
    );

    final snapshot =
        await _firestore.collection('doctors').orderBy('name').get();

    for (var i = 0; i < snapshot.docs.length; i++) {
      final r = dataRow + i;
      final doc = snapshot.docs[i];
      final data = doc.data();

      final values = [
        doc.id,
        data['name'] ?? '',
        data['email'] ?? '',
        data['specialization'] ?? '',
        data['department'] ?? '',
        (data['experienceYears'] ?? 0).toString(),
        data['bio'] ?? '',
        (data['isAvailable'] ?? true) ? 'Yes' : 'No',
        (data['isActive'] ?? true) ? 'Yes' : 'No',
      ];

      for (var col = 0; col < values.length; col++) {
        final cell = sheet.getRangeByIndex(r, col + 1);
        cell.setText(values[col].toString());
        _styleDataCell(cell, rowIndex: i);
      }
    }

    _addFooter(
      sheet,
      dataRow + snapshot.docs.length,
      headers.length,
      snapshot.docs.length,
    );
  }

  Future<void> _fillUsersSheet(xlsio.Workbook workbook) async {
    final sheet = workbook.worksheets[0];
    sheet.name = 'Users';

    final headers = [
      'ID',
      'Full Name',
      'Email',
      'Phone',
      'Role',
      'Blood Type',
      'Active',
      'Created At',
    ];
    final widths = [14.0, 22.0, 28.0, 16.0, 12.0, 12.0, 10.0, 14.0];

    final dataRow = _setupSheet(
      sheet: sheet,
      title: 'UHC — Users Report',
      headers: headers,
      columnWidths: widths,
    );

    final query = _firestore
        .collection('users')
        .orderBy('createdAt', descending: true);
    final docs = await _paginatedFetch(query);
    final dateFmt = DateFormat('yyyy-MM-dd');

    for (var i = 0; i < docs.length; i++) {
      final r = dataRow + i;
      final data = docs[i].data() as Map<String, dynamic>;
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

      final values = [
        docs[i].id,
        data['fullName'] ?? '',
        data['email'] ?? '',
        data['phoneNumber'] ?? '',
        data['role'] ?? '',
        data['bloodType'] ?? '',
        (data['isActive'] ?? true) ? 'Yes' : 'No',
        createdAt != null ? dateFmt.format(createdAt) : '',
      ];

      for (var col = 0; col < values.length; col++) {
        final cell = sheet.getRangeByIndex(r, col + 1);
        cell.setText(values[col].toString());
        _styleDataCell(cell, rowIndex: i);
      }
    }

    _addFooter(sheet, dataRow + docs.length, headers.length, docs.length);
  }

  Future<void> _fillDepartmentsSheet(xlsio.Workbook workbook) async {
    final sheet = workbook.worksheets[0];
    sheet.name = 'Departments';

    final headers = [
      'ID',
      'Department Name',
      'Doctors',
      'Appointments',
      'Active',
    ];
    final widths = [14.0, 28.0, 12.0, 14.0, 10.0];

    final dataRow = _setupSheet(
      sheet: sheet,
      title: 'UHC — Departments Report',
      headers: headers,
      columnWidths: widths,
    );

    // Fetch departments
    final deptSnapshot =
        await _firestore.collection('departments').orderBy('name').get();

    // Count doctors per department
    final doctorSnapshot = await _firestore.collection('doctors').get();
    final doctorsByDept = <String, int>{};
    for (final doc in doctorSnapshot.docs) {
      final dept = (doc.data()['department'] ?? '') as String;
      if (dept.isNotEmpty) {
        doctorsByDept[dept] = (doctorsByDept[dept] ?? 0) + 1;
      }
    }

    // Count appointments per department in date range
    final apptQuery = _firestore
        .collection('appointments')
        .where(
          'appointmentDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate),
        )
        .where(
          'appointmentDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endDate),
        )
        .orderBy('appointmentDate', descending: true);

    final apptDocs = await _paginatedFetch(apptQuery);
    final apptsByDept = <String, int>{};
    for (final doc in apptDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final dept = (data['department'] ?? '') as String;
      if (dept.isNotEmpty) {
        apptsByDept[dept] = (apptsByDept[dept] ?? 0) + 1;
      }
    }

    for (var i = 0; i < deptSnapshot.docs.length; i++) {
      final r = dataRow + i;
      final doc = deptSnapshot.docs[i];
      final data = doc.data();
      final name = data['name'] ?? '';

      final values = [
        doc.id,
        name,
        (doctorsByDept[name] ?? 0).toString(),
        (apptsByDept[name] ?? 0).toString(),
        (data['isActive'] ?? true) ? 'Yes' : 'No',
      ];

      for (var col = 0; col < values.length; col++) {
        final cell = sheet.getRangeByIndex(r, col + 1);
        cell.setText(values[col].toString());
        _styleDataCell(
          cell,
          rowIndex: i,
          hAlign: col >= 2
              ? xlsio.HAlignType.center
              : xlsio.HAlignType.left,
        );
      }
    }

    _addFooter(
      sheet,
      dataRow + deptSnapshot.docs.length,
      headers.length,
      deptSnapshot.docs.length,
    );
  }
}

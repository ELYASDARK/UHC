import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import 'department_form_dialog.dart';
import '../../core/widgets/loading_skeleton.dart';

/// Department management screen for admin
class DepartmentManagementScreen extends StatefulWidget {
  const DepartmentManagementScreen({super.key});

  @override
  State<DepartmentManagementScreen> createState() =>
      _DepartmentManagementScreenState();
}

class _DepartmentManagementScreenState
    extends State<DepartmentManagementScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'active', 'inactive'

  /// Dynamically loaded doctor counts per department key
  Map<String, int> _doctorCounts = {};

  @override
  void initState() {
    super.initState();
    _loadDoctorCounts();
    _cleanupSampleDataField();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Query the 'doctors' collection to count doctors per department
  Future<void> _loadDoctorCounts() async {
    try {
      final snapshot = await _firestore.collection('doctors').get();
      final counts = <String, int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final dept = (data['department'] ?? '').toString();
        if (dept.isNotEmpty) {
          // Store under multiple normalized keys for robust matching
          final lowerDept = dept.toLowerCase();
          final noSpaces = dept.replaceAll(' ', '').toLowerCase();
          counts[lowerDept] = (counts[lowerDept] ?? 0) + 1;
          if (noSpaces != lowerDept) {
            counts[noSpaces] = (counts[noSpaces] ?? 0) + 1;
          }
        }
      }
      debugPrint('Doctor counts per department: $counts');
      if (mounted) {
        setState(() => _doctorCounts = counts);
      }
    } catch (e) {
      debugPrint('Error loading doctor counts: $e');
    }
  }

  /// Get the real doctor count for a department by trying multiple matching strategies
  int _getRealDoctorCount(Map<String, dynamic> data) {
    final storedKey = (data['key'] ?? '').toString().toLowerCase();
    final name = (data['name'] ?? '').toString();

    // Generate camelCase key from name (e.g., "General Medicine" → "generalmedicine")
    final words = name.split(' ');
    final camelCaseKey = words.isNotEmpty
        ? (words.first.toLowerCase() +
                words
                    .skip(1)
                    .map((w) => w.isNotEmpty
                        ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
                        : '')
                    .join(''))
            .toLowerCase()
        : '';

    // Also try: just the lowercase name without spaces
    final flatName = name.replaceAll(' ', '').toLowerCase();

    // Return the first match found
    if (_doctorCounts.containsKey(storedKey) && storedKey.isNotEmpty) {
      return _doctorCounts[storedKey]!;
    }
    if (_doctorCounts.containsKey(camelCaseKey) && camelCaseKey.isNotEmpty) {
      return _doctorCounts[camelCaseKey]!;
    }
    if (_doctorCounts.containsKey(flatName) && flatName.isNotEmpty) {
      return _doctorCounts[flatName]!;
    }
    return 0;
  }

  /// One-time cleanup: fix department keys and remove legacy fields from Firestore
  Future<void> _cleanupSampleDataField() async {
    try {
      final snapshot = await _firestore.collection('departments').get();
      final batch = _firestore.batch();
      bool hasChanges = false;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final updates = <String, dynamic>{};

        // Remove legacy isSampleData field
        if (data.containsKey('isSampleData')) {
          updates['isSampleData'] = FieldValue.delete();
        }

        // Fix department key to camelCase format if needed
        final name = (data['name'] ?? '').toString();
        final currentKey = (data['key'] ?? '').toString();
        if (name.isNotEmpty) {
          final words = name.split(' ');
          final correctKey = words.first.toLowerCase() +
              words
                  .skip(1)
                  .map((w) => w.isNotEmpty
                      ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
                      : '')
                  .join('');
          if (currentKey != correctKey) {
            updates['key'] = correctKey;
            debugPrint('Fixing department key: "$currentKey" → "$correctKey"');
          }
        }

        if (updates.isNotEmpty) {
          batch.update(doc.reference, updates);
          hasChanges = true;
        }
      }
      if (hasChanges) {
        await batch.commit();
        debugPrint('Department cleanup completed');
        // Reload doctor counts after key fixes
        _loadDoctorCounts();
      }
    } catch (e) {
      debugPrint('Error during department cleanup: $e');
    }
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  IconData _getIconData(String iconName) {
    return departmentIcons[iconName] ?? Icons.medical_services;
  }

  Stream<QuerySnapshot> _getDepartmentsStream() {
    return _firestore.collection('departments').orderBy('name').snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Department Management'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const DepartmentFormDialog(),
          );
        },
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text(
          'Add Department',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        shape: const StadiumBorder(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search departments...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Filter Chips
          if (_statusFilter != 'all')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  Chip(
                    label: Text(
                      _statusFilter.toUpperCase(),
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: isDark
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.primary.withValues(alpha: 0.1),
                    side: BorderSide(
                      color: isDark
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : AppColors.primary.withValues(alpha: 0.2),
                    ),
                    onDeleted: () => setState(() => _statusFilter = 'all'),
                    deleteIconColor:
                        isDark ? Colors.white70 : AppColors.primary,
                  ),
                ],
              ),
            ),

          // Departments List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getDepartmentsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return SkeletonList(
                    itemBuilder: (context, index) =>
                        const CardSkeleton(height: 100),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.business,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        const Text('No departments found'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) =>
                                  const DepartmentFormDialog(),
                            );
                          },
                          icon: const Icon(Icons.add_business),
                          label: const Text('Add Department'),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final matchesSearch =
                      name.contains(_searchQuery.toLowerCase());

                  if (_statusFilter == 'active') {
                    return matchesSearch && (data['isActive'] ?? true);
                  } else if (_statusFilter == 'inactive') {
                    return matchesSearch && !(data['isActive'] ?? true);
                  }
                  return matchesSearch;
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        const Text('No matching departments'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(
                    top: 8,
                    left: 16,
                    right: 16,
                    bottom: 80,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _buildDepartmentCard(context, doc.id, data, isDark);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCard(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final isActive = data['isActive'] ?? true;
    final colorHex = data['colorHex'] ?? '#2196F3';
    final deptColor = _hexToColor(colorHex);
    final iconName = data['iconName'] ?? 'medical_services';
    final doctorCount = _getRealDoctorCount(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Stack(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: deptColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _getIconData(iconName),
                color: deptColor,
                size: 28,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: isActive ? AppColors.success : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          data['name'] ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data['description'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: deptColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$doctorCount doctors',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: deptColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (isActive ? AppColors.success : Colors.grey)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isActive ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isActive ? AppColors.success : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'view':
                _showDepartmentDetails(context, id, data);
                break;
              case 'edit':
                showDialog(
                  context: context,
                  builder: (context) =>
                      DepartmentFormDialog(id: id, data: data),
                );
                break;
              case 'toggle':
                _toggleDepartmentStatus(id, isActive);
                break;
              case 'delete':
                _confirmDelete(id, data['name'] ?? 'this department');
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 18),
                  SizedBox(width: 8),
                  Text('View Details'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'toggle',
              child: Row(
                children: [
                  Icon(
                    isActive ? Icons.block : Icons.check_circle,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 18, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String tempFilter = _statusFilter;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Filter Departments'),
              content: RadioGroup<String>(
                groupValue: tempFilter,
                onChanged: (value) {
                  if (value != null) setState(() => tempFilter = value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      title: const Text('All'),
                      value: 'all',
                      activeColor: AppColors.primary,
                    ),
                    RadioListTile<String>(
                      title: const Text('Active Only'),
                      value: 'active',
                      activeColor: AppColors.primary,
                    ),
                    RadioListTile<String>(
                      title: const Text('Inactive Only'),
                      value: 'inactive',
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    this.setState(() => _statusFilter = 'all');
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    this.setState(() {
                      _statusFilter = tempFilter;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleDepartmentStatus(String id, bool currentStatus) async {
    await _firestore.collection('departments').doc(id).update({
      'isActive': !currentStatus,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentStatus ? 'Department deactivated' : 'Department activated',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _confirmDelete(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Department'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "$name"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. Consider deactivating instead.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firestore.collection('departments').doc(id).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Department deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting department: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  /// Show department details in a bottom sheet
  void _showDepartmentDetails(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = data['name'] ?? 'Unknown';
    final description = data['description'] ?? 'N/A';
    final colorHex = data['colorHex'] ?? '#2196F3';
    final deptColor = _hexToColor(colorHex);
    final iconName = data['iconName'] ?? 'medical_services';
    final isActive = data['isActive'] ?? true;
    final doctorCount = _getRealDoctorCount(data);
    final rawHours = data['workingHours'] as Map<String, dynamic>? ?? {};
    final workingHours = <String, String>{};
    for (final entry in rawHours.entries) {
      final value = entry.value;
      if (value is String) {
        workingHours[entry.key] = value;
      } else if (value is Map) {
        final start = value['start'] ?? '';
        final end = value['end'] ?? '';
        workingHours[entry.key] = '$start - $end';
      }
    }
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Department Icon
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: deptColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          _getIconData(iconName),
                          size: 50,
                          color: deptColor,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Department Name
                      Text(
                        name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 8),

                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (isActive ? AppColors.success : Colors.grey)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isActive ? AppColors.success : Colors.grey,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Description
                      if (description != 'N/A' &&
                          description.toString().isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Description',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[800]?.withValues(alpha: 0.3)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            description.toString(),
                            style: TextStyle(
                              color:
                                  isDark ? Colors.grey[300] : Colors.grey[700],
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Details Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey[800]?.withValues(alpha: 0.3)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            _buildDetailRow(
                              'Doctors',
                              '$doctorCount',
                              isDark,
                            ),
                            _buildDivider(isDark),
                            _buildDetailRow(
                              'Color',
                              colorHex,
                              isDark,
                              valueColor: deptColor,
                            ),
                            if (createdAt != null) ...[
                              _buildDivider(isDark),
                              _buildDetailRow(
                                'Created',
                                '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                                isDark,
                              ),
                            ],
                            if (updatedAt != null) ...[
                              _buildDivider(isDark),
                              _buildDetailRow(
                                'Updated',
                                '${updatedAt.day}/${updatedAt.month}/${updatedAt.year}',
                                isDark,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Working Hours Section
                      if (workingHours.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Working Hours',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[800]?.withValues(alpha: 0.3)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: workingHours.entries.map((entry) {
                              final dayName = entry.key[0].toUpperCase() +
                                  entry.key.substring(1);
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      dayName,
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      entry.value.toString(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _toggleDepartmentStatus(id, isActive);
                        },
                        icon: Icon(
                          isActive ? Icons.block : Icons.check_circle,
                          color: isActive ? AppColors.error : AppColors.success,
                        ),
                        label: Text(
                          isActive ? 'Deactivate' : 'Activate',
                          style: TextStyle(
                            color:
                                isActive ? AppColors.error : AppColors.success,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(
                            color:
                                isActive ? AppColors.error : AppColors.success,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (context) =>
                                DepartmentFormDialog(id: id, data: data),
                          );
                        },
                        icon: const Icon(Icons.edit, color: Colors.white),
                        label: const Text('Edit'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    bool isDark, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: valueColor ?? (isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      color: isDark ? Colors.grey[700] : Colors.grey[200],
      height: 1,
    );
  }
}

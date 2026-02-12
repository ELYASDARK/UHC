import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';
import '../../services/doctor_functions_service.dart';
import 'doctor_form_dialog.dart';

/// Doctor management screen for admin
class DoctorManagementScreen extends StatefulWidget {
  const DoctorManagementScreen({super.key});

  @override
  State<DoctorManagementScreen> createState() => _DoctorManagementScreenState();
}

class _DoctorManagementScreenState extends State<DoctorManagementScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  final _doctorFunctionsService = DoctorFunctionsService();
  String _searchQuery = '';
  Set<Department> _selectedDepartments = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Management'),
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
            builder: (context) => const DoctorFormDialog(),
          );
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Add Doctor'),
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
                hintText: 'Search doctors...',
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
          if (_selectedDepartments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: _selectedDepartments.map((dept) {
                  return Chip(
                    label: Text(
                      dept.name.toUpperCase(),
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
                    onDeleted: () =>
                        setState(() => _selectedDepartments.remove(dept)),
                    deleteIconColor:
                        isDark ? Colors.white70 : AppColors.primary,
                  );
                }).toList(),
              ),
            ),

          // Doctors List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getDoctorsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.medical_services,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        const Text('No doctors found'),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final matchesSearch = name.contains(
                    _searchQuery.toLowerCase(),
                  );

                  if (_selectedDepartments.isEmpty) return matchesSearch;

                  final deptName = data['department'] as String?;
                  final dept = Department.values.firstWhere(
                    (d) => d.name == deptName,
                    orElse: () => Department.generalMedicine,
                  );

                  return matchesSearch && _selectedDepartments.contains(dept);
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.only(
                    top: 16,
                    left: 16,
                    right: 16,
                    bottom: 60, // Extra padding for FAB
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _buildDoctorCard(context, doc.id, data, isDark);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot> _getDoctorsStream() {
    return _firestore.collection('doctors').orderBy('name').snapshots();
  }

  Widget _buildDoctorCard(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
    bool isDark,
  ) {
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
            CircleAvatar(
              radius: 28,
              backgroundImage: data['photoUrl'] != null &&
                      (data['photoUrl'] as String).isNotEmpty
                  ? NetworkImage(data['photoUrl'])
                  : null,
              child: data['photoUrl'] == null ||
                      (data['photoUrl'] as String).isEmpty
                  ? const Icon(Icons.person)
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: (data['isActive'] ?? true)
                      ? AppColors.success
                      : Colors.grey,
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
          'Dr. ${data['name'] ?? 'Unknown'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(data['specialization'] ?? 'General')],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'view':
                _showDoctorDetails(context, id, data);
                break;
              case 'edit':
                showDialog(
                  context: context,
                  builder: (context) => DoctorFormDialog(id: id, data: data),
                );
                break;
              case 'delete':
                _confirmDelete(id, data['name'] ?? 'this doctor', data);
                break;
              case 'toggle':
                _toggleDoctorStatus(id, data['isActive'] ?? true);
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
                    data['isActive'] == true ? Icons.block : Icons.check_circle,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(data['isActive'] == true ? 'Deactivate' : 'Activate'),
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
        final tempSelected = Set<Department>.from(_selectedDepartments);
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Filter by Department'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: Department.values.map((dept) {
                    return CheckboxListTile(
                      title: Text(dept.name),
                      value: tempSelected.contains(dept),
                      activeColor: AppColors.primary,
                      onChanged: (bool? selected) {
                        setState(() {
                          if (selected == true) {
                            tempSelected.add(dept);
                          } else {
                            tempSelected.remove(dept);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    this.setState(() => _selectedDepartments.clear());
                    Navigator.pop(context);
                  },
                  child: const Text('Clear All'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    this.setState(() {
                      _selectedDepartments = tempSelected;
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

  Future<void> _confirmDelete(
    String id,
    String name,
    Map<String, dynamic> data,
  ) async {
    final hasAuthAccount =
        data['userId'] != null && data['userId'].toString().isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Doctor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete Dr. $name?'),
            if (hasAuthAccount) ...[
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
                        'This will also delete the doctor\'s login account.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
        if (hasAuthAccount) {
          // Use Cloud Function to delete auth account, user doc, and doctor doc
          await _doctorFunctionsService.deleteDoctorAccount(doctorId: id);
        } else {
          // Just delete the doctor document
          await _firestore.collection('doctors').doc(id).delete();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Doctor deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } on DoctorFunctionException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.userMessage),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting doctor: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleDoctorStatus(String id, bool currentStatus) async {
    await _firestore.collection('doctors').doc(id).update({
      'isActive': !currentStatus,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentStatus ? 'Doctor deactivated' : 'Doctor activated',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  /// Show doctor details in a bottom sheet
  Future<void> _showDoctorDetails(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) async {
    // Capture context values before async gap
    final capturedContext = context;
    final isDark = Theme.of(capturedContext).brightness == Brightness.dark;
    final name = data['name'] ?? 'Unknown';
    final email = data['email'] ?? 'N/A';
    final phone = data['phoneNumber'] ?? 'N/A';
    final department = data['department'] ?? 'N/A';
    final specialization = data['specialization'] ?? 'N/A';
    final experienceYears = data['experienceYears'] ?? 0;
    final consultationFee = data['consultationFee'] ?? 0;
    final bio = data['bio'] ?? 'N/A';
    final qualifications =
        (data['qualifications'] as List<dynamic>?)?.cast<String>() ?? [];
    final isActive = data['isActive'] ?? true;
    final photoUrl = data['photoUrl'] as String?;
    final userId = data['userId'] as String?;

    // Fetch dateOfBirth - first check users collection, then fallback to doctors collection
    String dateOfBirth = 'N/A';

    // First try to get from users collection
    if (userId != null) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists && userDoc.data()?['dateOfBirth'] != null) {
          final dob = userDoc.data()!['dateOfBirth'];
          if (dob is DateTime) {
            dateOfBirth = '${dob.day}/${dob.month}/${dob.year}';
          } else if (dob.toDate != null) {
            final date = dob.toDate() as DateTime;
            dateOfBirth = '${date.day}/${date.month}/${date.year}';
          }
        }
      } catch (_) {
        // Continue to fallback
      }
    }

    // Fallback: check doctors collection (for existing data)
    if (dateOfBirth == 'N/A' && data['dateOfBirth'] != null) {
      try {
        final dob = data['dateOfBirth'];
        if (dob is DateTime) {
          dateOfBirth = '${dob.day}/${dob.month}/${dob.year}';
        } else if (dob.toDate != null) {
          final date = dob.toDate() as DateTime;
          dateOfBirth = '${date.day}/${date.month}/${date.year}';
        }
      } catch (_) {
        dateOfBirth = 'N/A';
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      // ignore: use_build_context_synchronously
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
                      // Doctor Photo
                      CircleAvatar(
                        radius: 50,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.1),
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'D',
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              )
                            : null,
                      ),

                      const SizedBox(height: 16),

                      // Doctor Name
                      Text(
                        'Dr. $name',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),

                      const SizedBox(height: 4),

                      // Specialization
                      Text(
                        specialization,
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(height: 24),

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
                            _buildDetailRow('Email', email, isDark),
                            _buildDivider(isDark),
                            _buildDetailRow('Phone', phone, isDark),
                            _buildDivider(isDark),
                            _buildDetailRow(
                                'Date of Birth', dateOfBirth, isDark),
                            _buildDivider(isDark),
                            _buildDetailRow('Department',
                                _formatDepartment(department), isDark),
                            _buildDivider(isDark),
                            _buildDetailRow(
                                'Experience', '$experienceYears years', isDark),
                            _buildDivider(isDark),
                            _buildDetailRow(
                                'Consultation Fee',
                                '\$${consultationFee.toStringAsFixed(0)}',
                                isDark),
                            _buildDivider(isDark),
                            _buildDetailRow(
                              'Status',
                              isActive ? 'Active' : 'Inactive',
                              isDark,
                              valueColor:
                                  isActive ? AppColors.success : Colors.grey,
                            ),
                          ],
                        ),
                      ),

                      // Bio Section
                      if (bio != 'N/A' && bio.toString().isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Biography',
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
                            bio.toString(),
                            style: TextStyle(
                              color:
                                  isDark ? Colors.grey[300] : Colors.grey[700],
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],

                      // Qualifications Section
                      if (qualifications.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Qualifications',
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: qualifications
                                .map((q) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle,
                                              size: 16,
                                              color: AppColors.primary),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              q,
                                              style: TextStyle(
                                                color: isDark
                                                    ? Colors.grey[300]
                                                    : Colors.grey[700],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark,
      {Color? valueColor}) {
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

  String _formatDepartment(String department) {
    // Convert camelCase to Title Case with spaces
    return department
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : word)
        .join(' ');
  }
}

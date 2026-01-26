import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';

/// Doctor management screen for admin
class DoctorManagementScreen extends StatefulWidget {
  const DoctorManagementScreen({super.key});

  @override
  State<DoctorManagementScreen> createState() => _DoctorManagementScreenState();
}

class _DoctorManagementScreenState extends State<DoctorManagementScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Department? _filterDepartment;

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
        onPressed: () => _showDoctorDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Doctor'),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
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
          if (_filterDepartment != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Chip(
                    label: Text(_filterDepartment!.name),
                    onDeleted: () => setState(() => _filterDepartment = null),
                    deleteIconColor: AppColors.primary,
                  ),
                ],
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
                  return name.contains(_searchQuery.toLowerCase());
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
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
    Query query = _firestore.collection('doctors');
    if (_filterDepartment != null) {
      query = query.where('department', isEqualTo: _filterDepartment!.name);
    }
    return query.orderBy('name').snapshots();
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
        leading: CircleAvatar(
          radius: 28,
          backgroundImage: data['photoUrl'] != null
              ? NetworkImage(data['photoUrl'])
              : null,
          child: data['photoUrl'] == null ? const Icon(Icons.person) : null,
        ),
        title: Text(
          'Dr. ${data['name'] ?? 'Unknown'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data['specialization'] ?? 'General'),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.star, size: 14, color: Colors.amber[600]),
                const SizedBox(width: 4),
                Text(
                  '${data['rating']?.toStringAsFixed(1) ?? '0.0'} • ${data['reviewCount'] ?? 0} reviews',
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
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _showDoctorDialog(context, id: id, data: data);
                break;
              case 'delete':
                _confirmDelete(id, data['name'] ?? 'this doctor');
                break;
              case 'toggle':
                _toggleDoctorStatus(id, data['isActive'] ?? true);
                break;
            }
          },
          itemBuilder: (context) => [
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
      builder: (context) => AlertDialog(
        title: const Text('Filter by Department'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: Department.values.map((dept) {
              return ListTile(
                title: Text(dept.name),
                leading: Radio<Department>(
                  value: dept,
                  groupValue: _filterDepartment,
                  onChanged: (value) {
                    setState(() => _filterDepartment = value);
                    Navigator.pop(context);
                  },
                ),
                onTap: () {
                  setState(() => _filterDepartment = dept);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _filterDepartment = null);
              Navigator.pop(context);
            },
            child: const Text('Clear Filter'),
          ),
        ],
      ),
    );
  }

  void _showDoctorDialog(
    BuildContext context, {
    String? id,
    Map<String, dynamic>? data,
  }) {
    final isEditing = id != null;
    final nameController = TextEditingController(text: data?['name'] ?? '');
    final specializationController = TextEditingController(
      text: data?['specialization'] ?? '',
    );
    final bioController = TextEditingController(text: data?['bio'] ?? '');
    final experienceController = TextEditingController(
      text: data?['yearsExperience']?.toString() ?? '',
    );
    final feeController = TextEditingController(
      text: data?['consultationFee']?.toString() ?? '',
    );
    Department selectedDepartment = Department.values.firstWhere(
      (d) => d.name == data?['department'],
      orElse: () => Department.generalMedicine,
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Doctor' : 'Add Doctor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: specializationController,
                  decoration: const InputDecoration(
                    labelText: 'Specialization *',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Department>(
                  initialValue: selectedDepartment,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: Department.values
                      .map(
                        (d) => DropdownMenuItem(value: d, child: Text(d.name)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedDepartment = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: experienceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Years Experience',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: feeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Consultation Fee (\$)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bioController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Bio'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    specializationController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Name and specialization are required'),
                    ),
                  );
                  return;
                }

                final doctorData = {
                  'name': nameController.text,
                  'specialization': specializationController.text,
                  'department': selectedDepartment.name,
                  'bio': bioController.text,
                  'yearsExperience':
                      int.tryParse(experienceController.text) ?? 0,
                  'consultationFee': double.tryParse(feeController.text) ?? 0.0,
                  'isActive': data?['isActive'] ?? true,
                  'rating': data?['rating'] ?? 0.0,
                  'reviewCount': data?['reviewCount'] ?? 0,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                if (isEditing) {
                  await _firestore
                      .collection('doctors')
                      .doc(id)
                      .update(doctorData);
                } else {
                  doctorData['createdAt'] = FieldValue.serverTimestamp();
                  doctorData['weeklySchedule'] = {};
                  await _firestore.collection('doctors').add(doctorData);
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEditing ? 'Doctor updated' : 'Doctor added',
                      ),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: Text(isEditing ? 'Update' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Doctor'),
        content: Text('Are you sure you want to delete Dr. $name?'),
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
      await _firestore.collection('doctors').doc(id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Doctor deleted'),
            backgroundColor: AppColors.success,
          ),
        );
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
}

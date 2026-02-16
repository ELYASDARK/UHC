import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/user_model.dart';
import 'user_form_dialog.dart';
import '../../core/widgets/loading_skeleton.dart';

/// User management screen for admin
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Set<UserRole> _selectedRoles = {};

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
        title: const Text('User Management'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
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
                hintText: 'Search users...',
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
          if (_selectedRoles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: _selectedRoles.map((role) {
                  return Chip(
                    label: Text(
                      role.name.toUpperCase(),
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
                        setState(() => _selectedRoles.remove(role)),
                    deleteIconColor:
                        isDark ? Colors.white70 : AppColors.primary,
                  );
                }).toList(),
              ),
            ),

          // Users List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getUsersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return SkeletonList(
                    itemBuilder: (context, index) =>
                        const CardSkeleton(height: 80),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('No users found'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _showAddUserDialog(),
                          icon: const Icon(Icons.person_add),
                          label: const Text('Add User'),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  // Exclude doctors - they are managed in Doctor Management
                  final roleStr = data['role'] as String? ?? 'student';
                  if (roleStr == 'doctor') return false;

                  final name = (data['fullName'] ?? data['email'] ?? '')
                      .toString()
                      .toLowerCase();
                  final matchesSearch = name.contains(
                    _searchQuery.toLowerCase(),
                  );

                  if (_selectedRoles.isEmpty) return matchesSearch;

                  final role = UserRole.values.firstWhere(
                    (r) => r.name == roleStr,
                    orElse: () => UserRole.student,
                  );
                  return matchesSearch && _selectedRoles.contains(role);
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _buildUserCard(context, doc.id, data, isDark);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddUserDialog(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add User', style: TextStyle(color: Colors.white)),
        shape: const StadiumBorder(),
      ),
    );
  }

  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (context) => const UserFormDialog(),
    );
  }

  void _showEditUserDialog(String id, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => UserFormDialog(id: id, data: data),
    );
  }

  Stream<QuerySnapshot> _getUsersStream() {
    // Get all users and filter on client side to avoid composite index issues
    return _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Widget _buildUserCard(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final role = UserRole.values.firstWhere(
      (r) => r.name == data['role'],
      orElse: () => UserRole.student,
    );
    final isActive = data['isActive'] ?? true;

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
              backgroundImage: data['photoUrl'] != null
                  ? NetworkImage(data['photoUrl'])
                  : null,
              child: data['photoUrl'] == null
                  ? Text(
                      (data['fullName'] ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : null,
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
          data['fullName'] ?? 'Unknown User',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data['email'] ?? ''),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getRoleColor(role).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                role.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _getRoleColor(role),
                ),
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'view':
                _showUserDetails(context, id, data, isDark);
                break;
              case 'edit':
                _showEditUserDialog(id, data);
                break;
              case 'toggle':
                _toggleUserStatus(id, isActive);
                break;
              case 'role':
                _changeUserRole(id, role);
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
                  Icon(isActive ? Icons.block : Icons.check_circle, size: 18),
                  const SizedBox(width: 8),
                  Text(isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'role',
              child: Row(
                children: [
                  Icon(Icons.admin_panel_settings, size: 18),
                  SizedBox(width: 8),
                  Text('Change Role'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return AppColors.error;
      case UserRole.doctor:
        return AppColors.primary;
      case UserRole.student:
        return AppColors.success;
      case UserRole.staff:
        return AppColors.info;
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        // Use a local set to track changes inside the dialog
        final tempSelectedRoles = Set<UserRole>.from(_selectedRoles);

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Filter by Role'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                // Exclude doctor from filter options
                children: UserRole.values
                    .where((role) => role != UserRole.doctor)
                    .map((role) {
                  return CheckboxListTile(
                    title: Text(role.name.toUpperCase()),
                    value: tempSelectedRoles.contains(role),
                    activeColor: AppColors.primary,
                    onChanged: (bool? selected) {
                      setState(() {
                        if (selected == true) {
                          tempSelectedRoles.add(role);
                        } else {
                          tempSelectedRoles.remove(role);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Clear all filters
                    this.setState(() => _selectedRoles.clear());
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
                      _selectedRoles = tempSelectedRoles;
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

  void _showUserDetails(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final isActive = data['isActive'] ?? true;
    final photoUrl = data['photoUrl'] as String?;
    final fullName = data['fullName'] ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.75,
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
                      // User Photo
                      CircleAvatar(
                        radius: 50,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.1),
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Text(
                                fullName.isNotEmpty
                                    ? fullName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              )
                            : null,
                      ),

                      const SizedBox(height: 16),

                      // User Name
                      Text(
                        fullName,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 4),

                      // Role subtitle
                      Text(
                        (data['role'] ?? 'patient').toString().toUpperCase(),
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
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
                            _buildDetailRow(
                                'Email', data['email'] ?? 'N/A', isDark),
                            _buildDivider(isDark),
                            _buildDetailRow('Google Email',
                                data['googleEmail'] ?? 'N/A', isDark),
                            _buildDivider(isDark),
                            _buildDetailRow(
                                'Phone', data['phoneNumber'] ?? 'N/A', isDark),
                            _buildDivider(isDark),
                            _buildDetailRow('Blood Type',
                                data['bloodType'] ?? 'N/A', isDark),
                            _buildDivider(isDark),
                            _buildDetailRow('Allergies',
                                data['allergies'] ?? 'N/A', isDark),
                            _buildDivider(isDark),
                            _buildDetailRow(
                              'Date of Birth',
                              data['dateOfBirth'] is Timestamp
                                  ? DateFormat.yMMMd().format(
                                      (data['dateOfBirth'] as Timestamp)
                                          .toDate(),
                                    )
                                  : data['dateOfBirth']?.toString() ?? 'N/A',
                              isDark,
                            ),
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
                          _toggleUserStatus(id, isActive);
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
                          _showEditUserDialog(id, data);
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

  Future<void> _toggleUserStatus(String id, bool currentStatus) async {
    await _firestore.collection('users').doc(id).update({
      'isActive': !currentStatus,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentStatus ? 'User deactivated' : 'User activated'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _changeUserRole(String id, UserRole currentRole) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change User Role'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              // Exclude doctor from role change options
              children: UserRole.values
                  .where((role) => role != UserRole.doctor)
                  .map((role) {
                return RadioListTile<UserRole>(
                  title: Text(role.name.toUpperCase()),
                  value: role,
                  // ignore: deprecated_member_use
                  groupValue: currentRole,
                  // ignore: deprecated_member_use
                  onChanged: (value) async {
                    if (value != null) {
                      await _firestore.collection('users').doc(id).update({
                        'role': value.name,
                      });
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Role updated'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  },
                );
              }).toList(),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

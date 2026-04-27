import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/admin_permissions_model.dart';
import '../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_governance_service.dart';

/// Super Admin governance panel — manage admin accounts, permissions, and slots.
class AdminControlScreen extends StatefulWidget {
  final int initialTab;
  const AdminControlScreen({super.key, this.initialTab = 0});

  @override
  State<AdminControlScreen> createState() => _AdminControlScreenState();
}

class _AdminControlScreenState extends State<AdminControlScreen>
    with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _governance = AdminGovernanceService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final clampedInitialTab = widget.initialTab.clamp(0, 2);
    _tabController =
        TabController(length: 3, vsync: this, initialIndex: clampedInitialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actorRole = context.watch<AuthProvider>().currentUser?.role;
    final actorIsSuperAdmin = actorRole == UserRole.superAdmin;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.adminGovernance,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFD32F2F),
          unselectedLabelColor: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
          indicatorColor: const Color(0xFFD32F2F),
          tabs: [
            Tab(text: l10n.admins),
            Tab(text: l10n.permissions),
            Tab(text: l10n.slots),
          ],
        ),
      ),
      floatingActionButton: actorIsSuperAdmin
          ? FloatingActionButton(
              // Two AdminControlScreen instances can exist simultaneously
              // in SuperAdminShell (Admins + Permissions tabs via IndexedStack),
              // so hero tags must be unique per instance.
              heroTag: 'admin_governance_fab_${widget.initialTab}',
              backgroundColor: const Color(0xFFD32F2F),
              onPressed: _showCreateAdminDialog,
              child: const Icon(Icons.person_add, color: Colors.white),
            )
          : null,
      body: Column(
        children: [
          if (!actorIsSuperAdmin)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.warning.withValues(alpha: 0.1),
              child: Text(
                l10n.viewOnlyMode,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.warning,
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAdminListTab(isDark, actorIsSuperAdmin),
                _buildPermissionsTab(isDark, actorIsSuperAdmin),
                _buildSlotsTab(isDark, actorIsSuperAdmin),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab 1: Admin + SuperAdmin List ─────────────────────

  Widget _buildAdminListTab(bool isDark, bool actorIsSuperAdmin) {
    final l10n = AppLocalizations.of(context);
    // Fix #3: Query both admin and superAdmin roles
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .where('role', whereIn: ['admin', 'superAdmin']).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.admin_panel_settings,
                    size: 64, color: isDark ? Colors.white24 : Colors.black12),
                const SizedBox(height: 16),
                Text(l10n.noAdminsFound,
                    style: GoogleFonts.poppins(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final uid = docs[index].id;
            final name = data['fullName'] ?? 'Unknown';
            final email = data['email'] ?? '';
            final isActive = data['isActive'] ?? true;
            final role = data['role'] as String? ?? 'admin';
            final isSuperAdmin = role == 'superAdmin';
            final slotType = data['superAdminType'] as String?;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSuperAdmin
                      ? const Color(0xFFD32F2F).withValues(alpha: 0.15)
                      : (isActive
                          ? AppColors.success.withValues(alpha: 0.15)
                          : AppColors.error.withValues(alpha: 0.15)),
                  child: Icon(
                    isSuperAdmin
                        ? Icons.shield
                        : (isActive ? Icons.admin_panel_settings : Icons.block),
                    color: isSuperAdmin
                        ? const Color(0xFFD32F2F)
                        : (isActive ? AppColors.success : AppColors.error),
                  ),
                ),
                title: Row(
                  children: [
                    Text(name,
                        style:
                            GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    if (isSuperAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFD32F2F).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          slotType?.toUpperCase() ?? 'SA',
                          style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFD32F2F)),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(email,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight)),
                // Fix #4: Add role-change action; don't show destructive actions for superAdmin rows
                trailing: (!actorIsSuperAdmin || isSuperAdmin)
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (action) =>
                            _handleAdminAction(action, uid, name, isActive),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: isActive ? 'deactivate' : 'activate',
                            child: Text(
                                isActive ? l10n.deactivate : l10n.activate),
                          ),
                          PopupMenuItem(
                              value: 'changeRole',
                              child: Text(l10n.changeUserRole)),
                          PopupMenuItem(
                              value: 'resetPassword',
                              child: Text(l10n.passwordResetAction)),
                          PopupMenuItem(
                              value: 'forceSignOut',
                              child: Text(l10n.forceSignOut)),
                          PopupMenuItem(
                              value: 'delete',
                              child: Text(l10n.delete,
                                  style:
                                      const TextStyle(color: AppColors.error))),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Tab 2: Permissions ─────────────────────────────────

  Widget _buildPermissionsTab(bool isDark, bool actorIsSuperAdmin) {
    final l10n = AppLocalizations.of(context);
    // Only admin accounts have editable permissions (superAdmin bypasses all)
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(child: Text(l10n.noAdminsFound));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final uid = docs[index].id;
            final name = data['fullName'] ?? 'Unknown';
            final perms = AdminPermissions.fromMap(
                data['adminPermissions'] as Map<String, dynamic>?);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: ExpansionTile(
                leading: const Icon(Icons.security, color: Color(0xFFD32F2F)),
                title: Text(name,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${AdminPermissions.allKeys.where((k) => perms.getByKey(k)).length}/${AdminPermissions.allKeys.length} permissions',
                    style: GoogleFonts.poppins(fontSize: 12)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _presetChip(
                            'Full',
                            isDark,
                            actorIsSuperAdmin
                                ? () => _applyPreset(
                                    uid, AdminPermissions.fullAccess)
                                : null),
                        const SizedBox(width: 8),
                        _presetChip(
                            'Ops',
                            isDark,
                            actorIsSuperAdmin
                                ? () => _applyPreset(
                                    uid, AdminPermissions.operations)
                                : null),
                        const SizedBox(width: 8),
                        _presetChip(
                            'Read-Only',
                            isDark,
                            actorIsSuperAdmin
                                ? () =>
                                    _applyPreset(uid, AdminPermissions.readOnly)
                                : null),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  ...AdminPermissions.allKeys.map((key) {
                    return SwitchListTile(
                      dense: true,
                      activeThumbColor: const Color(0xFFD32F2F),
                      title: Text(AdminPermissions.labels[key] ?? key,
                          style: GoogleFonts.poppins(fontSize: 13)),
                      subtitle: Text(AdminPermissions.descriptions[key] ?? '',
                          style: GoogleFonts.poppins(fontSize: 11)),
                      value: perms.getByKey(key),
                      onChanged: actorIsSuperAdmin
                          ? (val) => _togglePermission(uid, perms, key, val)
                          : null,
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _presetChip(String label, bool isDark, VoidCallback? onTap) {
    return ActionChip(
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: onTap == null
              ? (isDark ? Colors.white54 : Colors.black38)
              : (isDark ? Colors.white : const Color(0xFF7A1616)),
        ),
      ),
      onPressed: onTap,
      backgroundColor: isDark
          ? const Color(0xFFD32F2F).withValues(alpha: 0.22)
          : const Color(0xFFD32F2F).withValues(alpha: 0.1),
      disabledColor:
          isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey[200],
      side: BorderSide(
        color: onTap == null
            ? (isDark
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.6))
            : const Color(0xFFD32F2F),
        width: 0.8,
      ),
    );
  }

  // ─── Tab 3: Super Admin Slots ───────────────────────────
  // Fix #1: Query users collection where role==superAdmin, not app_config

  Widget _buildSlotsTab(bool isDark, bool actorIsSuperAdmin) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .where('role', isEqualTo: 'superAdmin')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];

        // Build slot map from user docs
        String? primaryUid;
        String? backupUid;
        Map<String, dynamic>? primaryData;
        Map<String, dynamic>? backupData;

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final slotType = data['superAdminType'] as String?;
          if (slotType == 'primary') {
            primaryUid = doc.id;
            primaryData = data;
          } else if (slotType == 'backup') {
            backupUid = doc.id;
            backupData = data;
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSlotCard('Primary', primaryUid, primaryData, 'primary',
                isDark, actorIsSuperAdmin),
            const SizedBox(height: 16),
            _buildSlotCard('Backup', backupUid, backupData, 'backup', isDark,
                actorIsSuperAdmin),
            const SizedBox(height: 32),
            Card(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Color(0xFFD32F2F)),
                        const SizedBox(width: 8),
                        Text(l10n.superAdminSlots,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• ${l10n.maxSlotsReached}\n'
                      '• ${l10n.slotAssign} / ${l10n.slotRotate} use transactions\n'
                      '• ${l10n.slotRotate} demotes old holder and promotes replacement',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSlotCard(
      String label,
      String? uid,
      Map<String, dynamic>? userData,
      String slotType,
      bool isDark,
      bool actorIsSuperAdmin) {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  slotType == 'primary' ? Icons.star : Icons.star_border,
                  color: const Color(0xFFD32F2F),
                ),
                const SizedBox(width: 8),
                Text('$label ${l10n.superAdmin}',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            if (uid == null || userData == null)
              Text(l10n.notFound,
                  style: GoogleFonts.poppins(
                      color: AppColors.warning, fontStyle: FontStyle.italic))
            else
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: userData['photoUrl'] != null
                        ? NetworkImage(userData['photoUrl'] as String)
                        : null,
                    child: userData['photoUrl'] == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userData['fullName'] ?? 'Unknown',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                        Text(userData['email'] ?? '',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight)),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            if (!actorIsSuperAdmin)
              Text(
                l10n.readOnlyMode,
                style: GoogleFonts.poppins(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              )
            else if (uid == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showAssignSlotDialog(slotType),
                  icon: const Icon(Icons.person_add, size: 18),
                  label: Text(l10n.assignSlot),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD32F2F),
                      foregroundColor: Colors.white),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showRotateSlotDialog(slotType),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: Text(l10n.rotateSlot),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD32F2F)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Actions ────────────────────────────────────────────

  Future<void> _handleAdminAction(
      String action, String uid, String name, bool isActive) async {
    if (!_isActorSuperAdmin()) {
      _showError('Permission denied: Super Admin access required.');
      return;
    }
    try {
      switch (action) {
        case 'activate':
        case 'deactivate':
          await _governance.setAdminActiveStatus(
              targetUid: uid, isActive: action == 'activate');
          _showSuccess(
              '${action == 'activate' ? 'Activated' : 'Deactivated'} $name');
          break;
        case 'changeRole':
          _showChangeRoleDialog(uid, name);
          break;
        case 'resetPassword':
          _showResetPasswordDialog(uid, name);
          break;
        case 'forceSignOut':
          await _governance.forceSignOutUser(targetUid: uid);
          _showSuccess('Force signed out $name');
          break;
        case 'delete':
          _showDeleteConfirmDialog(uid, name);
          break;
      }
    } catch (e) {
      _showError('Action failed: ${_readableError(e)}');
    }
  }

  bool _isActorSuperAdmin() {
    final role = context.read<AuthProvider>().currentUser?.role;
    return role == UserRole.superAdmin;
  }

  // Fix #4: Change role dialog
  void _showChangeRoleDialog(String uid, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${AppLocalizations.of(context).changeUserRole} — $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${AppLocalizations.of(context).changeUserRole}:',
                style: GoogleFonts.poppins(fontSize: 13)),
            const SizedBox(height: 12),
            // Only non-doctor, non-superAdmin roles are valid targets
            ...['student', 'staff', 'admin'].map((role) {
              return ListTile(
                dense: true,
                leading: Icon(role == 'admin'
                    ? Icons.admin_panel_settings
                    : Icons.person),
                title: Text(role.toUpperCase(),
                    style: GoogleFonts.poppins(fontSize: 13)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await _governance.changeAdminRole(
                        targetUid: uid, newRole: role);
                    _showSuccess('Role changed to $role');
                  } catch (e) {
                    _showError('Failed: ${_readableError(e)}');
                  }
                },
              );
            }),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context).cancel)),
        ],
      ),
    );
  }

  void _showCreateAdminDialog() {
    final l10n = AppLocalizations.of(context);
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    bool obscurePassword = true;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final inputBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.12),
          ),
        );

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() => isSubmitting = true);
              try {
                await _governance.createAdminAccount(
                  email: emailCtrl.text.trim(),
                  password: passwordCtrl.text,
                  fullName: nameCtrl.text.trim(),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _showSuccess('Admin created');
              } catch (e) {
                _showError('Failed: ${_readableError(e)}');
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => isSubmitting = false);
                }
              }
            }

            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor:
                  isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.createAdmin,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: nameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: l10n.fullName,
                            prefixIcon: const Icon(Icons.person_outline),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: const BorderSide(
                                  color: Color(0xFFD32F2F), width: 1.2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter full name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: l10n.email,
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: const BorderSide(
                                  color: Color(0xFFD32F2F), width: 1.2),
                            ),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Please enter email';
                            if (!text.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: passwordCtrl,
                          obscureText: obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!isSubmitting) submit();
                          },
                          decoration: InputDecoration(
                            labelText: l10n.password,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setDialogState(
                                  () => obscurePassword = !obscurePassword),
                            ),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: const BorderSide(
                                  color: Color(0xFFD32F2F), width: 1.2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(dialogContext),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    l10n.add,
                                    style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      emailCtrl.dispose();
      passwordCtrl.dispose();
    });
  }

  void _showResetPasswordDialog(String uid, String name) {
    final l10n = AppLocalizations.of(context);
    final pwCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    bool obscurePassword = true;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final inputBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.12),
          ),
        );

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() => isSubmitting = true);
              try {
                await _governance.resetAdminPassword(
                    targetUid: uid, newPassword: pwCtrl.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _showSuccess('Password reset for $name');
              } catch (e) {
                _showError('Failed: ${_readableError(e)}');
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => isSubmitting = false);
                }
              }
            }

            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor:
                  isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${l10n.passwordResetAction} - $name',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: pwCtrl,
                          obscureText: obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!isSubmitting) submit();
                          },
                          decoration: InputDecoration(
                            labelText: l10n.newPassword,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setDialogState(
                                  () => obscurePassword = !obscurePassword),
                            ),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: const BorderSide(
                                  color: Color(0xFFD32F2F), width: 1.2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(dialogContext),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    l10n.resetPassword,
                                    style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => pwCtrl.dispose());
  }

  void _showDeleteConfirmDialog(String uid, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).deleteAdmin),
        content: Text(
          '${AppLocalizations.of(context).confirmDeleteMessage}\n$name',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context).cancel)),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _governance.deleteAdminAccount(targetUid: uid);
                _showSuccess('Deleted $name');
              } catch (e) {
                _showError('Failed: ${_readableError(e)}');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(AppLocalizations.of(context).delete,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePermission(
      String uid, AdminPermissions current, String key, bool value) async {
    try {
      final map = current.toMap();
      map[key] = value;
      await _governance.setAdminPermissions(
        targetUid: uid,
        permissions: Map<String, bool>.from(map),
      );
    } catch (e) {
      _showError('Failed to update permission: ${_readableError(e)}');
    }
  }

  Future<void> _applyPreset(String uid, AdminPermissions preset) async {
    try {
      await _governance.setAdminPermissions(
        targetUid: uid,
        permissions: Map<String, bool>.from(preset.toMap()),
      );
      _showSuccess('Preset applied');
    } catch (e) {
      _showError('Failed: ${_readableError(e)}');
    }
  }

  void _showAssignSlotDialog(String slotType) {
    final l10n = AppLocalizations.of(context);
    final uidCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    final slotLabel = slotType == 'primary' ? 'Primary' : 'Backup';

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final inputBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.12),
          ),
        );

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() => isSubmitting = true);
              try {
                final resolvedUid = await _resolveUidFromInput(uidCtrl.text);
                if (resolvedUid == null) {
                  throw Exception(
                      'User not found. Enter a valid UID or email.');
                }
                await _governance.assignSuperAdminSlot(
                    targetUid: resolvedUid, slotType: slotType);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _showSuccess('Slot assigned');
              } catch (e) {
                _showError('Failed: ${_readableError(e)}');
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => isSubmitting = false);
                }
              }
            }

            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor:
                  isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${l10n.assignSlot} - $slotLabel',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: uidCtrl,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!isSubmitting) submit();
                          },
                          decoration: InputDecoration(
                            labelText: '${l10n.targetUserUid} / Email',
                            hintText: 'Paste UID or email',
                            prefixIcon:
                                const Icon(Icons.person_search_outlined),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: const BorderSide(
                                  color: Color(0xFFD32F2F), width: 1.2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter target UID or email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(dialogContext),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    l10n.assignSlot,
                                    style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => uidCtrl.dispose());
  }

  void _showRotateSlotDialog(String slotType) {
    final l10n = AppLocalizations.of(context);
    final uidCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    final slotLabel = slotType == 'primary' ? 'Primary' : 'Backup';

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final inputBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.12),
          ),
        );

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() => isSubmitting = true);
              try {
                final resolvedUid = await _resolveUidFromInput(uidCtrl.text);
                if (resolvedUid == null) {
                  throw Exception(
                      'User not found. Enter a valid UID or email.');
                }
                await _governance.rotateSuperAdminSlot(
                    slotType: slotType, replacementUid: resolvedUid);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _showSuccess('Slot rotated');
              } catch (e) {
                _showError('Failed: ${_readableError(e)}');
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => isSubmitting = false);
                }
              }
            }

            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor:
                  isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${l10n.rotateSlot} - $slotLabel',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: uidCtrl,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!isSubmitting) submit();
                          },
                          decoration: InputDecoration(
                            labelText: '${l10n.replacementUid} / Email',
                            hintText: 'Paste UID or email',
                            prefixIcon: const Icon(Icons.swap_horiz_rounded),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: const BorderSide(
                                  color: Color(0xFFD32F2F), width: 1.2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter replacement UID or email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(dialogContext),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    l10n.rotateSlot,
                                    style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => uidCtrl.dispose());
  }

  /// Accept UID or email and resolve to a real users/{uid} document id.
  Future<String?> _resolveUidFromInput(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) return null;

    if (input.contains('@')) {
      final byEmail = await _firestore
          .collection('users')
          .where('email', isEqualTo: input)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) return byEmail.docs.first.id;

      final byLowerEmail = await _firestore
          .collection('users')
          .where('email', isEqualTo: input.toLowerCase())
          .limit(1)
          .get();
      if (byLowerEmail.docs.isNotEmpty) return byLowerEmail.docs.first.id;
      return null;
    }

    final asUidDoc = await _firestore.collection('users').doc(input).get();
    if (asUidDoc.exists) return input;

    return null;
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.success));
  }

  String _readableError(Object error) {
    if (error is FirebaseFunctionsException) {
      final raw = (error.message ?? '').trim();
      if (raw.isNotEmpty && raw.toLowerCase() != 'internal') {
        return raw;
      }
      switch (error.code) {
        case 'permission-denied':
          return 'Permission denied. Super Admin access is required.';
        case 'not-found':
          return 'Target account not found.';
        case 'failed-precondition':
          return 'Action is not allowed for the selected account.';
        case 'invalid-argument':
          return 'Invalid input. Please review and try again.';
        case 'unauthenticated':
          return 'Session expired. Please login again.';
        default:
          return 'Server error (${error.code}). Please try again.';
      }
    }
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error));
  }
}

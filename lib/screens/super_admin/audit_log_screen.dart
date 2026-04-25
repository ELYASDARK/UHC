import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import '../../services/admin_governance_service.dart';

/// Audit log viewer for Super Admin — shows admin_audit_logs entries.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _governance = AdminGovernanceService();
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _filterAction;
  String? _filterTargetUid;
  String? _filterActorUid;
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  final _targetUidCtrl = TextEditingController();
  final _actorUidCtrl = TextEditingController();

  // Fix #2: Match backend dot-style action values exactly
  static const _actionFilters = <String?>[
    null, // All
    'admin.create',
    'admin.promote',
    'admin.demote',
    'admin.activate',
    'admin.deactivate',
    'admin.passwordReset',
    'admin.delete',
    'admin.forceSignOut',
    'admin.permissionsUpdate',
    'superAdmin.slotAssign',
    'superAdmin.slotRotate',
  ];

  // Human-readable labels for the dot-style actions
  static const _actionLabels = <String, String>{
    'admin.create': 'Create Admin',
    'admin.promote': 'Promote',
    'admin.demote': 'Demote',
    'admin.activate': 'Activate',
    'admin.deactivate': 'Deactivate',
    'admin.passwordReset': 'Password Reset',
    'admin.delete': 'Delete Admin',
    'admin.forceSignOut': 'Force Sign-Out',
    'admin.permissionsUpdate': 'Permissions Update',
    'superAdmin.slotAssign': 'Slot Assign',
    'superAdmin.slotRotate': 'Slot Rotate',
  };

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _targetUidCtrl.dispose();
    _actorUidCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final result = await _governance.listAdminAuditLogs(
        limit: 50,
        action: _filterAction,
        targetUid: _filterTargetUid,
        actorUid: _filterActorUid,
        dateFrom: _filterDateFrom,
        dateTo: _filterDateTo,
      );
      final entries = (result['logs'] as List<dynamic>?) ?? [];
      setState(() {
        _logs = entries.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load logs: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.auditLogs,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          // Target UID filter
          IconButton(
            icon: Icon(Icons.person_search,
                color:
                    _filterTargetUid != null ? const Color(0xFFD32F2F) : null),
            onPressed: _showTargetFilter,
            tooltip: l10n.filterByTarget,
          ),
          // Actor UID filter
          IconButton(
            icon: Icon(Icons.manage_accounts_outlined,
                color:
                    _filterActorUid != null ? const Color(0xFFD32F2F) : null),
            onPressed: _showActorFilter,
            tooltip: l10n.filterByActor,
          ),
          // Date range filter
          IconButton(
            icon: Icon(Icons.date_range,
                color: (_filterDateFrom != null || _filterDateTo != null)
                    ? const Color(0xFFD32F2F)
                    : null),
            onPressed: _showDateRangeFilter,
            tooltip: l10n.filterByDateRange,
          ),
          // Action filter
          PopupMenuButton<String?>(
            icon: Icon(Icons.filter_list,
                color: _filterAction != null ? const Color(0xFFD32F2F) : null),
            onSelected: (val) {
              _filterAction = val;
              _loadLogs();
            },
            itemBuilder: (_) => _actionFilters.map((a) {
              return PopupMenuItem(
                value: a,
                child:
                    Text(a == null ? l10n.allActions : (_actionLabels[a] ?? a)),
              );
            }).toList(),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs),
        ],
      ),
      body: Column(
        children: [
          // Active filters bar
          if (_filterAction != null ||
              _filterTargetUid != null ||
              _filterActorUid != null ||
              _filterDateFrom != null ||
              _filterDateTo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
              child: Wrap(
                spacing: 8,
                children: [
                  if (_filterAction != null)
                    Chip(
                      label: Text(
                          _actionLabels[_filterAction] ?? _filterAction!,
                          style: GoogleFonts.poppins(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        _filterAction = null;
                        _loadLogs();
                      },
                    ),
                  if (_filterTargetUid != null)
                    Chip(
                      label: Text('Target: ${_shortUid(_filterTargetUid!)}',
                          style: GoogleFonts.poppins(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        _filterTargetUid = null;
                        _targetUidCtrl.clear();
                        _loadLogs();
                      },
                    ),
                  if (_filterActorUid != null)
                    Chip(
                      label: Text('Actor: ${_shortUid(_filterActorUid!)}',
                          style: GoogleFonts.poppins(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        _filterActorUid = null;
                        _actorUidCtrl.clear();
                        _loadLogs();
                      },
                    ),
                  if (_filterDateFrom != null || _filterDateTo != null)
                    Chip(
                      label: Text(
                        _dateRangeLabel(),
                        style: GoogleFonts.poppins(fontSize: 11),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        _filterDateFrom = null;
                        _filterDateTo = null;
                        _loadLogs();
                      },
                    ),
                ],
              ),
            ),
          // Log list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history,
                                size: 64,
                                color:
                                    isDark ? Colors.white24 : Colors.black12),
                            const SizedBox(height: 16),
                            Text(l10n.noAuditLogsFound,
                                style: GoogleFonts.poppins(
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadLogs,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) =>
                              _buildLogTile(_logs[index], isDark),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showTargetFilter() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${l10n.filterByTarget} (${l10n.targetUserUid})'),
        content: TextField(
          controller: _targetUidCtrl,
          decoration: InputDecoration(
            labelText: l10n.targetUserUid,
            hintText: l10n.pasteUidHere,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _targetUidCtrl.clear();
              _filterTargetUid = null;
              Navigator.pop(ctx);
              _loadLogs();
            },
            child: Text(l10n.clear),
          ),
          ElevatedButton(
            onPressed: () {
              final uid = _targetUidCtrl.text.trim();
              _filterTargetUid = uid.isNotEmpty ? uid : null;
              Navigator.pop(ctx);
              _loadLogs();
            },
            child: Text(l10n.apply),
          ),
        ],
      ),
    );
  }

  void _showActorFilter() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${l10n.filterByActor} (${l10n.actorUserUid})'),
        content: TextField(
          controller: _actorUidCtrl,
          decoration: InputDecoration(
            labelText: l10n.actorUserUid,
            hintText: l10n.pasteUidHere,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _actorUidCtrl.clear();
              _filterActorUid = null;
              Navigator.pop(ctx);
              _loadLogs();
            },
            child: Text(l10n.clear),
          ),
          ElevatedButton(
            onPressed: () {
              final uid = _actorUidCtrl.text.trim();
              _filterActorUid = uid.isNotEmpty ? uid : null;
              Navigator.pop(ctx);
              _loadLogs();
            },
            child: Text(l10n.apply),
          ),
        ],
      ),
    );
  }

  Future<void> _showDateRangeFilter() async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final initialRange = (_filterDateFrom != null && _filterDateTo != null)
        ? DateTimeRange(start: _filterDateFrom!, end: _filterDateTo!)
        : DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          );

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initialRange,
      helpText: l10n.filterAuditDates,
    );

    if (range == null) return;
    _filterDateFrom =
        DateTime(range.start.year, range.start.month, range.start.day);
    _filterDateTo = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    );
    _loadLogs();
  }

  String _shortUid(String uid) {
    if (uid.length <= 10) return uid;
    return '${uid.substring(0, 10)}…';
  }

  String _dateRangeLabel() {
    final l10n = AppLocalizations.of(context);
    final fmt = DateFormat('yyyy-MM-dd');
    final from = _filterDateFrom != null ? fmt.format(_filterDateFrom!) : 'Any';
    final to = _filterDateTo != null ? fmt.format(_filterDateTo!) : 'Any';
    return '${l10n.date}: $from → $to';
  }

  Widget _buildLogTile(Map<String, dynamic> log, bool isDark) {
    final action = log['action'] as String? ?? 'unknown';
    final actorName = log['actorName'] as String? ?? '';
    final targetName = log['targetName'] as String? ?? '';
    final actorUid = log['actorUid'] as String? ?? '';
    final targetUid = log['targetUid'] as String? ?? '';
    final createdAt = log['createdAt'];
    String timeStr = '';
    if (createdAt != null) {
      try {
        if (createdAt is Map && createdAt['_seconds'] != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(
              (createdAt['_seconds'] as int) * 1000);
          timeStr = DateFormat('MMM d, yyyy HH:mm').format(dt);
        } else if (createdAt is String) {
          final parsed = DateTime.tryParse(createdAt);
          timeStr = parsed != null
              ? DateFormat('MMM d, yyyy HH:mm').format(parsed.toLocal())
              : createdAt;
        }
      } catch (_) {}
    }

    final icon = _actionIcon(action);
    final color = _actionColor(action);
    final label = _actionLabels[action] ?? action;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          label,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (actorName.isNotEmpty)
              Text('By: $actorName', style: GoogleFonts.poppins(fontSize: 11))
            else if (actorUid.isNotEmpty)
              Text(
                  'By: ${actorUid.substring(0, actorUid.length > 12 ? 12 : actorUid.length)}…',
                  style: GoogleFonts.poppins(fontSize: 11)),
            if (targetName.isNotEmpty)
              Text('Target: $targetName',
                  style: GoogleFonts.poppins(fontSize: 11))
            else if (targetUid.isNotEmpty)
              Text(
                  'Target: ${targetUid.substring(0, targetUid.length > 12 ? 12 : targetUid.length)}…',
                  style: GoogleFonts.poppins(fontSize: 11)),
            if (timeStr.isNotEmpty)
              Text(timeStr,
                  style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight)),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'admin.create':
        return Icons.person_add;
      case 'admin.promote':
      case 'admin.demote':
        return Icons.swap_horiz;
      case 'admin.activate':
      case 'admin.deactivate':
        return Icons.toggle_on;
      case 'admin.passwordReset':
        return Icons.lock_reset;
      case 'admin.delete':
        return Icons.delete;
      case 'admin.forceSignOut':
        return Icons.logout;
      case 'admin.permissionsUpdate':
        return Icons.security;
      case 'superAdmin.slotAssign':
        return Icons.star;
      case 'superAdmin.slotRotate':
        return Icons.autorenew;
      default:
        return Icons.history;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'admin.create':
        return AppColors.success;
      case 'admin.delete':
        return AppColors.error;
      case 'admin.forceSignOut':
        return AppColors.warning;
      case 'admin.activate':
      case 'admin.deactivate':
        return AppColors.info;
      default:
        return const Color(0xFFD32F2F);
    }
  }
}

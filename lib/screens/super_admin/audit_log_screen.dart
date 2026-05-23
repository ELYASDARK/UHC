import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/role_english_ltr_scope.dart';
import '../../services/admin_governance_service.dart';

/// Audit log viewer for Super Admin — shows admin_audit_logs entries.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _governance = AdminGovernanceService();
  final _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _filterAction;
  String? _filterTargetUid;
  String? _filterActorUid;
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  int _displayLimit = 50;
  bool _hasMore = false;
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

  EdgeInsets _auditListPadding({double bottom = 24}) {
    final breakpoint = UhcResponsive.breakpointOf(context);
    final top = switch (breakpoint) {
      UhcBreakpoint.phone => 12.0,
      UhcBreakpoint.tablet => 14.0,
      UhcBreakpoint.laptop || UhcBreakpoint.desktop => 18.0,
    };
    return UhcResponsive.pagePadding(context, top: top, bottom: bottom);
  }

  double _listGap() {
    return UhcResponsive.breakpointOf(context).isPhone ? 10 : 12;
  }

  double _logTileAspectRatio() {
    return switch (UhcResponsive.breakpointOf(context)) {
      UhcBreakpoint.phone => 4.8,
      UhcBreakpoint.tablet => 7.2,
      UhcBreakpoint.laptop => 5.2,
      UhcBreakpoint.desktop => 4.55,
    };
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final result = await _governance.listAdminAuditLogs(
        limit: _displayLimit,
        action: _filterAction,
        targetUid: _filterTargetUid,
        actorUid: _filterActorUid,
        dateFrom: _filterDateFrom,
        dateTo: _filterDateTo,
      );
      final entries = (result['logs'] as List<dynamic>?) ?? [];
      final normalizedLogs = entries
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      if (!mounted) return;
      setState(() {
        _logs = normalizedLogs;
        _hasMore = result['hasMore'] == true;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load logs: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _loadMore() {
    setState(() => _displayLimit += 50);
    _loadLogs();
  }

  void _resetAndReload() {
    _displayLimit = 50;
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return RoleEnglishLtrScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.auditLogs,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          centerTitle: true,
          actions: [
            // Target UID filter
            IconButton(
              icon: Icon(Icons.person_search,
                  color: _filterTargetUid != null
                      ? const Color(0xFFD32F2F)
                      : null),
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
                  color:
                      _filterAction != null ? const Color(0xFFD32F2F) : null),
              onSelected: (val) {
                _filterAction = val;
                _resetAndReload();
              },
              itemBuilder: (_) => _actionFilters.map((a) {
                return PopupMenuItem(
                  value: a,
                  child: Text(
                      a == null ? l10n.allActions : (_actionLabels[a] ?? a)),
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
              ColoredBox(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
                child: ResponsiveContent(
                  maxWidth: 1440,
                  child: Padding(
                    padding:
                        UhcResponsive.pagePadding(context, top: 8, bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (_filterAction != null)
                          Chip(
                            label: Text(
                                _actionLabels[_filterAction] ?? _filterAction!,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: isDark ? Colors.white : Colors.black87,
                                )),
                            backgroundColor:
                                isDark ? AppColors.surfaceDark : Colors.white,
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.35)
                                  : Colors.black.withValues(alpha: 0.15),
                            ),
                            deleteIconColor:
                                isDark ? Colors.white70 : Colors.black54,
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              _filterAction = null;
                              _resetAndReload();
                            },
                          ),
                        if (_filterTargetUid != null)
                          Chip(
                            label: Text(
                                'Target: ${_shortUid(_filterTargetUid!)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: isDark ? Colors.white : Colors.black87,
                                )),
                            backgroundColor:
                                isDark ? AppColors.surfaceDark : Colors.white,
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.35)
                                  : Colors.black.withValues(alpha: 0.15),
                            ),
                            deleteIconColor:
                                isDark ? Colors.white70 : Colors.black54,
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              _filterTargetUid = null;
                              _targetUidCtrl.clear();
                              _resetAndReload();
                            },
                          ),
                        if (_filterActorUid != null)
                          Chip(
                            label: Text('Actor: ${_shortUid(_filterActorUid!)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: isDark ? Colors.white : Colors.black87,
                                )),
                            backgroundColor:
                                isDark ? AppColors.surfaceDark : Colors.white,
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.35)
                                  : Colors.black.withValues(alpha: 0.15),
                            ),
                            deleteIconColor:
                                isDark ? Colors.white70 : Colors.black54,
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              _filterActorUid = null;
                              _actorUidCtrl.clear();
                              _resetAndReload();
                            },
                          ),
                        if (_filterDateFrom != null || _filterDateTo != null)
                          Chip(
                            label: Text(
                              _dateRangeLabel(),
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            backgroundColor:
                                isDark ? AppColors.surfaceDark : Colors.white,
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.35)
                                  : Colors.black.withValues(alpha: 0.15),
                            ),
                            deleteIconColor:
                                isDark ? Colors.white70 : Colors.black54,
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              _filterDateFrom = null;
                              _filterDateTo = null;
                              _resetAndReload();
                            },
                          ),
                      ],
                    ),
                  ),
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
                          child: ResponsiveListView(
                            maxWidth: 1440,
                            gridOnWide: true,
                            tabletColumns: 1,
                            laptopColumns: 2,
                            desktopColumns: 3,
                            spacing: _listGap(),
                            runSpacing: _listGap(),
                            childAspectRatio: _logTileAspectRatio(),
                            padding: _auditListPadding(bottom: 24),
                            itemCount: _logs.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _logs.length) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: TextButton.icon(
                                      onPressed: _loadMore,
                                      icon: const Icon(Icons.expand_more,
                                          color: Color(0xFFD32F2F)),
                                      label: Text(
                                        'Load More',
                                        style: GoogleFonts.poppins(
                                          color: const Color(0xFFD32F2F),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return _buildLogTile(_logs[index], isDark);
                            },
                          ),
                        ),
            ),
          ],
        ),
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
            labelText: '${l10n.targetUserUid} / Email',
            hintText: 'Paste UID or email',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _targetUidCtrl.clear();
              _filterTargetUid = null;
              Navigator.pop(ctx);
              _resetAndReload();
            },
            child: Text(l10n.clear),
          ),
          ElevatedButton(
            onPressed: () async {
              final raw = _targetUidCtrl.text.trim();
              if (raw.isEmpty) {
                _filterTargetUid = null;
                if (ctx.mounted) Navigator.pop(ctx);
                _resetAndReload();
                return;
              }

              final resolvedUid = await _resolveUidFromInput(raw);
              if (resolvedUid == null) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('User not found. Enter a valid UID or email.'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              _filterTargetUid = resolvedUid;
              if (ctx.mounted) Navigator.pop(ctx);
              _resetAndReload();
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
            labelText: '${l10n.actorUserUid} / Email',
            hintText: 'Paste UID or email',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _actorUidCtrl.clear();
              _filterActorUid = null;
              Navigator.pop(ctx);
              _resetAndReload();
            },
            child: Text(l10n.clear),
          ),
          ElevatedButton(
            onPressed: () async {
              final raw = _actorUidCtrl.text.trim();
              if (raw.isEmpty) {
                _filterActorUid = null;
                if (ctx.mounted) Navigator.pop(ctx);
                _resetAndReload();
                return;
              }

              final resolvedUid = await _resolveUidFromInput(raw);
              if (resolvedUid == null) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('User not found. Enter a valid UID or email.'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              _filterActorUid = resolvedUid;
              if (ctx.mounted) Navigator.pop(ctx);
              _resetAndReload();
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
    _resetAndReload();
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

  /// Accept UID or email and resolve to real users/{uid} doc id.
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

  Widget _buildLogTile(Map<String, dynamic> log, bool isDark) {
    final action = _asString(log['action'], fallback: 'unknown');
    final actorName = _asString(log['actorName']);
    final targetName = _asString(log['targetName']);
    final actorUid = _asString(log['actorUid']);
    final targetUid = _asString(log['targetUid']);
    final timeStr = _formatCreatedAt(log['createdAt']);

    final icon = _actionIcon(action);
    final color = _actionColor(action);
    final label = _actionLabels[action] ?? action;

    return Card(
      margin: EdgeInsets.zero,
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  if (actorName.isNotEmpty)
                    Text(
                      'By: $actorName',
                      style: GoogleFonts.poppins(fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (actorUid.isNotEmpty)
                    Text(
                      'By: ${actorUid.substring(0, actorUid.length > 12 ? 12 : actorUid.length)}...',
                      style: GoogleFonts.poppins(fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 1),
                  if (targetName.isNotEmpty)
                    Text(
                      'Target: $targetName',
                      style: GoogleFonts.poppins(fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (targetUid.isNotEmpty)
                    Text(
                      'Target: ${targetUid.substring(0, targetUid.length > 12 ? 12 : targetUid.length)}...',
                      style: GoogleFonts.poppins(fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 1),
                  if (timeStr.isNotEmpty)
                    Text(
                      timeStr,
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _asString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  String _formatCreatedAt(dynamic createdAt) {
    try {
      if (createdAt == null) return '';
      if (createdAt is Timestamp) {
        return DateFormat('MMM d, yyyy HH:mm').format(createdAt.toDate());
      }
      if (createdAt is DateTime) {
        return DateFormat('MMM d, yyyy HH:mm').format(createdAt.toLocal());
      }
      if (createdAt is String) {
        final parsed = DateTime.tryParse(createdAt);
        if (parsed != null) {
          return DateFormat('MMM d, yyyy HH:mm').format(parsed.toLocal());
        }
        return createdAt;
      }
      if (createdAt is int) {
        final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
        return DateFormat('MMM d, yyyy HH:mm').format(dt.toLocal());
      }
      if (createdAt is Map && createdAt['_seconds'] != null) {
        final sec = createdAt['_seconds'];
        if (sec is int) {
          final dt = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
          return DateFormat('MMM d, yyyy HH:mm').format(dt.toLocal());
        }
      }
    } catch (_) {}
    return '';
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

import 'dart:async';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/role_english_ltr_scope.dart';
import '../admin/dashboard/admin_dashboard_screen.dart';

/// Super Admin Dashboard with governance-focused KPIs:
/// admin count, active admins, slot health, recent audit activity.
class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _loading = <String>{};
  final _failed = <String>{};
  final _loaded = <String>{};
  final _outstanding = <String>{};
  String? _session;
  int _generation = 0;

  // KPIs
  int _totalAdmins = 0;
  int _activeAdmins = 0;
  int _inactiveAdmins = 0;
  int _superAdminCount = 0;
  bool _primarySlotFilled = false;
  bool _backupSlotFilled = false;

  int _totalUsers = 0;
  int _totalDoctors = 0;
  List<Map<String, dynamic>> _recentLogs = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<AuthProvider>().cacheSessionKey;
    if (_session == session) return;
    _session = session;
    _generation++;
    _loading.clear();
    _failed.clear();
    _loaded.clear();
    _outstanding.clear();
    _recentLogs = [];
    if (session != null) _loadDashboard();
  }

  Future<void> _loadDashboard({bool failedOnly = false}) async {
    await Future.wait([
      _loadSection(
          'totalAdmins',
          () => _firestore
              .collection('users')
              .where('role', isEqualTo: 'admin')
              .count()
              .get(),
          (aggregate) => _totalAdmins = aggregate.count!,
          failedOnly: failedOnly),
      _loadSection(
          'activeAdmins',
          () => _firestore
              .collection('users')
              .where('role', isEqualTo: 'admin')
              .where('isActive', isEqualTo: true)
              .count()
              .get(),
          (aggregate) => _activeAdmins = aggregate.count!,
          failedOnly: failedOnly),
      _loadSection('users', () => _firestore.collection('users').count().get(),
          (aggregate) => _totalUsers = aggregate.count!,
          failedOnly: failedOnly),
      _loadSection(
          'doctors',
          () => _firestore.collection('doctors').count().get(),
          (aggregate) => _totalDoctors = aggregate.count!,
          failedOnly: failedOnly),
      _loadSection(
          'slots',
          () => _firestore
              .collection('users')
              .where('role', isEqualTo: 'superAdmin')
              .limit(5)
              .get(const GetOptions(source: Source.server)), (slots) {
        _superAdminCount = slots.docs.length;
        _primarySlotFilled =
            slots.docs.any((doc) => doc.data()['superAdminType'] == 'primary');
        _backupSlotFilled =
            slots.docs.any((doc) => doc.data()['superAdminType'] == 'backup');
      }, failedOnly: failedOnly),
      _loadSection(
          'audit',
          () => _firestore
              .collection('admin_audit_logs')
              .where('createdAt',
                  isGreaterThan: Timestamp.fromDate(
                      DateTime.now().subtract(const Duration(days: 7))))
              .orderBy('createdAt', descending: true)
              .limit(5)
              .get(const GetOptions(source: Source.server)),
          (logs) => _recentLogs = logs.docs.map((doc) => doc.data()).toList(),
          failedOnly: failedOnly),
    ]);
  }

  Future<void> _loadSection<T>(
      String key, Future<T> Function() read, void Function(T) apply,
      {required bool failedOnly}) async {
    if (_outstanding.contains(key) || (failedOnly && !_failed.contains(key))) {
      return;
    }
    final generation = _generation;
    _outstanding.add(key);
    setState(() {
      _loading.add(key);
      _failed.remove(key);
    });
    final request = Future.sync(read);
    // Keep timed-out reads outstanding, so repeated Retry cannot stack requests.
    unawaited(request.then((_) {
      if (mounted && generation == _generation) _outstanding.remove(key);
    }, onError: (Object _) {
      if (mounted && generation == _generation) _outstanding.remove(key);
    }));
    try {
      final value = await request.timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation) return;
      setState(() {
        apply(value);
        _loaded.add(key);
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed.add(key);
        if (error is FirebaseException &&
            ['permission-denied', 'unauthenticated'].contains(error.code)) {
          _loaded.remove(key);
          if (key == 'totalAdmins' || key == 'activeAdmins') {
            _loaded.remove('admins');
          }
          if (key == 'audit') _recentLogs = [];
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading.remove(key);
          _updateInactiveCount();
        });
      }
    }
  }

  void _updateInactiveCount() {
    if (_loading.contains('totalAdmins') || _loading.contains('activeAdmins')) {
      return;
    }
    if (_failed.contains('totalAdmins') || _failed.contains('activeAdmins')) {
      if (!_loaded.contains('admins')) _failed.add('admins');
      return;
    }
    if (!_loaded.contains('totalAdmins') || !_loaded.contains('activeAdmins')) {
      return;
    }
    if (_activeAdmins > _totalAdmins) {
      // The independent counts can straddle an account mutation. Retry the pair.
      _failed.addAll(['totalAdmins', 'activeAdmins', 'admins']);
      return;
    }
    _inactiveAdmins = _totalAdmins - _activeAdmins;
    _loaded.add('admins');
    _failed.remove('admins');
  }

  String _countLabel(String key, int count) => _loaded.contains(key)
      ? '$count'
      : _failed.contains(key)
          ? 'Unavailable'
          : '…';

  Widget _sectionStatus(String key) {
    if (_failed.contains(key)) {
      return TextButton.icon(
          onPressed: () => _loadDashboard(failedOnly: true),
          icon: const Icon(Icons.refresh),
          label: Text(AppLocalizations.of(context).tryAgain));
    }
    return _loading.contains(key)
        ? const LinearProgressIndicator()
        : const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return RoleEnglishLtrScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.superAdmin,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          centerTitle: true,
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh), onPressed: _loadDashboard),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadDashboard,
          child: ResponsivePage(
            maxWidth: 1240,
            child: _buildDashboardBody(isDark, l10n),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardBody(bool isDark, AppLocalizations l10n) {
    final metrics =
        _buildMetricsGrid(isDark, compact: UhcResponsive.isWide(context));
    final riskVisible = (_loaded.contains('admins') && _inactiveAdmins > 0) ||
        (_loaded.contains('slots') &&
            (!_primarySlotFilled || !_backupSlotFilled));

    if (UhcResponsive.isWide(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSlotHealthBanner(isDark, l10n),
                _sectionStatus('slots'),
                const SizedBox(height: 14),
                _buildAdminDashboardEntry(isDark),
                const SizedBox(height: 14),
                metrics,
                if (riskVisible) ...[
                  const SizedBox(height: 18),
                  _buildRiskSection(isDark, l10n),
                ],
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 5,
            child: _buildRecentAuditSection(isDark, l10n),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSlotHealthBanner(isDark, l10n),
        _sectionStatus('slots'),
        const SizedBox(height: 14),
        _buildAdminDashboardEntry(isDark),
        const SizedBox(height: 14),
        metrics,
        const SizedBox(height: 18),
        if (riskVisible) ...[
          _buildRiskSection(isDark, l10n),
        ],
        _buildRecentAuditSection(isDark, l10n),
      ],
    );
  }

  Widget _buildAdminDashboardEntry(bool isDark) {
    return Card(
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.info.withValues(alpha: 0.12),
          child: const Icon(Icons.dashboard_customize, color: AppColors.info),
        ),
        title: Text(
          'Admin tools dashboard',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Open the shared Admin Dashboard for operational quick actions.',
          style: GoogleFonts.poppins(fontSize: 11),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        ),
      ),
    );
  }

  Widget _buildMetricsGrid(bool isDark, {required bool compact}) {
    final l10n = AppLocalizations.of(context);
    final breakpoint = UhcResponsive.breakpointOf(context);
    final ratio = switch (breakpoint) {
      UhcBreakpoint.phone => 1.55,
      UhcBreakpoint.tablet => 2.0,
      UhcBreakpoint.laptop || UhcBreakpoint.desktop => compact ? 3.15 : 2.2,
    };
    final gap = breakpoint.isPhone ? 10.0 : 12.0;

    final grid = ResponsiveGrid(
      phoneColumns: 2,
      tabletColumns: 3,
      laptopColumns: compact ? 2 : 3,
      desktopColumns: compact ? 2 : 3,
      childAspectRatio: ratio,
      spacing: gap,
      runSpacing: gap,
      children: [
        _buildKpiCard(
          l10n.totalAdmins,
          _countLabel('totalAdmins', _totalAdmins),
          Icons.admin_panel_settings,
          AppColors.primary,
          isDark,
        ),
        _buildKpiCard(
          l10n.activeAdmins,
          _countLabel('activeAdmins', _activeAdmins),
          Icons.check_circle,
          AppColors.success,
          isDark,
        ),
        _buildKpiCard(
          l10n.inactiveAdmins,
          _countLabel('admins', _inactiveAdmins),
          Icons.block,
          AppColors.error,
          isDark,
        ),
        _buildKpiCard(
          l10n.superAdmins,
          _loaded.contains('slots')
              ? '$_superAdminCount/2'
              : _countLabel('slots', 0),
          Icons.shield,
          const Color(0xFFD32F2F),
          isDark,
        ),
        _buildKpiCard(
          l10n.manageUsers,
          _countLabel('users', _totalUsers),
          Icons.people,
          AppColors.secondary,
          isDark,
        ),
        _buildKpiCard(
          l10n.doctors,
          _countLabel('doctors', _totalDoctors),
          Icons.local_hospital,
          AppColors.tertiary,
          isDark,
        ),
      ],
    );

    final section = Column(mainAxisSize: MainAxisSize.min, children: [
      grid,
      for (final key in ['totalAdmins', 'activeAdmins', 'users', 'doctors'])
        _sectionStatus(key),
    ]);
    if (!breakpoint.isPhone) return section;

    return Align(
      alignment: Alignment.topCenter,
      child: FractionallySizedBox(
        widthFactor: 0.93,
        child: section,
      ),
    );
  }

  Widget _buildRecentAuditSection(bool isDark, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.recentAuditActivity,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _sectionStatus('audit'),
        if (_loaded.contains('audit') && _recentLogs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                l10n.noRecentActivity,
                style: GoogleFonts.poppins(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ),
          )
        else
          ..._recentLogs.map((log) => _buildAuditRow(log, isDark)),
      ],
    );
  }

  Widget _buildSlotHealthBanner(bool isDark, AppLocalizations l10n) {
    if (!_loaded.contains('slots')) return const SizedBox.shrink();
    final allFilled = _primarySlotFilled && _backupSlotFilled;
    final color = allFilled ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            allFilled ? Icons.verified_user : Icons.warning_amber_rounded,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allFilled ? l10n.slotHealthy : l10n.slotAttentionNeeded,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13, color: color),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _slotDot(l10n.primarySlot, _primarySlotFilled),
                    const SizedBox(width: 12),
                    _slotDot(l10n.backupSlot, _backupSlotFilled),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotDot(String label, bool filled) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.success : AppColors.error,
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style:
                GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildKpiCard(
      String label, String value, IconData icon, Color color, bool isDark) {
    return Card(
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 260;
            final dense = constraints.maxWidth < 240;
            final iconSize = dense ? 36.0 : 44.0;
            final iconBox = Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: dense ? 20 : 24),
            );

            if (wide) {
              final groupWidth =
                  constraints.maxWidth < 190 ? constraints.maxWidth : 190.0;
              return Center(
                child: SizedBox(
                  width: groupWidth,
                  child: Row(
                    children: [
                      iconBox,
                      const SizedBox(width: 14),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: groupWidth - iconSize - 14,
                        ),
                        child: _buildKpiText(label, value, color, isDark,
                            wide: true),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconBox,
                SizedBox(height: dense ? 2 : 4),
                _buildKpiText(
                  label,
                  value,
                  color,
                  isDark,
                  wide: false,
                  dense: dense,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildKpiText(
    String label,
    String value,
    Color color,
    bool isDark, {
    required bool wide,
    bool dense = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: wide ? 22 : (dense ? 18 : 20),
            fontWeight: FontWeight.w700,
            color: color,
            height: dense ? 1.0 : 1.05,
          ),
        ),
        SizedBox(height: dense ? 1 : 2),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: wide ? 11.5 : (dense ? 10 : 10.5),
            height: dense ? 1.05 : 1.15,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
          textAlign: wide ? TextAlign.left : TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildRiskSection(bool isDark, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⚠ ${l10n.riskWarnings}',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppColors.warning)),
          const SizedBox(height: 8),
          if (_loaded.contains('slots') && !_primarySlotFilled)
            _riskTile(
                l10n.primarySlotEmpty, Icons.star, AppColors.error, isDark),
          if (_loaded.contains('slots') && !_backupSlotFilled)
            _riskTile(l10n.backupSlotEmpty, Icons.star_border,
                AppColors.warning, isDark),
          if (_loaded.contains('admins') && _inactiveAdmins > 0)
            _riskTile(l10n.inactiveAdminWarning(_inactiveAdmins), Icons.block,
                AppColors.warning, isDark),
        ],
      ),
    );
  }

  Widget _riskTile(String msg, IconData icon, Color color, bool isDark) {
    return Card(
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color, size: 20),
        title: Text(msg, style: GoogleFonts.poppins(fontSize: 12)),
      ),
    );
  }

  Widget _buildAuditRow(Map<String, dynamic> log, bool isDark) {
    final action = log['action'] as String? ?? 'unknown';
    final actorName = log['actorName'] as String? ?? '';
    final targetName = log['targetName'] as String? ?? '';

    return Card(
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: const Color(0xFFD32F2F).withValues(alpha: 0.1),
          child: const Icon(Icons.history, size: 15, color: Color(0xFFD32F2F)),
        ),
        title: Text(
          action
              .replaceAll('.', ' → ')
              .split(' ')
              .map((w) =>
                  w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
              .join(' '),
          style:
              GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${actorName.isNotEmpty ? 'By $actorName' : ''}${targetName.isNotEmpty ? ' → $targetName' : ''}',
          style: GoogleFonts.poppins(fontSize: 9.5),
        ),
      ),
    );
  }
}

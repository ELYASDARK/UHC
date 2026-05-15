import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/role_english_ltr_scope.dart';

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
  bool _isLoading = true;

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
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    try {
      // All admins
      final adminsSnap = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();
      final activeAdmins =
          adminsSnap.docs.where((d) => d.data()['isActive'] == true).length;

      // Super admins
      final saSnap = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'superAdmin')
          .get();
      bool primaryFilled = false;
      bool backupFilled = false;
      for (final doc in saSnap.docs) {
        final slot = doc.data()['superAdminType'] as String?;
        if (slot == 'primary') primaryFilled = true;
        if (slot == 'backup') backupFilled = true;
      }

      // Total users & doctors
      final usersCount = await _firestore.collection('users').count().get();
      final doctorsCount = await _firestore.collection('doctors').count().get();

      // Recent audit logs (last 7 days)
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final auditSnap = await _firestore
          .collection('admin_audit_logs')
          .where('createdAt', isGreaterThan: Timestamp.fromDate(weekAgo))
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      setState(() {
        _totalAdmins = adminsSnap.docs.length;
        _activeAdmins = activeAdmins;
        _inactiveAdmins = adminsSnap.docs.length - activeAdmins;
        _superAdminCount = saSnap.docs.length;
        _primarySlotFilled = primaryFilled;
        _backupSlotFilled = backupFilled;
        _totalUsers = usersCount.count ?? 0;
        _totalDoctors = doctorsCount.count ?? 0;
        _recentLogs = auditSnap.docs.map((d) => d.data()).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Dashboard load error: $e');
    }
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
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
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
    final riskVisible =
        _inactiveAdmins > 0 || !_primarySlotFilled || !_backupSlotFilled;

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
                const SizedBox(height: 20),
                metrics,
                if (riskVisible) ...[
                  const SizedBox(height: 24),
                  _buildRiskSection(isDark, l10n),
                ],
              ],
            ),
          ),
          const SizedBox(width: 28),
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
        const SizedBox(height: 20),
        metrics,
        const SizedBox(height: 24),
        if (riskVisible) _buildRiskSection(isDark, l10n),
        _buildRecentAuditSection(isDark, l10n),
      ],
    );
  }

  Widget _buildMetricsGrid(bool isDark, {required bool compact}) {
    final l10n = AppLocalizations.of(context);
    final breakpoint = UhcResponsive.breakpointOf(context);
    final ratio = switch (breakpoint) {
      UhcBreakpoint.phone => 1.22,
      UhcBreakpoint.tablet => 1.75,
      UhcBreakpoint.laptop || UhcBreakpoint.desktop => compact ? 2.85 : 1.8,
    };

    return ResponsiveGrid(
      phoneColumns: 2,
      tabletColumns: 3,
      laptopColumns: compact ? 2 : 3,
      desktopColumns: compact ? 2 : 3,
      childAspectRatio: ratio,
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildKpiCard(
          l10n.totalAdmins,
          '$_totalAdmins',
          Icons.admin_panel_settings,
          AppColors.primary,
          isDark,
        ),
        _buildKpiCard(
          l10n.activeAdmins,
          '$_activeAdmins',
          Icons.check_circle,
          AppColors.success,
          isDark,
        ),
        _buildKpiCard(
          l10n.inactiveAdmins,
          '$_inactiveAdmins',
          Icons.block,
          AppColors.error,
          isDark,
        ),
        _buildKpiCard(
          l10n.superAdmins,
          '$_superAdminCount/2',
          Icons.shield,
          const Color(0xFFD32F2F),
          isDark,
        ),
        _buildKpiCard(
          l10n.manageUsers,
          '$_totalUsers',
          Icons.people,
          AppColors.secondary,
          isDark,
        ),
        _buildKpiCard(
          l10n.doctors,
          '$_totalDoctors',
          Icons.local_hospital,
          AppColors.tertiary,
          isDark,
        ),
      ],
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
        if (_recentLogs.isEmpty)
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
    final allFilled = _primarySlotFilled && _backupSlotFilled;
    final color = allFilled ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(16),
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
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allFilled ? l10n.slotHealthy : l10n.slotAttentionNeeded,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 14, color: color),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _slotDot(l10n.primarySlot, _primarySlotFilled),
                    const SizedBox(width: 16),
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
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 260;
            final content = [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              SizedBox(width: wide ? 16 : 0, height: wide ? 0 : 8),
              if (wide)
                Expanded(
                  child: _buildKpiText(label, value, color, isDark, wide: true),
                )
              else
                _buildKpiText(label, value, color, isDark, wide: false),
            ];

            return wide
                ? Row(children: content)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: content,
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
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: wide ? 24 : 22,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: wide ? 12 : 11,
            height: 1.15,
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
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⚠ ${l10n.riskWarnings}',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppColors.warning)),
          const SizedBox(height: 8),
          if (!_primarySlotFilled)
            _riskTile(
                l10n.primarySlotEmpty, Icons.star, AppColors.error, isDark),
          if (!_backupSlotFilled)
            _riskTile(l10n.backupSlotEmpty, Icons.star_border,
                AppColors.warning, isDark),
          if (_inactiveAdmins > 0)
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
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFD32F2F).withValues(alpha: 0.1),
          child: const Icon(Icons.history, size: 16, color: Color(0xFFD32F2F)),
        ),
        title: Text(
          action
              .replaceAll('.', ' → ')
              .split(' ')
              .map((w) =>
                  w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
              .join(' '),
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${actorName.isNotEmpty ? 'By $actorName' : ''}${targetName.isNotEmpty ? ' → $targetName' : ''}',
          style: GoogleFonts.poppins(fontSize: 10),
        ),
      ),
    );
  }
}

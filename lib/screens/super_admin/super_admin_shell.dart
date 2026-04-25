import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import 'super_admin_dashboard_screen.dart';
import '../patient/profile/profile_screen.dart';
import 'admin_control_screen.dart';
import 'audit_log_screen.dart';

/// Super Admin navigation shell with dedicated bottom navigation.
///
/// Provides a distinct experience from regular admin, with governance
/// (admin management, permissions, slots) and audit-log access as
/// first-class tabs rather than sub-screens.
class SuperAdminShell extends StatefulWidget {
  final int initialIndex;

  const SuperAdminShell({super.key, this.initialIndex = 0});

  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  late int _currentIndex;
  late Set<int> _visitedScreens;

  // Accent color for super-admin branding
  static const Color _accent = Color(0xFFD32F2F); // Deep red

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _visitedScreens = {widget.initialIndex};
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      _visitedScreens.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Super Admin Dashboard (governance KPIs)
          _visitedScreens.contains(0)
              ? const SuperAdminDashboardScreen()
              : const SizedBox.shrink(),
          // Tab 1: Admin Control (governance panel)
          _visitedScreens.contains(1)
              ? const AdminControlScreen(initialTab: 0)
              : const SizedBox.shrink(),
          // Tab 2: Permissions
          _visitedScreens.contains(2)
              ? const AdminControlScreen(initialTab: 1)
              : const SizedBox.shrink(),
          // Tab 3: Audit Logs
          _visitedScreens.contains(3)
              ? const AuditLogScreen()
              : const SizedBox.shrink(),
          // Tab 4: Profile
          _visitedScreens.contains(4)
              ? const ProfileScreen()
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: SizedBox(
          height: 70,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        AppColors.surfaceDark.withValues(alpha: 1),
                        AppColors.surfaceDark,
                      ]
                    : [
                        AppColors.surfaceLight.withValues(alpha: 1),
                        AppColors.surfaceLight,
                      ],
              ),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: l10n.adminDashboard,
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.admin_panel_settings_outlined,
                  activeIcon: Icons.admin_panel_settings,
                  label: l10n.admins,
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.security_outlined,
                  activeIcon: Icons.security,
                  label: l10n.permissions,
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 3,
                  icon: Icons.history_outlined,
                  activeIcon: Icons.history_rounded,
                  label: l10n.auditLogs,
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 4,
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: AppLocalizations.of(context).profile,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isDark,
    bool showBadge = false,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 65,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected
                      ? _accent
                      : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight),
                  size: 24,
                ),
                if (showBadge)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? _accent
                    : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

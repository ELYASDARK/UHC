import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../home/home_screen.dart';
import '../doctors/doctor_list_screen.dart';
import '../appointments/my_appointments_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../departments/department_browsing_screen.dart';

/// Main navigation shell with bottom navigation
class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;
  String? _selectedDepartmentKey;

  // Track which screens have been visited for lazy loading
  late Set<int> _visitedScreens;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // Only mark the initial screen as visited
    _visitedScreens = {widget.initialIndex};
    // Load notifications after first frame (non-blocking)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotifications();
    });
  }

  Future<void> _loadNotifications() async {
    final authProvider = context.read<AuthProvider>();
    final notificationProvider = context.read<NotificationProvider>();

    if (authProvider.user != null) {
      await notificationProvider.loadNotifications(authProvider.user!.id);
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      _visitedScreens.add(index); // Mark as visited for lazy loading
      // Clear department filter when manually switching tabs
      if (index != 1) {
        _selectedDepartmentKey = null;
      }
    });
  }

  void _onDepartmentTapped(String departmentKey) {
    setState(() {
      _selectedDepartmentKey = departmentKey;
      _currentIndex = 1; // Switch to doctors tab
      _visitedScreens.add(1); // Mark as visited
    });
  }

  // GlobalKey to access MyAppointmentsScreen state
  final _appointmentsKey = GlobalKey<MyAppointmentsScreenState>();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      extendBody: true, // Extends body behind bottom nav bar
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Index 0: Home Screen (always built first - it's the initial screen)
          _visitedScreens.contains(0)
              ? HomeScreen(
                  onDoctorsTap: () => _onTabTapped(1),
                  onAppointmentsTap: () {
                    _appointmentsKey.currentState?.switchToTab(0);
                    _onTabTapped(2);
                  },
                  onHistoryTap: () {
                    _appointmentsKey.currentState?.switchToTab(1);
                    _onTabTapped(2);
                  },
                  onNotificationsTap: () => _onTabTapped(3),
                  onBookNowTap: () => _onTabTapped(1),
                  onDepartmentsTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DepartmentBrowsingScreen(),
                      ),
                    );
                  },
                  onDepartmentTap: _onDepartmentTapped,
                )
              : const SizedBox.shrink(),
          // Index 1: Doctors Screen (lazy loaded)
          _visitedScreens.contains(1)
              ? DoctorListScreen(
                  key: ValueKey(_selectedDepartmentKey),
                  initialDepartmentKey: _selectedDepartmentKey,
                )
              : const SizedBox.shrink(),
          // Index 2: Appointments Screen (lazy loaded)
          _visitedScreens.contains(2)
              ? MyAppointmentsScreen(key: _appointmentsKey)
              : const SizedBox.shrink(),
          // Index 3: Notifications Screen (lazy loaded)
          _visitedScreens.contains(3)
              ? const NotificationsScreen()
              : const SizedBox.shrink(),
          // Index 4: Profile Screen (lazy loaded)
          _visitedScreens.contains(4)
              ? const ProfileScreen()
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent, // Remove divider line
        ),
        child: SizedBox(
          height: 90,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              // Bottom navigation bar with water/translucent effect
              Container(
                height: 70,
                decoration: BoxDecoration(
                  // Simple translucent effect (no blur for performance)
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? [
                            AppColors.surfaceDark.withValues(alpha: 1),
                            AppColors.surfaceDark,
                          ]
                        : [Colors.white.withValues(alpha: 1), Colors.white],
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
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      label: l10n.home,
                      isDark: isDark,
                    ),
                    _buildNavItem(
                      index: 1,
                      icon: Icons.people_outline_rounded,
                      activeIcon: Icons.people_rounded,
                      label: l10n.doctors,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 70), // Space for FAB
                    // Use Consumer to reactively show badge based on unread count
                    Consumer<NotificationProvider>(
                      builder: (context, notificationProvider, _) {
                        return _buildNavItem(
                          index: 3,
                          icon: Icons.notifications_outlined,
                          activeIcon: Icons.notifications_rounded,
                          label: l10n.alerts,
                          isDark: isDark,
                          showBadge: notificationProvider.unreadCount > 0,
                        );
                      },
                    ),
                    _buildNavItem(
                      index: 4,
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                      label: l10n.profile,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              // Center FAB with Appointments label - positioned above
              Positioned(bottom: 15, child: _buildCenterFabItem(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterFabItem(bool isDark) {
    final isSelected = _currentIndex == 2;
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () => _onTabTapped(2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.appointments,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? AppColors.primary
                  : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight),
            ),
          ),
        ],
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
                      ? AppColors.primary
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
                    ? AppColors.primary
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

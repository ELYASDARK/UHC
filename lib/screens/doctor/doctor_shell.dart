import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';
import '../../data/repositories/doctor_repository.dart';
import '../../providers/notification_provider.dart';
import '../../providers/auth_provider.dart';
import 'appointments/doctor_appointments_screen.dart';
import 'dashboard/doctor_dashboard_screen.dart';
import 'schedule/doctor_schedule_management_screen.dart';
import 'profile/doctor_profile_screen.dart';
import '../shared/notifications_screen.dart';

/// Doctor navigation shell with 5-tab bottom navigation
class DoctorShell extends StatefulWidget {
  final DoctorModel doctor;
  final int initialIndex;

  const DoctorShell({super.key, required this.doctor, this.initialIndex = 0});

  @override
  State<DoctorShell> createState() => _DoctorShellState();
}

class _DoctorShellState extends State<DoctorShell> {
  late int _currentIndex;
  late Set<int> _visitedScreens;
  late DoctorModel _doctor;
  final DoctorRepository _doctorRepo = DoctorRepository();

  @override
  void initState() {
    super.initState();
    _doctor = widget.doctor;
    _currentIndex = widget.initialIndex;
    _visitedScreens = {widget.initialIndex};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initNotifications();
    });
  }

  /// Re-fetch doctor data from Firestore and rebuild all tabs.
  Future<void> _refreshDoctor() async {
    final updated = await _doctorRepo.getDoctorById(_doctor.id);
    if (updated != null && mounted) {
      setState(() => _doctor = updated);
    }
  }

  Future<void> _initNotifications() async {
    final authProvider = context.read<AuthProvider>();
    final notificationProvider = context.read<NotificationProvider>();
    if (authProvider.currentUser != null) {
      await notificationProvider.initialize(
        authProvider.currentUser!.id,
        role: authProvider.currentUser!.role.name,
        department: _doctor.departmentId,
      );
    }
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
          // Tab 0: Dashboard
          _visitedScreens.contains(0)
              ? DoctorDashboardScreen(
                  doctor: _doctor,
                  onDoctorUpdated: _refreshDoctor,
                  onNotificationsTap: () => _onTabTapped(3),
                )
              : const SizedBox.shrink(),
          // Tab 1: Appointments
          _visitedScreens.contains(1)
              ? DoctorAppointmentsScreen(doctor: _doctor)
              : const SizedBox.shrink(),
          // Tab 2: Schedule
          _visitedScreens.contains(2)
              ? DoctorScheduleManagementScreen(doctor: _doctor)
              : const SizedBox.shrink(),
          // Tab 3: Notifications
          _visitedScreens.contains(3)
              ? const NotificationsScreen()
              : const SizedBox.shrink(),
          // Tab 4: Profile
          _visitedScreens.contains(4)
              ? DoctorProfileScreen(
                  doctor: _doctor,
                  onDoctorUpdated: _refreshDoctor,
                )
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
                        AppColors.surfaceLight
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
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: l10n.home,
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.calendar_today_outlined,
                  activeIcon: Icons.calendar_today_rounded,
                  label: l10n.appointments,
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.schedule_outlined,
                  activeIcon: Icons.schedule_rounded,
                  label: l10n.schedule,
                  isDark: isDark,
                ),
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

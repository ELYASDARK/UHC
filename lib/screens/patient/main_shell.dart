import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/widgets/shell_bottom_navigation_bar.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import 'home/home_screen.dart';
import 'browse_doctors/doctor_list_screen.dart';
import 'appointments/my_appointments_screen.dart';
import '../shared/notifications_screen.dart';
import 'profile/profile_screen.dart';
import 'departments/department_browsing_screen.dart';

/// Main navigation shell with bottom navigation
class MainShell extends StatefulWidget {
  final int initialIndex;
  final bool initializeNotifications;
  final bool captureHomeDepartmentsError;

  const MainShell({
    super.key,
    this.initialIndex = 0,
    this.initializeNotifications = true,
    this.captureHomeDepartmentsError = false,
  });

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
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
    if (widget.initializeNotifications) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadNotifications();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listenToNotificationsOnly();
      });
    }
  }

  void _listenToNotificationsOnly() {
    final user = context.read<AuthProvider>().user;
    if (user != null) {
      context.read<NotificationProvider>().startListening(user.id);
    }
  }

  Future<void> _loadNotifications() async {
    final authProvider = context.read<AuthProvider>();
    final notificationProvider = context.read<NotificationProvider>();

    if (authProvider.user != null) {
      // initialize() saves FCM token, subscribes to topics, and starts
      // real-time notification streams.  It is idempotent, so calling it
      // every time the shell mounts is safe.
      await notificationProvider.initialize(
        authProvider.user!.id,
        role: authProvider.user!.role.name,
      );
    }
  }

  void selectTab(int index) {
    if (index == 2) _appointmentsKey.currentState?.refreshAppointments();
    _onTabTapped(index);
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
    final l10n = AppLocalizations.of(context);

    final body = IndexedStack(
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
                onNotificationsTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen())),
                onBookNowTap: () => _onTabTapped(1),
                onDepartmentsTap: () async {
                  final departmentKey = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DepartmentBrowsingScreen(),
                    ),
                  );
                  if (!mounted || departmentKey == null) return;
                  _onDepartmentTapped(departmentKey);
                },
                onDepartmentTap: _onDepartmentTapped,
                captureDepartmentsError: widget.captureHomeDepartmentsError,
              )
            : const SizedBox.shrink(),
        // Index 1: Doctors Screen (lazy loaded)
        _visitedScreens.contains(1)
            ? DoctorListScreen(
                initialDepartmentKey: _selectedDepartmentKey,
              )
            : const SizedBox.shrink(),
        // Index 2: Appointments Screen (lazy loaded)
        _visitedScreens.contains(2)
            ? MyAppointmentsScreen(key: _appointmentsKey)
            : const SizedBox.shrink(),
        // Index 3: Profile Screen (lazy loaded)
        _visitedScreens.contains(3)
            ? const ProfileScreen()
            : const SizedBox.shrink(),
      ],
    );

    return AdaptiveNavigationScaffold(
      selectedIndex: _currentIndex,
      onDestinationSelected: _onTabTapped,
      extendBody: false,
      body: body,
      bottomNavigationBar: PatientBottomNavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTapped,
      ),
      destinations: [
        AdaptiveNavigationDestination(
          index: 0,
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
          label: l10n.home,
        ),
        AdaptiveNavigationDestination(
          index: 1,
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
          label: l10n.doctors,
        ),
        AdaptiveNavigationDestination(
          index: 2,
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
          label: l10n.appointments,
        ),
        AdaptiveNavigationDestination(
          index: 3,
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          label: l10n.profile,
        ),
      ],
    );
  }
}

/// Patient destinations rendered with the same navigation as the doctor shell.
class PatientBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const PatientBottomNavigationBar(
      {super.key,
      required this.selectedIndex,
      required this.onDestinationSelected});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ShellBottomNavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: [
          AdaptiveNavigationDestination(
              index: 0,
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: l10n.home),
          AdaptiveNavigationDestination(
              index: 1,
              icon: Icons.people_outline_rounded,
              selectedIcon: Icons.people_rounded,
              label: l10n.doctors),
          AdaptiveNavigationDestination(
              index: 2,
              icon: Icons.calendar_today_outlined,
              selectedIcon: Icons.calendar_today_rounded,
              label: l10n.appointments),
          AdaptiveNavigationDestination(
              index: 3,
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: l10n.profile),
        ]);
  }
}

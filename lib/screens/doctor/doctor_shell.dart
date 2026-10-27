import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/widgets/shell_bottom_navigation_bar.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../data/models/doctor_model.dart';
import '../../data/repositories/doctor_repository.dart';
import '../../providers/notification_provider.dart';
import '../../providers/auth_provider.dart';
import 'appointments/doctor_appointments_screen.dart';
import 'dashboard/doctor_dashboard_screen.dart';
import 'schedule/doctor_schedule_management_screen.dart';
import 'profile/doctor_profile_screen.dart';
import '../shared/notifications_screen.dart';

/// Doctor navigation shell with four destinations
class DoctorShell extends StatefulWidget {
  final DoctorModel doctor;
  final int initialIndex;
  final bool enableLiveDoctorUpdates;
  final DateTime? referenceTime;

  const DoctorShell({
    super.key,
    required this.doctor,
    this.initialIndex = 0,
    this.enableLiveDoctorUpdates = true,
    this.referenceTime,
  });

  @override
  State<DoctorShell> createState() => _DoctorShellState();
}

class _DoctorShellState extends State<DoctorShell> {
  late int _currentIndex;
  late Set<int> _visitedScreens;
  late DoctorModel _doctor;
  final DoctorRepository _doctorRepo = DoctorRepository();
  StreamSubscription<DoctorModel?>? _doctorSubscription;

  @override
  void initState() {
    super.initState();
    _doctor = widget.doctor;
    _currentIndex = widget.initialIndex;
    _visitedScreens = {widget.initialIndex};
    if (widget.enableLiveDoctorUpdates) {
      _startDoctorStream();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initNotifications();
    });
  }

  @override
  void didUpdateWidget(covariant DoctorShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.doctor.id != oldWidget.doctor.id) {
      _doctor = widget.doctor;
      if (widget.enableLiveDoctorUpdates) {
        _startDoctorStream();
      }
    }
    if (widget.enableLiveDoctorUpdates != oldWidget.enableLiveDoctorUpdates) {
      if (widget.enableLiveDoctorUpdates) {
        _startDoctorStream();
      } else {
        _doctorSubscription?.cancel();
        _doctorSubscription = null;
      }
    }
  }

  void _startDoctorStream() {
    _doctorSubscription?.cancel();
    _doctorSubscription = _doctorRepo.streamDoctorById(_doctor.id).listen(
      (updated) {
        if (updated == null || !mounted) return;
        setState(() => _doctor = updated);
      },
      onError: (error) {
        debugPrint('Doctor live refresh failed: $error');
      },
    );
  }

  @override
  void dispose() {
    _doctorSubscription?.cancel();
    super.dispose();
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
    final l10n = AppLocalizations.of(context);

    final body = IndexedStack(
      index: _currentIndex,
      children: [
        // Tab 0: Dashboard
        _visitedScreens.contains(0)
            ? DoctorDashboardScreen(
                doctor: _doctor,
                onDoctorUpdated: _refreshDoctor,
                onNotificationsTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen())),
                referenceTime: widget.referenceTime,
              )
            : const SizedBox.shrink(),
        // Tab 1: Appointments
        _visitedScreens.contains(1)
            ? DoctorAppointmentsScreen(
                doctor: _doctor,
                referenceTime: widget.referenceTime,
              )
            : const SizedBox.shrink(),
        // Tab 2: Schedule
        _visitedScreens.contains(2)
            ? DoctorScheduleManagementScreen(
                doctor: _doctor, isActive: _currentIndex == 2)
            : const SizedBox.shrink(),
        // Tab 3: Profile
        _visitedScreens.contains(3)
            ? DoctorProfileScreen(
                doctor: _doctor,
                onDoctorUpdated: _refreshDoctor,
              )
            : const SizedBox.shrink(),
      ],
    );

    return AdaptiveNavigationScaffold(
      selectedIndex: _currentIndex,
      onDestinationSelected: _onTabTapped,
      extendBody: false,
      body: body,
      bottomNavigationBar: ShellBottomNavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTapped,
        destinations: [
          AdaptiveNavigationDestination(
              index: 0,
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: l10n.home),
          AdaptiveNavigationDestination(
              index: 1,
              icon: Icons.calendar_today_outlined,
              selectedIcon: Icons.calendar_today_rounded,
              label: l10n.appointments),
          AdaptiveNavigationDestination(
              index: 2,
              icon: Icons.schedule_outlined,
              selectedIcon: Icons.schedule_rounded,
              label: l10n.schedule),
          AdaptiveNavigationDestination(
              index: 3,
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: l10n.profile),
        ],
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
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
          label: l10n.appointments,
        ),
        AdaptiveNavigationDestination(
          index: 2,
          icon: Icons.schedule_outlined,
          selectedIcon: Icons.schedule_rounded,
          label: l10n.schedule,
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

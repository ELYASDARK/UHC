import 'dart:io';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/localization_helper.dart';
import '../../core/widgets/glassmorphic_card.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../data/models/department_model.dart';
import '../../data/repositories/department_repository.dart';
import '../../l10n/app_localizations.dart';

/// Home dashboard screen
class HomeScreen extends StatefulWidget {
  final VoidCallback? onDoctorsTap;
  final VoidCallback? onAppointmentsTap;
  final VoidCallback? onHistoryTap; // New: for past appointments
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onBookNowTap;
  final VoidCallback? onDepartmentsTap; // New callback
  final Function(String departmentKey)? onDepartmentTap;

  const HomeScreen({
    super.key,
    this.onDoctorsTap,
    this.onAppointmentsTap,
    this.onHistoryTap,
    this.onNotificationsTap,
    this.onBookNowTap,
    this.onDepartmentsTap,
    this.onDepartmentTap,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _departmentRepository = DepartmentRepository();
  List<DepartmentModel> _departments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Defer loading to after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDepartments();
    });
  }

  Future<void> _loadDepartments() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final departments = await _departmentRepository.getAllDepartments();
      if (mounted) {
        // Sort departments in specific order for home screen
        final orderedKeys = [
          'generalMedicine',
          'dentistry',
          'psychology',
          'pharmacy',
          'cardiology',
        ];
        final sortedDepartments = <DepartmentModel>[];

        // First add departments in the specified order
        for (final key in orderedKeys) {
          final dept =
              departments.where((d) => d.departmentKey == key).firstOrNull;
          if (dept != null) {
            sortedDepartments.add(dept);
          }
        }

        // Then add any remaining departments not in the order
        for (final dept in departments) {
          if (!orderedKeys.contains(dept.departmentKey)) {
            sortedDepartments.add(dept);
          }
        }

        setState(() {
          _departments = sortedDepartments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = AppLocalizations.of(context).connectionError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = authProvider.currentUser;
    final userName = currentUser?.fullName.split(' ').first ?? 'User';
    final photoUrl = currentUser?.photoUrl;

    return Scaffold(
      body: SafeArea(
        bottom: false, // Allow content to go behind bottom nav bar
        child: RefreshIndicator(
          onRefresh: _loadDepartments,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              100,
            ), // Standard top padding, extra bottom for nav bar
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with greeting
                _buildHeader(context, userName, photoUrl, isDark),

                const SizedBox(height: 24),

                // Quick booking card
                _buildQuickBookingCard(context, isDark),

                const SizedBox(height: 28),

                // Quick actions
                _buildQuickActions(context, isDark),

                const SizedBox(height: 28),

                // Departments section
                _buildDepartmentsSection(context, isDark),

                const SizedBox(height: 28),

                // Health tips
                _buildHealthTipsSection(context, isDark),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String userName,
    String? photoUrl,
    bool isDark,
  ) {
    // Get user initial for the avatar
    final initial =
        userName.isNotEmpty ? userName.substring(0, 1).toUpperCase() : 'U';

    return Row(
      children: [
        // 1. Avatar with initials or image
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
            border: Border.all(
              color:
                  isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1),
            ),
          ),
          child: ClipOval(
            child: photoUrl != null
                ? (photoUrl.startsWith('http')
                    ? Image.network(
                        photoUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(
                            initial,
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      )
                    : (kIsWeb
                        ? Center(
                            child: Text(
                              initial,
                              style: GoogleFonts.outfit(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : Image.file(
                            File(photoUrl),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Center(
                              child: Text(
                                initial,
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          )))
                : Center(
                    child: Text(
                      initial,
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
          ),
        ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),

        const SizedBox(width: 16),

        // 2. Welcome Text & Subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${AppLocalizations.of(context).welcome}, $userName',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.2),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context).howAreYouFeeling,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: -0.2),
            ],
          ),
        ),

        // 3. Notification Bell
        Consumer<NotificationProvider>(
          builder: (context, notificationProvider, _) {
            return Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: isDark
                      ? Colors.white10
                      : Colors.grey.withValues(alpha: 0.1),
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    onPressed: widget.onNotificationsTap,
                    icon: Icon(
                      Icons.notifications_none_rounded,
                      size: 26,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  if (notificationProvider.unreadCount > 0)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isDark ? AppColors.surfaceDark : Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
                .animate(delay: 300.ms)
                .fadeIn()
                .scale(begin: const Offset(0.8, 0.8));
          },
        ),
      ],
    );
  }

  Widget _buildQuickBookingCard(BuildContext context, bool isDark) {
    return GradientCard(
      colors: AppColors.primaryGradient,
      onTap: widget.onBookNowTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).bookAnAppointment,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).findBestDoctors,
                  style: GoogleFonts.roboto(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLocalizations.of(context).bookNow,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.medical_services_rounded,
              size: 45,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn(duration: 500.ms).slideY(begin: 0.1);
  }

  Widget _buildQuickActions(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).quickActions,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildActionCard(
              context,
              icon: Icons.people_alt_rounded,
              label: AppLocalizations.of(context).doctors,
              color: AppColors.primary,
              onTap: widget.onDoctorsTap,
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            _buildActionCard(
              context,
              icon: Icons.calendar_today_rounded,
              label: AppLocalizations.of(context).appointments,
              color: AppColors.secondary,
              onTap: widget.onAppointmentsTap,
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            _buildActionCard(
              context,
              icon: Icons.history_rounded,
              label: AppLocalizations.of(context).history,
              color: AppColors.tertiary,
              onTap: widget.onHistoryTap,
              isDark: isDark,
            ),
          ],
        ),
      ],
    ).animate(delay: 400.ms).fadeIn(duration: 500.ms);
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDepartmentsSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocalizations.of(context).departments,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            TextButton(
              onPressed: widget.onDepartmentsTap, // Use new callback
              child: Text(
                AppLocalizations.of(context).viewAll,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            style: GoogleFonts.roboto(
                              fontSize: 12,
                              color: AppColors.error,
                            ),
                          ),
                          TextButton(
                            onPressed: _loadDepartments,
                            child: Text(AppLocalizations.of(context).retry),
                          ),
                        ],
                      ),
                    )
                  : _departments.isEmpty
                      ? Center(
                          child:
                              Text(AppLocalizations.of(context).noDepartments))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          // Show max 4 departments on home, click View All for more
                          itemCount:
                              _departments.length > 4 ? 4 : _departments.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final dept = _departments[index];
                            return _buildDepartmentCard(dept, isDark);
                          },
                        ),
        ),
      ],
    ).animate(delay: 500.ms).fadeIn(duration: 500.ms);
  }

  IconData _getIconFromName(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'medical_services':
        return Icons.local_hospital_rounded;
      case 'dentistry':
        return Icons.sentiment_satisfied_alt_rounded;
      case 'psychology':
        return Icons.psychology_rounded;
      case 'local_pharmacy':
        return Icons.medication_rounded;
      case 'favorite':
        return Icons.favorite_rounded;
      case 'face':
        return Icons.face_rounded;
      default:
        return Icons.medical_services_rounded;
    }
  }

  Color _getColorFromHex(String hexColor) {
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    } catch (e) {
      return AppColors.primary;
    }
  }

  /// Shorten department names for better display
  String _shortenDepartmentName(DepartmentModel dept, AppLocalizations l10n) {
    // Robust check using the key instead of the translated name
    if (dept.departmentKey == 'generalMedicine') {
      // If English, return shortened 'General'. For others, use translation.
      if (Localizations.localeOf(context).languageCode == 'en') {
        return 'General';
      }
    }
    return LocalizationHelper.translateDepartment(dept.name, l10n);
  }

  Widget _buildDepartmentCard(DepartmentModel dept, bool isDark) {
    final color = _getColorFromHex(dept.colorHex);
    return GestureDetector(
      onTap: () => widget.onDepartmentTap?.call(dept.departmentKey),
      child: Container(
        width: 110,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getIconFromName(dept.iconName),
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _shortenDepartmentName(dept, AppLocalizations.of(context)),
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthTipsSection(BuildContext context, bool isDark) {
    final l10n = AppLocalizations.of(context);
    final tips = [
      _HealthTip(
        title: l10n.stayHydrated,
        description: l10n.stayHydratedDesc,
        icon: Icons.water_drop_rounded,
        color: AppColors.info,
      ),
      _HealthTip(
        title: l10n.regularExercise,
        description: l10n.regularExerciseDesc,
        icon: Icons.directions_run_rounded,
        color: AppColors.success,
      ),
      _HealthTip(
        title: l10n.getEnoughSleep,
        description: l10n.getEnoughSleepDesc,
        icon: Icons.bedtime_rounded,
        color: AppColors.secondary,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).healthTips,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 145,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tips.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final tip = tips[index];
              return _buildHealthTipCard(tip, isDark);
            },
          ),
        ),
      ],
    ).animate(delay: 600.ms).fadeIn(duration: 500.ms);
  }

  Widget _buildHealthTipCard(_HealthTip tip, bool isDark) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tip.color.withValues(alpha: 0.1),
            tip.color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tip.color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tip.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(tip.icon, color: tip.color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            tip.title,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: Text(
              tip.description,
              style: GoogleFonts.roboto(
                fontSize: 12,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthTip {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  _HealthTip({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

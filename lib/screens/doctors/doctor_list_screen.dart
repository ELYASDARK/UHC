import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/localization_helper.dart';
import '../../core/widgets/custom_text_field.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../data/models/doctor_model.dart';
import '../../data/models/department_model.dart';
import '../../data/repositories/doctor_repository.dart';
import '../../data/repositories/department_repository.dart';
import '../../l10n/app_localizations.dart';
import '../booking/booking_screen.dart';

/// Doctor list screen with search and filters
class DoctorListScreen extends StatefulWidget {
  final Department? initialDepartment;
  final String? initialDepartmentKey; // New: string-based department key

  const DoctorListScreen({
    super.key,
    this.initialDepartment,
    this.initialDepartmentKey,
  });

  @override
  State<DoctorListScreen> createState() => _DoctorListScreenState();
}

class _DoctorListScreenState extends State<DoctorListScreen> {
  final _searchController = TextEditingController();
  final _doctorRepository = DoctorRepository();
  final _departmentRepository = DepartmentRepository();
  String? _selectedDepartmentName; // Changed to string-based
  bool _isLoading = true;
  List<DoctorModel> _doctors = [];
  List<DepartmentModel> _departments = [];
  String? _error;

  // Stream subscriptions for real-time updates
  StreamSubscription<List<DoctorModel>>? _doctorsSubscription;
  StreamSubscription<List<DepartmentModel>>? _departmentsSubscription;

  @override
  void initState() {
    super.initState();
    // Prefer initialDepartmentKey over initialDepartment (enum)
    if (widget.initialDepartmentKey != null) {
      _selectedDepartmentName = widget.initialDepartmentKey;
    } else if (widget.initialDepartment != null) {
      _selectedDepartmentName = widget.initialDepartment!.name;
    }
    _subscribeToData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _doctorsSubscription?.cancel();
    _departmentsSubscription?.cancel();
    super.dispose();
  }

  /// Subscribe to real-time updates from Firestore
  void _subscribeToData() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Subscribe to doctors stream
    _doctorsSubscription?.cancel();
    _doctorsSubscription = _doctorRepository.streamDoctors().listen(
      (doctors) {
        if (mounted) {
          setState(() {
            _doctors = doctors;
            _isLoading = false;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Failed to load doctors. Pull to retry.';
          });
        }
      },
    );

    // Load departments (they don't change often, so one-time fetch is fine)
    _loadDepartments();
  }

  /// Load departments (one-time fetch, as they don't change often)
  Future<void> _loadDepartments() async {
    try {
      final departments = await _departmentRepository.getAllDepartments();
      if (mounted) {
        setState(() {
          _departments = departments;
        });
      }
    } catch (e) {
      debugPrint('Error loading departments: $e');
    }
  }

  /// Refresh data - used for pull-to-refresh
  Future<void> _refreshData() async {
    // Cancel existing subscription and resubscribe
    _subscribeToData();
  }

  List<DoctorModel> get _filteredDoctors {
    var filtered = _doctors;

    // Filter by department
    if (_selectedDepartmentName != null) {
      filtered = filtered
          .where(
            (d) =>
                d.departmentId.toLowerCase() ==
                _selectedDepartmentName!.toLowerCase(),
          )
          .toList();
    }

    // Filter by search
    final search = _searchController.text.toLowerCase();
    if (search.isNotEmpty) {
      filtered = filtered.where((d) {
        return d.name.toLowerCase().contains(search) ||
            d.specialization.toLowerCase().contains(search);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).doctors,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          // Search and filters
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SearchField(
                  controller: _searchController,
                  hintText: AppLocalizations.of(context).searchDoctors,
                  onChanged: (_) => setState(() {}),
                  // onFilterTap removed to hide filter button
                  showFilter: false,
                ),
                const SizedBox(height: 12),
                _buildDepartmentChips(isDark),
              ],
            ),
          ),

          // Error message
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: AppColors.error)),
            ),

          // Doctor list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child: _isLoading
                  ? _buildLoadingList()
                  : _doctors.isEmpty
                      ? _buildEmptyState(
                          isDark,
                          message: AppLocalizations.of(context).noDataFound,
                        )
                      : _filteredDoctors.isEmpty
                          ? _buildEmptyState(
                              isDark,
                              message: AppLocalizations.of(context).noDataFound,
                            ) // You might want a different message for "no matches"
                          : _buildDoctorList(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentChips(bool isDark) {
    // Build list with "All" option first, then departments from Firebase
    // Use departmentKey which automatically converts name to camelCase
    final l10n = AppLocalizations.of(context);
    final chipItems = <(String?, String)>[
      (null, l10n.all),
      ..._departments.map(
        (d) => (
          d.departmentKey,
          LocalizationHelper.translateDepartment(d.name, l10n),
        ),
      ),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chipItems.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (deptKey, label) = chipItems[index];
          final isSelected = _selectedDepartmentName == deptKey;

          return FilterChip(
            selected: isSelected,
            label: Text(label),
            labelStyle: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight),
            ),
            selectedColor: AppColors.primary,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
            checkmarkColor: Colors.white,
            showCheckmark: false,
            onSelected: (_) {
              setState(() {
                _selectedDepartmentName = deptKey;
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildLoadingList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: 4,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => const DoctorCardSkeleton(),
    );
  }

  Widget _buildEmptyState(bool isDark, {String? message}) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 80,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              message ?? AppLocalizations.of(context).noDataFound,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).tryAgain,
              style: GoogleFonts.roboto(
                fontSize: 14,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _filteredDoctors.length,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doctor = _filteredDoctors[index];
        return _DoctorCard(
          doctor: doctor,
          isDark: isDark,
          onTap: () => _navigateToDetail(doctor),
        )
            .animate(delay: Duration(milliseconds: index * 100))
            .fadeIn(duration: 400.ms)
            .slideX(begin: 0.05);
      },
    );
  }

  void _navigateToDetail(DoctorModel doctor) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DoctorDetailScreen(doctor: doctor)),
    );
  }
}

/// Doctor card widget
class _DoctorCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  final VoidCallback onTap;

  const _DoctorCard({
    required this.doctor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Row(
          children: [
            // Photo
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: doctor.photoUrl ?? '',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.person, size: 40),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.person, size: 40),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          doctor.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                        ),
                      ),
                      if (!doctor.isAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            AppLocalizations.of(context).notAvailable,
                            style: GoogleFonts.roboto(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LocalizationHelper.translateDepartment(
                      doctor.specialization,
                      AppLocalizations.of(context),
                    ),
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Doctor detail screen
class DoctorDetailScreen extends StatelessWidget {
  final DoctorModel doctor;

  const DoctorDetailScreen({super.key, required this.doctor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with image
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: doctor.photoUrl ?? '',
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      child: const Icon(Icons.person, size: 100),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      child: const Icon(Icons.person, size: 100),
                    ),
                  ),
                  // Top gradient for back button visibility
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.black.withValues(alpha: 0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  // Bottom gradient for text visibility
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doctor.name,
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          LocalizationHelper.translateDepartment(
                            doctor.specialization,
                            AppLocalizations.of(context),
                          ),
                          style: GoogleFonts.roboto(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats card - Beautiful floating card design
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatItem(
                          LocalizationHelper.formatExperience(
                            doctor.experienceYears,
                            AppLocalizations.of(context),
                          ),
                          AppLocalizations.of(context).experience,
                          Icons.workspace_premium_rounded,
                          isDark,
                        ),
                        _buildStatItem(
                          LocalizationHelper.translateDepartment(
                            doctor.specialization,
                            AppLocalizations.of(context),
                          ),
                          AppLocalizations.of(context).specialty,
                          Icons.medical_services_rounded,
                          isDark,
                        ),
                        _buildStatItem(
                          doctor.isAvailable
                              ? AppLocalizations.of(context).yes
                              : AppLocalizations.of(context).no,
                          AppLocalizations.of(context).available,
                          doctor.isAvailable
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          isDark,
                          valueColor: doctor.isAvailable
                              ? AppColors.success
                              : Colors.red,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // About
                  Text(
                    AppLocalizations.of(context).aboutDoctor,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getLocalizedBio(doctor, context),
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      height: 1.6,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Qualifications
                  Text(
                    AppLocalizations.of(context).qualifications,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: doctor.qualifications.map((q) {
                      return Chip(
                        label: Text(
                          LocalizationHelper.translateQualification(
                            q,
                            AppLocalizations.of(context),
                          ),
                        ),
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.1,
                        ),
                        labelStyle: GoogleFonts.roboto(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        child: SafeArea(
          child: ElevatedButton.icon(
            onPressed: () {
              // Navigate to booking screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BookingScreen(doctor: doctor),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
            ),
            icon: const Icon(Icons.calendar_today_rounded),
            label: Text(
              AppLocalizations.of(context).bookAppointment,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String value,
    String label,
    IconData icon,
    bool isDark, {
    Color? valueColor,
  }) {
    final iconColor = valueColor ?? AppColors.primary;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: valueColor ??
                    (isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight),
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.roboto(
                fontSize: 11,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static final Map<String, String Function(AppLocalizations)>
      _bioLocalizationMap = {
    'Amanda White': (l10n) => l10n.doctorBioAmandaWhite,
    'Lisa Brown': (l10n) => l10n.doctorBioLisaBrown,
    'James Wilson': (l10n) => l10n.doctorBioJamesWilson,
    'Robert Taylor': (l10n) => l10n.doctorBioRobertTaylor,
    'David Lee': (l10n) => l10n.doctorBioDavidLee,
    'Sarah Johnson': (l10n) => l10n.doctorBioSarahJohnson,
    'Emily Davis': (l10n) => l10n.doctorBioEmilyDavis,
    'Michael Chen': (l10n) => l10n.doctorBioMichaelChen,
  };

  String _getLocalizedBio(DoctorModel doctor, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;

    // Use default bio for English, or if no localized bio exists
    // You can adjust this logic to ALWAYS prefer localized if available
    if (locale == 'en') {
      return doctor.bio ?? 'No bio available.';
    }

    // Identify doctor by name content - ideally this should be by ID
    // We check if the doctor's name contains any of the keys in our map
    for (final entry in _bioLocalizationMap.entries) {
      if (doctor.name.contains(entry.key)) {
        return entry.value(l10n);
      }
    }

    return doctor.bio ?? 'No bio available.';
  }
}

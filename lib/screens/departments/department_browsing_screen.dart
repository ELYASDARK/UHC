import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/localization_helper.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../data/models/department_model.dart';
import '../../data/repositories/department_repository.dart';
import '../../l10n/app_localizations.dart';
import '../doctors/doctor_list_screen.dart';

class DepartmentBrowsingScreen extends StatefulWidget {
  const DepartmentBrowsingScreen({super.key});

  @override
  State<DepartmentBrowsingScreen> createState() =>
      _DepartmentBrowsingScreenState();
}

class _DepartmentBrowsingScreenState extends State<DepartmentBrowsingScreen> {
  final _departmentRepository = DepartmentRepository();
  List<DepartmentModel> _departments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    // Only set loading to true if we don't have data yet
    if (_departments.isEmpty) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final departments = await _departmentRepository.getAllDepartments();
      if (mounted) {
        setState(() {
          _departments = departments;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).departments,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: _error != null && _departments.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadDepartments,
                    child: Text(AppLocalizations.of(context).retry),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadDepartments,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).departments,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context).findBestDoctors,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        fontFamily: GoogleFonts.roboto().fontFamily,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Department Cards Grid
                    if (_isLoading && _departments.isEmpty)
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.85,
                        children: List.generate(
                          6,
                          (index) => const CardSkeleton(height: 180),
                        ),
                      )
                    else if (_departments.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            AppLocalizations.of(context).noDepartments,
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      )
                    else
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.85,
                        children: _departments.asMap().entries.map((entry) {
                          final index = entry.key;
                          final dept = entry.value;
                          return _DepartmentCard(
                                department: dept,
                                isDark: isDark,
                              )
                              .animate(
                                delay: Duration(milliseconds: index * 50),
                              )
                              .fadeIn(duration: 400.ms)
                              .slideY(begin: 0.1);
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  final DepartmentModel department;
  final bool isDark;

  const _DepartmentCard({required this.department, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = _getColorFromHex(department.colorHex);
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () => _navigateToDepartment(context),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.2) ?? color],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background pattern
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              left: -10,
              bottom: -10,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _getIconFromName(department.iconName),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    LocalizationHelper.translateDepartment(
                      department.name,
                      l10n,
                    ),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    department.description,
                    style: GoogleFonts.roboto(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        l10n.viewAll, // "View Doctors" or similar
                        style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 16,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDepartment(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DoctorListScreen(initialDepartmentKey: department.departmentKey),
      ),
    );
  }

  Color _getColorFromHex(String hexColor) {
    try {
      var hex = hexColor.replaceAll('#', '');

      // Handle incomplete hex codes
      if (hex.length == 3) {
        hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
      }
      if (hex.length == 4) {
        hex =
            '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}';
      }

      if (hex.length == 6) {
        return Color(int.parse('0xFF$hex'));
      } else if (hex.length == 8) {
        return Color(int.parse('0x$hex'));
      }

      return AppColors.primary;
    } catch (e) {
      return AppColors.primary;
    }
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
      case 'cardiology':
        return Icons.favorite_rounded;
      case 'face':
        return Icons.face_rounded;
      default:
        return Icons.medical_services_rounded;
    }
  }
}

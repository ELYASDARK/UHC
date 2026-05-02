import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/localization_helper.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../data/models/department_model.dart';
import '../../../data/repositories/department_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../browse_doctors/doctor_list_screen.dart';

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
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).departments,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.of(context).findBestDoctors,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                      fontFamily:
                                          GoogleFonts.roboto().fontFamily,
                                    ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  if (_isLoading && _departments.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.78,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return const CardSkeleton(height: 180);
                        }, childCount: 6),
                      ),
                    )
                  else if (_departments.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            AppLocalizations.of(context).noDepartments,
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.78,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final dept = _departments[index];
                          return RepaintBoundary(
                            child: _DepartmentCard(
                              department: dept,
                              isDark: isDark,
                            ),
                          );
                        }, childCount: _departments.length),
                      ),
                    ),
                ],
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

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToDepartment(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getIconFromName(department.iconName),
                  color: Colors.white,
                  size: 24,
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
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                department.description,
                style: GoogleFonts.roboto(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    l10n.viewAll,
                    style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white.withValues(alpha: 0.95),
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
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

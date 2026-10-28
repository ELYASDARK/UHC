import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import 'responsive_layout.dart';

/// Shared bottom navigation for patient and doctor shells.
class ShellBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  final List<AdaptiveNavigationDestination> destinations;

  const ShellBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
            top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                width: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 70),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < destinations.length; index++)
                      Expanded(
                        child: Semantics(
                          selected: selectedIndex == index,
                          button: true,
                          child: InkWell(
                            onTap: () => onDestinationSelected(
                                destinations[index].index),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      selectedIndex == index
                                          ? destinations[index].selectedIcon
                                          : destinations[index].icon,
                                      size: 24,
                                      color: selectedIndex == index
                                          ? AppColors.primary
                                          : isDark
                                              ? AppColors.textSecondaryDark
                                              : AppColors.textSecondaryLight),
                                  const SizedBox(height: 4),
                                  Text(
                                    destinations[index].label,
                                    maxLines: MediaQuery.textScalerOf(context)
                                                .scale(10) <=
                                            12
                                        ? 1
                                        : null,
                                    overflow: MediaQuery.textScalerOf(context)
                                                .scale(10) <=
                                            12
                                        ? TextOverflow.ellipsis
                                        : null,
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: selectedIndex == index
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: selectedIndex == index
                                          ? AppColors.primary
                                          : isDark
                                              ? AppColors.textSecondaryDark
                                              : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

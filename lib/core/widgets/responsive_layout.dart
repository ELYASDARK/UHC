import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum UhcBreakpoint {
  phone,
  tablet,
  laptop,
  desktop,
}

extension UhcBreakpointX on UhcBreakpoint {
  bool get isPhone => this == UhcBreakpoint.phone;
  bool get isTablet => this == UhcBreakpoint.tablet;
  bool get isLaptop => this == UhcBreakpoint.laptop;
  bool get isDesktop => this == UhcBreakpoint.desktop;
  bool get isWide => isLaptop || isDesktop;
}

class UhcResponsive {
  UhcResponsive._();

  static const double tablet = 768;
  static const double laptop = 1024;
  static const double desktop = 1440;

  static UhcBreakpoint breakpointForWidth(double width) {
    if (width >= desktop) return UhcBreakpoint.desktop;
    if (width >= laptop) return UhcBreakpoint.laptop;
    if (width >= tablet) return UhcBreakpoint.tablet;
    return UhcBreakpoint.phone;
  }

  static UhcBreakpoint breakpointOf(BuildContext context) {
    return breakpointForWidth(MediaQuery.sizeOf(context).width);
  }

  static bool isWide(BuildContext context) => breakpointOf(context).isWide;

  static EdgeInsets pagePadding(
    BuildContext context, {
    double? top,
    double bottom = 24,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final breakpoint = breakpointForWidth(width);

    return switch (breakpoint) {
      UhcBreakpoint.phone => EdgeInsets.fromLTRB(16, top ?? 16, 16, bottom),
      UhcBreakpoint.tablet => EdgeInsets.fromLTRB(24, top ?? 24, 24, bottom),
      UhcBreakpoint.laptop => EdgeInsets.fromLTRB(32, top ?? 28, 32, bottom),
      UhcBreakpoint.desktop => EdgeInsets.fromLTRB(40, top ?? 32, 40, bottom),
    };
  }

  static double maxContentWidth(BuildContext context) {
    final breakpoint = breakpointOf(context);
    return switch (breakpoint) {
      UhcBreakpoint.phone => double.infinity,
      UhcBreakpoint.tablet => 760,
      UhcBreakpoint.laptop => 1280,
      UhcBreakpoint.desktop => 1600,
    };
  }

  static int columnsFor(
    BuildContext context, {
    int phone = 1,
    int tablet = 2,
    int laptop = 3,
    int desktop = 4,
  }) {
    return switch (breakpointOf(context)) {
      UhcBreakpoint.phone => phone,
      UhcBreakpoint.tablet => tablet,
      UhcBreakpoint.laptop => laptop,
      UhcBreakpoint.desktop => desktop,
    };
  }

  static double dialogWidth(
    BuildContext context, {
    double phoneFactor = 0.94,
    double tabletWidth = 640,
    double laptopWidth = 760,
    double desktopWidth = 860,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final breakpoint = breakpointForWidth(width);
    final target = switch (breakpoint) {
      UhcBreakpoint.phone => width * phoneFactor,
      UhcBreakpoint.tablet => tabletWidth,
      UhcBreakpoint.laptop => laptopWidth,
      UhcBreakpoint.desktop => desktopWidth,
    };
    return math.min(width - 32, target);
  }
}

class ResponsiveContent extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final AlignmentGeometry alignment;

  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? UhcResponsive.maxContentWidth(context),
        ),
        child: child,
      ),
    );
  }
}

class ResponsivePage extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;
  final bool scrollable;
  final ScrollPhysics? physics;
  final bool safeArea;
  final double bottomPadding;
  final AlignmentGeometry alignment;

  const ResponsivePage({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
    this.scrollable = true,
    this.physics,
    this.safeArea = false,
    this.bottomPadding = 24,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final page = Container(
      color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padded = Padding(
            padding: padding ??
                UhcResponsive.pagePadding(context, bottom: bottomPadding),
            child: ResponsiveContent(
              maxWidth: maxWidth,
              alignment: alignment,
              child: child,
            ),
          );

          if (!scrollable) return padded;

          return SingleChildScrollView(
            physics: physics ?? const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: padded,
            ),
          );
        },
      ),
    );

    return safeArea ? SafeArea(child: page) : page;
  }
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int phoneColumns;
  final int tabletColumns;
  final int laptopColumns;
  final int desktopColumns;
  final double spacing;
  final double runSpacing;
  final double childAspectRatio;
  final ScrollPhysics physics;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.phoneColumns = 1,
    this.tabletColumns = 2,
    this.laptopColumns = 3,
    this.desktopColumns = 4,
    this.spacing = 12,
    this.runSpacing = 12,
    this.childAspectRatio = 1.4,
    this.physics = const NeverScrollableScrollPhysics(),
  });

  @override
  Widget build(BuildContext context) {
    final columns = UhcResponsive.columnsFor(
      context,
      phone: phoneColumns,
      tablet: tabletColumns,
      laptop: laptopColumns,
      desktop: desktopColumns,
    );

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: physics,
      mainAxisSpacing: runSpacing,
      crossAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
      children: children,
    );
  }
}

class ResponsiveListView extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final double maxWidth;
  final bool gridOnWide;
  final int tabletColumns;
  final int laptopColumns;
  final int desktopColumns;
  final double spacing;
  final double runSpacing;
  final double childAspectRatio;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  const ResponsiveListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
    this.maxWidth = 980,
    this.gridOnWide = false,
    this.tabletColumns = 1,
    this.laptopColumns = 2,
    this.desktopColumns = 2,
    this.spacing = 12,
    this.runSpacing = 12,
    this.childAspectRatio = 3.4,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  @override
  Widget build(BuildContext context) {
    final breakpoint = UhcResponsive.breakpointOf(context);
    final effectivePadding =
        padding ?? UhcResponsive.pagePadding(context, bottom: 24);

    if (gridOnWide && !breakpoint.isPhone) {
      final columns = switch (breakpoint) {
        UhcBreakpoint.phone => 1,
        UhcBreakpoint.tablet => tabletColumns,
        UhcBreakpoint.laptop => laptopColumns,
        UhcBreakpoint.desktop => desktopColumns,
      };

      return ResponsiveContent(
        maxWidth: maxWidth,
        child: GridView.builder(
          padding: effectivePadding,
          physics: physics,
          shrinkWrap: shrinkWrap,
          keyboardDismissBehavior: keyboardDismissBehavior,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: runSpacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      );
    }

    return ResponsiveContent(
      maxWidth: maxWidth,
      child: ListView.separated(
        padding: effectivePadding,
        physics: physics,
        shrinkWrap: shrinkWrap,
        keyboardDismissBehavior: keyboardDismissBehavior,
        itemCount: itemCount,
        separatorBuilder:
            separatorBuilder ?? (context, index) => SizedBox(height: spacing),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class ResponsiveFormLayout extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final int tabletColumns;
  final int desktopColumns;

  const ResponsiveFormLayout({
    super.key,
    required this.children,
    this.spacing = 16,
    this.runSpacing = 16,
    this.tabletColumns = 2,
    this.desktopColumns = 2,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final breakpoint = UhcResponsive.breakpointForWidth(
          constraints.maxWidth,
        );
        final columns = switch (breakpoint) {
          UhcBreakpoint.phone => 1,
          UhcBreakpoint.tablet => tabletColumns,
          UhcBreakpoint.laptop || UhcBreakpoint.desktop => desktopColumns,
        };
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class AdaptiveDialogConstraints extends StatelessWidget {
  final Widget child;
  final double? maxHeightFactor;
  final double? width;

  const AdaptiveDialogConstraints({
    super.key,
    required this.child,
    this.maxHeightFactor,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width ?? UhcResponsive.dialogWidth(context),
        maxHeight: size.height * (maxHeightFactor ?? 0.9),
      ),
      child: child,
    );
  }
}

class AdaptiveNavigationDestination {
  final int index;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool showBadge;

  const AdaptiveNavigationDestination({
    required this.index,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.showBadge = false,
  });
}

class AdaptiveNavigationScaffold extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveNavigationDestination> destinations;
  final Widget body;
  final Widget bottomNavigationBar;
  final Color? selectedColor;
  final bool extendBody;

  const AdaptiveNavigationScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
    required this.bottomNavigationBar,
    this.selectedColor,
    this.extendBody = false,
  });

  @override
  Widget build(BuildContext context) {
    final breakpoint = UhcResponsive.breakpointOf(context);
    if (breakpoint.isPhone) {
      return Scaffold(
        extendBody: extendBody,
        body: body,
        bottomNavigationBar: bottomNavigationBar,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = selectedColor ?? AppColors.primary;
    final railBackground =
        isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final extended = breakpoint.isLaptop || breakpoint.isDesktop;

    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: NavigationRail(
              extended: extended,
              minExtendedWidth: 220,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              backgroundColor: railBackground,
              selectedIconTheme: IconThemeData(color: accent),
              selectedLabelTextStyle: TextStyle(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
              unselectedIconTheme: IconThemeData(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              unselectedLabelTextStyle: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: _NavigationIcon(
                      icon: destination.icon,
                      showBadge: destination.showBadge,
                    ),
                    selectedIcon: _NavigationIcon(
                      icon: destination.selectedIcon,
                      showBadge: destination.showBadge,
                    ),
                    label: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
          Expanded(
            child: Container(
              color:
                  isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: breakpoint.isDesktop ? 1720 : 1360,
                  ),
                  child: body,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationIcon extends StatelessWidget {
  final IconData icon;
  final bool showBadge;

  const _NavigationIcon({
    required this.icon,
    required this.showBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
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
    );
  }
}

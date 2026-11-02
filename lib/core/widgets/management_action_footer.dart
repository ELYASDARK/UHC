import 'package:flutter/material.dart';

/// Scaffold reserves the measured action and system inset before laying out lists.
class ManagementActionFooter extends StatelessWidget {
  const ManagementActionFooter({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Align(
            heightFactor: 1,
            alignment: AlignmentDirectional.centerEnd,
            child: child),
      );
}

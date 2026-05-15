import 'package:flutter/material.dart';

/// Forces a subtree to use English locale and LTR direction.
class RoleEnglishLtrScope extends StatelessWidget {
  final Widget child;

  const RoleEnglishLtrScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Localizations.override(
      context: context,
      locale: const Locale('en'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: child,
      ),
    );
  }
}

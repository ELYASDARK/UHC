import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/locale_provider.dart';
import '../../services/auth_service.dart';
import '../../services/department_functions_service.dart';
import '../../services/doctor_functions_service.dart';
import '../constants/app_colors.dart';

/// Presentation boundary for transient feedback and untrusted service errors.
class AppMessages {
  static AppLocalizations localizations(BuildContext context) =>
      lookupAppLocalizations(context.read<LocaleProvider?>()?.locale ??
          Localizations.localeOf(context));

  static String error(BuildContext context, Object? error) {
    final l10n = localizations(context);
    final code = switch (error) {
      FirebaseException e => e.code,
      DoctorFunctionException e => e.code,
      DepartmentFunctionException e => e.code,
      AuthException e => e.code,
      TimeoutException() => 'deadline-exceeded',
      String value => _stringCode(value),
      _ => '',
    };
    return switch (code) {
      'unavailable' ||
      'network-request-failed' ||
      'deadline-exceeded' ||
      'network-error' =>
        l10n.requestNetworkError,
      'permission-denied' || 'unauthorized' => l10n.noPermissionForAction,
      'unauthenticated' || 'requires-recent-login' => l10n.sessionExpired,
      'invalid-credential' ||
      'invalid-login-credentials' ||
      'wrong-password' ||
      'user-not-found' =>
        l10n.authInvalidCredentials,
      'email-already-in-use' => l10n.authEmailUsed,
      'user-disabled' => l10n.authAccountDisabled,
      'weak-password' => l10n.weakPassword,
      'invalid-email' => l10n.invalidEmail,
      'resource-exhausted' || 'too-many-requests' => l10n.requestLimitReached,
      'already-exists' ||
      'aborted' ||
      'failed-precondition' =>
        l10n.requestConflict,
      'invalid-argument' => l10n.requestInvalid,
      'not-found' => l10n.requestNotFound,
      _ => l10n.requestFailed,
    };
  }

  // Existing providers sometimes retain a string rather than the SDK exception.
  // Only a known category is recovered; no server-supplied prose is displayed.
  static String _stringCode(String value) {
    if (const {
      'permission-denied',
      'unauthenticated',
      'unavailable',
      'deadline-exceeded',
      'resource-exhausted',
      'invalid-argument',
      'already-exists',
      'failed-precondition',
      'not-found'
    }.contains(value)) {
      return value;
    }
    final match = RegExp(r'^\[(?:firebase_[a-z_]+|cloud_firestore)/([a-z-]+)\]')
        .firstMatch(value);
    if (match != null) return match.group(1)!;
    return switch (value) {
      'Incorrect email or password. Please try again.' => 'invalid-credential',
      'This email is already registered.' => 'email-already-in-use',
      'Password is too weak.' => 'weak-password',
      'Please sign in again, then choose your new password.' =>
        'requires-recent-login',
      'Invalid email address.' => 'invalid-email',
      'This account has been disabled.' ||
      'Your account has been deactivated. Please contact support.' =>
        'user-disabled',
      'Too many attempts. Please try again later.' => 'too-many-requests',
      _ => '',
    };
  }

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
      BuildContext context, SnackBar message) {
    final theme = Theme.of(context);
    final background = switch (message.backgroundColor) {
      AppColors.error => const Color(0xFF9C2525),
      AppColors.success => const Color(0xFF17613A),
      AppColors.warning => const Color(0xFF755000),
      _ => theme.colorScheme.inverseSurface,
    };
    final foreground = message.backgroundColor == AppColors.error ||
            message.backgroundColor == AppColors.success ||
            message.backgroundColor == AppColors.warning
        ? Colors.white
        : theme.colorScheme.onInverseSurface;
    final action = message.action;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    return messenger.showSnackBar(SnackBar(
      content: DefaultTextStyle.merge(
        style: TextStyle(color: foreground, fontSize: 14, height: 1.35),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.3),
          child: SingleChildScrollView(
            child: message.content is Row
                ? Row(children: [
                    for (final child in (message.content as Row).children)
                      if (child is Text) Flexible(child: child) else child,
                  ])
                : message.content,
          ),
        ),
      ),
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      closeIconColor: foreground,
      duration: message.duration,
      action: action == null
          ? null
          : SnackBarAction(
              label: action.label,
              onPressed: action.onPressed,
              textColor: foreground,
            ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onVisible: message.onVisible,
    ));
  }
}

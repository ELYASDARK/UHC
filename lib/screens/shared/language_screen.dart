import 'package:uhc/core/utils/app_messages.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';

/// Language settings shared by every role's profile.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  static const _englishNames = {
    'en': 'English',
    'ar': 'Arabic',
    'ku': 'Kurdish',
  };

  bool _saving = false;

  Future<void> _select(String code) async {
    if (_saving || context.read<LocaleProvider>().locale.languageCode == code) {
      return;
    }
    final locale = context.read<LocaleProvider>();
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      final saved = !auth.isAuthenticated || await auth.updateLanguage(code);
      if (!mounted) return;
      if (!saved) {
        AppMessages.show(
          context,
          SnackBar(content: Text(AppMessages.localizations(context).tryAgain)),
        );
        return;
      }
      await locale.setLocaleByCode(code);
    } catch (_) {
      if (mounted) {
        AppMessages.show(
          context,
          SnackBar(content: Text(AppMessages.localizations(context).tryAgain)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight *
            (MediaQuery.textScalerOf(context).scale(20) / 20).clamp(1.0, 2.0),
        title: Text(AppLocalizations.of(context).selectLanguage, maxLines: 2),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_saving) const LinearProgressIndicator(),
              Material(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final entry in AppLocale.languageNames.entries) ...[
                      if (entry.key != AppLocale.languageNames.keys.first)
                        const Divider(height: 1, indent: 20, endIndent: 20),
                      _languageRow(entry, locale.locale.languageCode),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _languageRow(MapEntry<String, String> language, String selectedCode) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = selectedCode == language.key;
    final alignment = Directionality.of(context) == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left;
    return Semantics(
      selected: selected,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minTileHeight: 80,
        enabled: !_saving,
        selected: selected,
        title: Text(
          language.value,
          textDirection: AppLocale.isRtl(Locale(language.key))
              ? TextDirection.rtl
              : TextDirection.ltr,
          textAlign: alignment,
          style: theme.textTheme.titleMedium?.copyWith(color: colors.onSurface),
        ),
        subtitle: Text(
          _englishNames[language.key]!,
          textDirection: TextDirection.ltr,
          textAlign: alignment,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: colors.primary)
            : null,
        onTap: () => _select(language.key),
      ),
    );
  }
}

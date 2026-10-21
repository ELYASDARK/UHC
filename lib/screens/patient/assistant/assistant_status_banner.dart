import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/locale_utils.dart';
import '../../../data/models/assistant_chat_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/assistant_chat_provider.dart';

class AssistantStatusBanner extends StatelessWidget {
  const AssistantStatusBanner(
      {super.key, required this.provider, required this.onBookManually});

  final AssistantChatProvider provider;
  final VoidCallback onBookManually;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (provider.currentStatus) {
      AssistantMessageStatus.dailyLimit =>
        _buildDailyLimitBanner(context, provider, l10n, isDark),
      AssistantMessageStatus.disabled =>
        _buildDisabledBanner(provider, l10n, isDark),
      AssistantMessageStatus.unavailable =>
        _buildUnavailableBanner(provider, l10n, isDark),
      AssistantMessageStatus.throttled =>
        _buildThrottledBanner(provider, l10n, isDark),
      _ => provider.errorMessage == null
          ? const SizedBox.shrink()
          : _buildGenericErrorBanner(provider, l10n, isDark),
    };
  }

  Widget _buildDailyLimitBanner(
    BuildContext context,
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    String resetText = '';
    if (provider.resetAt != null) {
      final localReset = provider.resetAt!.toLocal();
      final locale = safeIntlLocale(context);
      final formattedTime =
          intl.DateFormat('h:mm a, MMM d', locale).format(localReset);
      resetText = l10n.assistantResetsAt(formattedTime);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_empty,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.assistantDailyLimitHeading,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.assistantSharedLimitExplanation,
            style: GoogleFonts.roboto(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          if (resetText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              resetText,
              style: GoogleFonts.roboto(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ElevatedButton.icon(
              onPressed: onBookManually,
              icon: const Icon(Icons.calendar_month, size: 16),
              label: Text(l10n.bookAnAppointment),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisabledBanner(
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isDark ? Colors.grey[900] : Colors.grey[200],
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.reasonCode == 'assistant_unconfigured'
                      ? l10n.assistantUnavailableNotice
                      : l10n.assistantDisabledNotice,
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: onBookManually,
                  child: Text(
                    l10n.bookAnAppointment,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableBanner(
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.error.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.assistantUnavailableNotice,
              style: GoogleFonts.roboto(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: onBookManually,
            child: Text(l10n.assistantBookDirectly),
          ),
        ],
      ),
    );
  }

  Widget _buildThrottledBanner(
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.warning.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.speed, color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.assistantThrottledNotice,
              style: GoogleFonts.roboto(
                fontSize: 11,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _localizedError(
      AssistantChatProvider provider, AppLocalizations l10n) {
    return switch (provider.failureKind) {
      AssistantFailureKind.historyLoad => l10n.assistantHistoryLoadFailed,
      AssistantFailureKind.unauthenticated =>
        l10n.assistantErrorUnauthenticated,
      AssistantFailureKind.permissionDenied =>
        l10n.assistantErrorPermissionDenied,
      AssistantFailureKind.notFound => l10n.assistantErrorNotFound,
      AssistantFailureKind.dailyLimit => l10n.assistantDailyLimitHeading,
      AssistantFailureKind.throttled => l10n.assistantThrottledNotice,
      AssistantFailureKind.disabled => l10n.assistantDisabledNotice,
      AssistantFailureKind.unavailable => l10n.assistantUnavailableNotice,
      AssistantFailureKind.staleOffer => l10n.assistantStaleOffer,
      _ => provider.errorMessage!,
    };
  }

  Widget _buildGenericErrorBanner(
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final localizedMsg = _localizedError(provider, l10n);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.error.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              localizedMsg,
              style: GoogleFonts.roboto(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          if (provider.canRetryHistory)
            TextButton(
              onPressed: () => provider.refreshHistory(force: true),
              child: Text(l10n.assistantRetrySending),
            ),
        ],
      ),
    );
  }
}

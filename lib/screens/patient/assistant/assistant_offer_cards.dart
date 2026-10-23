import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/localization_helper.dart';
import '../../../data/models/assistant_chat_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/assistant_chat_provider.dart';
import 'assistant_formatting.dart';

class AssistantOfferCards extends StatelessWidget {
  const AssistantOfferCards(
      {super.key,
      required this.offers,
      required this.provider,
      required this.onSelected});

  final List<AssistantOffer> offers;
  final AssistantChatProvider provider;
  final ValueChanged<AssistantOffer> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: offers.map((offer) {
        final now = DateTime.now();
        final isPendingRetry = provider.activeBookingOfferId == offer.offerId;
        final isBookable = offer.isBookable(now);
        final isExpired = offer.isExpired(now);
        final minutesLeft = offer.expiresAt.difference(now.toUtc()).inMinutes;

        final canClick =
            (isBookable || isPendingRetry) && provider.canConfirmOffer(offer);

        String buttonLabel;
        if (isPendingRetry) {
          buttonLabel = l10n.assistantRetrySending;
        } else if (isBookable) {
          buttonLabel = l10n.assistantBookThisSlot;
        } else if (isExpired) {
          buttonLabel = l10n.assistantOfferExpired;
        } else {
          buttonLabel = l10n.unavailable;
        }

        String chipLabel;
        Color chipColor;
        if (isPendingRetry) {
          chipLabel = l10n.assistantRetrySending;
          chipColor = AppColors.warning;
        } else if (isBookable) {
          chipLabel = (minutesLeft > 0
              ? l10n.assistantExpiresInMinutes(minutesLeft)
              : l10n.assistantOfferAvailable);
          chipColor = AppColors.success;
        } else if (isExpired) {
          chipLabel = l10n.assistantOfferExpired;
          chipColor = Colors.grey;
        } else {
          chipLabel = l10n.unavailable;
          chipColor = Colors.grey;
        }

        return Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: canClick
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      offer.doctorName,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      chipLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: chipColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                LocalizationHelper.translateDepartment(
                  offer.departmentName ?? offer.department,
                  l10n,
                ),
                style: GoogleFonts.roboto(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatAssistantDate(offer.appointmentDate, context),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    offer.timeSlot,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canClick ? () => onSelected(offer) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark
                        ? Colors.white10
                        : Colors.grey.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

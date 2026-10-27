import 'package:uhc/core/utils/app_messages.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/models/assistant_chat_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show AppNavigator;
import '../../../providers/assistant_chat_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../services/notification_scheduling_coordinator.dart';
import '../booking/booking_success_screen.dart';
import 'assistant_confirmation_sheet.dart';
import 'assistant_offer_cards.dart';
import 'assistant_status_banner.dart';

/// Screen for the AI Appointment Scheduling Assistant.
/// Provides real-time chat, structured schedule offer cards, affirmative confirmation modal,
/// multi-lingual RTL support, quota and policy fallback routing to standard booking.
class AssistantChatScreen extends StatefulWidget {
  final AssistantChatProvider? provider;

  const AssistantChatScreen({
    super.key,
    this.provider,
  });

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen>
    with WidgetsBindingObserver {
  late final AssistantChatProvider _provider;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _ownsProvider = false;
  int _charCount = 0;
  String? _lastObservedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final user = context.read<AuthProvider>().currentUser;
    _lastObservedUserId = user?.id;

    if (widget.provider != null) {
      _provider = widget.provider!;
      _ownsProvider = false;
    } else {
      _provider = AssistantChatProvider(
        patientId: user?.id,
      );
      _ownsProvider = true;
    }

    _textController.addListener(_onTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider.initialize().then((_) => _scrollToBottom(smooth: false));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthProvider>(context, listen: true);
    final user = auth.currentUser;
    final currentUserId = user?.id;

    if (currentUserId != _lastObservedUserId) {
      _lastObservedUserId = currentUserId;
      _textController.clear();
      if (mounted) {
        setState(() {
          _charCount = 0;
        });
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      }
      _provider.updateActiveUser(
        userId: user?.id,
        role: user?.role,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check slot availability on resume before enabling old suggestions
      _provider.refreshHistory();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    if (_ownsProvider) {
      _provider.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    final text = _textController.text;
    if (_charCount != text.length) {
      setState(() {
        _charCount = text.length;
      });
      _provider.setDraft(text);
    }
  }

  void _scrollToBottom({bool smooth = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (smooth) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  Future<void> _handleSendMessage() async {
    final text = _textController.text.trim();
    if (!_provider.canSendMessage || text.isEmpty || text.length > 500) return;

    final locale = context.read<LocaleProvider>().locale.languageCode;
    _textController.clear();
    setState(() => _charCount = 0);

    final success = await _provider.sendMessage(text, localeCode: locale);
    _scrollToBottom();

    if (!success && _provider.unsentDraft != null && mounted) {
      // Restore draft if sending failed
      _textController.text = _provider.unsentDraft!;
      setState(() => _charCount = _provider.unsentDraft!.length);
    }
  }

  void _navigateToStandardBooking() {
    AppNavigator.returnToPatientTab(context, 1);
  }

  Future<void> _confirmClearChat() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.assistantClearChatConfirmTitle),
        content: Text(l10n.assistantClearChatConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.clear),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await _provider.clearChat();
      if (mounted) {
        if (success) {
          _textController.clear();
          setState(() => _charCount = 0);
          AppMessages.show(
            context,
            SnackBar(
                content: Text(
                    AppMessages.localizations(context).assistantChatCleared)),
          );
        } else {
          AppMessages.show(
            context,
            SnackBar(
              content: Text(
                  AppMessages.localizations(context).assistantClearChatFailed),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _showInfoSheet() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Text(
                    l10n.assistantTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildInfoRow(
                Icons.medical_information_outlined,
                l10n.assistantInfoScopeTitle,
                l10n.assistantPrivacyNotice,
                isDark,
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.history_toggle_off,
                l10n.assistantInfoRetentionTitle,
                l10n.assistantRetentionNotice,
                isDark,
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.access_time_filled,
                l10n.assistantInfoTimezoneTitle,
                l10n.assistantClinicTimezone,
                isDark,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: Text(l10n.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String title,
    String description,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.roboto(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleOfferSelection(AssistantOffer offer) async {
    if (!_provider.canConfirmOffer(offer)) return;
    final isRetry = _provider.activeBookingOfferId == offer.offerId;
    if (!isRetry && !offer.isBookable(DateTime.now())) {
      AppMessages.show(
          context,
          SnackBar(
            content:
                Text(AppMessages.localizations(context).assistantStaleOffer),
            backgroundColor: AppColors.warning,
          ));
      await _provider.refreshHistory();
      return;
    }
    final openingUserId = context.read<AuthProvider>().currentUser?.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AssistantConfirmationSheet(
        offer: offer,
        provider: _provider,
        onConfirmed: (receipt) async {
          if (!mounted ||
              openingUserId == null ||
              context.read<AuthProvider>().currentUser?.id != openingUserId) {
            return;
          }
          await _onBookingSuccess(offer, receipt);
        },
      ),
    );
  }

  Future<void> _onBookingSuccess(
    AssistantOffer offer,
    ConfirmAssistantAppointmentResult result,
  ) async {
    final user = context.read<AuthProvider>().currentUser;
    final appointmentDate = offer.parsedAppointmentDate ?? DateTime.now();

    if (user != null) {
      final appointment = AppointmentModel(
        id: result.appointmentId,
        patientId: user.id,
        patientName: user.fullName,
        patientEmail: user.email,
        doctorId: offer.doctorId,
        doctorName: offer.doctorName,
        department: offer.department,
        appointmentDate: appointmentDate,
        timeSlot: offer.timeSlot,
        qrCode: result.qrCode,
        bookingReference: result.bookingReference,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      // A confirmed receipt must not wait for optional reminder preference reads.
      unawaited(NotificationSchedulingCoordinator()
          .scheduleLocalAppointmentReminders(appointment));
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BookingSuccessScreen(
          appointmentId: result.appointmentId,
          qrCode: result.qrCode,
          bookingReference: result.bookingReference,
          doctorName: offer.doctorName,
          date: appointmentDate,
          timeSlot: offer.timeSlot,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AssistantChatProvider>.value(
      value: _provider,
      child: Consumer<AssistantChatProvider>(
        builder: (context, provider, _) {
          final l10n = AppLocalizations.of(context);
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final isRtl = Directionality.of(context) == TextDirection.rtl;

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Scaffold(
              appBar: AppBar(
                title: Column(
                  crossAxisAlignment:
                      isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.assistantTitle,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      l10n.assistantClinicTimezone,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: l10n.assistantInfoTooltip,
                    icon: const Icon(Icons.info_outline),
                    onPressed: _showInfoSheet,
                  ),
                  IconButton(
                    tooltip: l10n.assistantClearChat,
                    icon: const Icon(Icons.delete_outline),
                    onPressed:
                        provider.messages.isNotEmpty ? _confirmClearChat : null,
                  ),
                ],
              ),
              body: ResponsivePage(
                padding: EdgeInsets.zero,
                scrollable: false,
                child: Column(
                  children: [
                    AssistantStatusBanner(
                      provider: provider,
                      onBookManually: _navigateToStandardBooking,
                    ),

                    // Chat Area
                    Expanded(
                      child: provider.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : provider.messages.isEmpty
                              ? _buildEmptyState(l10n, isDark)
                              : _buildMessagesList(provider, l10n, isDark),
                    ),

                    _buildReceiptRecovery(provider, l10n),

                    // Bottom Input Field & Booking Fallback Shortcut
                    _buildInputBar(provider, l10n, isDark),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, bool isDark) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if ((notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle) ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null)) {
          FocusScope.of(context).unfocus();
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.primary,
                  size: 38,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.assistantTitle,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.assistantSubtitle,
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Privacy and Help Disclaimer Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.grey.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.assistantInitialHelpPrompt,
                      style: GoogleFonts.roboto(
                        fontSize: 13,
                        height: 1.4,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.security,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.assistantPrivacyNotice,
                            style: GoogleFonts.roboto(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              // Fallback direct booking action
              OutlinedButton.icon(
                onPressed: _navigateToStandardBooking,
                icon: const Icon(Icons.calendar_month, size: 18),
                label: Text(l10n.bookAnAppointment),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList(
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if ((notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle) ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null)) {
          FocusScope.of(context).unfocus();
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView.builder(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: provider.messages.length,
          itemBuilder: (context, index) {
            final message = provider.messages[index];
            final offers = provider.getOffersForMessage(message);

            return Column(
              crossAxisAlignment: message.isPatient
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                _buildMessageBubble(message, isDark),
                if (offers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  AssistantOfferCards(
                      offers: offers,
                      provider: provider,
                      onSelected: _handleOfferSelection),
                ],
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessageBubble(AssistantChatMessage message, bool isDark) {
    final isPatient = message.isPatient;

    return Row(
      mainAxisAlignment:
          isPatient ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isPatient) ...[
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child:
                const Icon(Icons.smart_toy, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isPatient
                  ? AppColors.primary
                  : (isDark ? AppColors.surfaceDark : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isPatient ? 16 : 4),
                bottomRight: Radius.circular(isPatient ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
              border: !isPatient
                  ? Border.all(
                      color: isDark
                          ? Colors.white10
                          : Colors.grey.withValues(alpha: 0.15),
                    )
                  : null,
            ),
            child: Text(
              message.text,
              style: GoogleFonts.roboto(
                fontSize: 14,
                height: 1.35,
                color: isPatient
                    ? Colors.white
                    : (isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptRecovery(
    AssistantChatProvider provider,
    AppLocalizations l10n,
  ) {
    final pendingOffer = provider.pendingBookingOffer;
    if (pendingOffer == null ||
        provider.messages.any((message) => provider
            .getOffersForMessage(message)
            .any((offer) => offer.offerId == pendingOffer.offerId))) {
      return const SizedBox.shrink();
    }

    return ListTile(
      leading: const Icon(Icons.receipt_long, color: AppColors.warning),
      title: Text(pendingOffer.doctorName),
      subtitle: Text(pendingOffer.timeSlot),
      trailing: TextButton(
        onPressed: provider.canConfirmOffer(pendingOffer)
            ? () => _handleOfferSelection(pendingOffer)
            : null,
        child: Text(l10n.assistantRetrySending),
      ),
    );
  }

  Widget _buildInputBar(
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final isLimitReached = provider.isDailyLimit || provider.isDisabled;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        border: Border(
          top: BorderSide(
            color:
                isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick shortcut to standard booking
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: _navigateToStandardBooking,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.bookAnAppointment,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Character Counter (0 / 500)
              Text(
                '$_charCount/500',
                style: GoogleFonts.roboto(
                  fontSize: 10,
                  color: _charCount > 500
                      ? AppColors.error
                      : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: !provider.isSending && !isLimitReached,
                  maxLines: 4,
                  minLines: 1,
                  maxLength: 500,
                  buildCounter: (context,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null, // Hide default counter
                  decoration: InputDecoration(
                    hintText: provider.isDailyLimit
                        ? l10n.assistantDailyLimitHeading
                        : provider.isDisabled
                            ? l10n.assistantUnavailableNotice
                            : l10n.assistantInputPlaceholder,
                    hintStyle: GoogleFonts.roboto(fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: isDark
                            ? Colors.white10
                            : Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.withValues(alpha: 0.08),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: provider.isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: (provider.canSendMessage &&
                          _charCount > 0 &&
                          _charCount <= 500)
                      ? _handleSendMessage
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

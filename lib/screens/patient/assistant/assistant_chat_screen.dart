import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/localization_helper.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/models/assistant_chat_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/appointment_provider.dart';
import '../../../providers/assistant_chat_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../services/notification_scheduling_coordinator.dart';
import '../booking/booking_screen.dart';
import '../main_shell.dart';

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
    if (text.isEmpty || text.length > 500) return;

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
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 1)),
      (route) => false,
    );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.assistantChatCleared)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_provider.errorMessage ?? l10n.assistantClearChatFailed),
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
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isRetry = _provider.activeBookingOfferId == offer.offerId;
    if (!isRetry && !offer.isBookable(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.assistantStaleOffer),
          backgroundColor: AppColors.warning,
        ),
      );
      await _provider.refreshHistory();
      return;
    }

    final modalOpeningUserId = context.read<AuthProvider>().currentUser?.id;

    // Explicit affirmative confirmation modal
    final notesController = TextEditingController();
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            l10n.assistantSelectedSlot,
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n.assistantClinicTimezone,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Doctor and department card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppColors.primary,
                                child: Text(
                                  offer.doctorName.isNotEmpty
                                      ? offer.doctorName[0].toUpperCase()
                                      : 'D',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      offer.doctorName,
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      LocalizationHelper.translateDepartment(
                                        offer.departmentName ?? offer.department,
                                        l10n,
                                      ),
                                      style: GoogleFonts.roboto(
                                        fontSize: 13,
                                        color: isDark
                                            ? AppColors.textSecondaryDark
                                            : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      size: 16,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _formatDate(offer.appointmentDate, context),
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.access_time,
                                      size: 16,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        offer.timeSlot,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    // Notice banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 18,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.assistantSlotsNotReserved,
                              style: GoogleFonts.roboto(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    // Optional Notes Field
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: l10n.assistantNotesOptional,
                        hintText: l10n.assistantNotesOptional,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(modalCtx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    setModalState(() => isSubmitting = true);
                                    final result = await _provider.confirmOffer(
                                      offer,
                                      notes: notesController.text.trim(),
                                    );

                                    final currentUserId = mounted
                                        ? context.read<AuthProvider>().currentUser?.id
                                        : null;
                                    if (currentUserId != modalOpeningUserId || currentUserId == null) {
                                      if (modalCtx.mounted) {
                                        Navigator.pop(modalCtx);
                                      }
                                      return;
                                    }

                                    if (result != null && result.success && result.isValid) {
                                      if (modalCtx.mounted) {
                                        Navigator.pop(modalCtx);
                                      }
                                      if (mounted) {
                                        await _onBookingSuccess(offer, result);
                                      }
                                    } else {
                                      if (modalCtx.mounted) {
                                        setModalState(() => isSubmitting = false);
                                      }
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              _provider.errorMessage ??
                                                  l10n.bookingFailed,
                                            ),
                                            backgroundColor: AppColors.error,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(l10n.assistantConfirmAppointment),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _onBookingSuccess(
    AssistantOffer offer,
    ConfirmAssistantAppointmentResult result,
  ) async {
    final user = context.read<AuthProvider>().currentUser;
    final appointmentDate =
        offer.parsedAppointmentDate ?? DateTime.now();

    // 1. Trigger secondary refresh tasks with non-fatal try-catch
    try {
      if (user != null) {
        final apptProvider = context.read<AppointmentProvider>();
        await apptProvider.loadAppointments(user.id, email: user.email);

        final authoritativeAppt = apptProvider.upcomingAppointments
            .where((a) => a.id == result.appointmentId)
            .firstOrNull ??
            apptProvider.pastAppointments
                .where((a) => a.id == result.appointmentId)
                .firstOrNull;

        final targetAppt = authoritativeAppt ??
            AppointmentModel(
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

        final coordinator = NotificationSchedulingCoordinator();
        await coordinator.scheduleLocalAppointmentReminders(targetAppt);
      }
    } catch (e) {
      debugPrint('Secondary post-booking tasks failed (non-fatal): $e');
    }

    if (!mounted) return;

    // 2. Navigate to BookingSuccessScreen
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

  String _formatDate(String yyyyMmDd, BuildContext context) {
    try {
      final date = DateTime.parse(yyyyMmDd);
      final locale = Localizations.localeOf(context).languageCode;
      return intl.DateFormat.yMMMMEEEEd(locale).format(date);
    } catch (_) {
      return yyyyMmDd;
    }
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
                    onPressed: provider.messages.isNotEmpty
                        ? _confirmClearChat
                        : null,
                  ),
                ],
              ),
              body: ResponsivePage(
                padding: EdgeInsets.zero,
                scrollable: false,
                child: Column(
                  children: [
                    // Quota / Policy / Outage / Generic Error Banners
                    if (provider.isDailyLimit)
                      _buildDailyLimitBanner(provider, l10n, isDark),
                    if (provider.isDisabled)
                      _buildDisabledBanner(provider, l10n, isDark),
                    if (provider.isUnavailable)
                      _buildUnavailableBanner(provider, l10n, isDark),
                    if (provider.isThrottled)
                      _buildThrottledBanner(provider, l10n, isDark),
                    if (provider.errorMessage != null &&
                        !provider.isDailyLimit &&
                        !provider.isDisabled &&
                        !provider.isUnavailable &&
                        !provider.isThrottled)
                      _buildGenericErrorBanner(provider, l10n, isDark),

                    // Chat Area
                    Expanded(
                      child: provider.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : provider.messages.isEmpty
                              ? _buildEmptyState(l10n, isDark)
                              : _buildMessagesList(provider, l10n, isDark),
                    ),

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

  Widget _buildDailyLimitBanner(
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    String resetText = '';
    if (provider.resetAt != null) {
      final localReset = provider.resetAt!.toLocal();
      final formattedTime = intl.DateFormat('h:mm a, MMM d').format(localReset);
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
              const Icon(Icons.hourglass_empty, color: AppColors.warning, size: 20),
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
              onPressed: _navigateToStandardBooking,
              icon: const Icon(Icons.calendar_month, size: 16),
              label: Text(l10n.bookAnAppointment),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                  l10n.assistantDisabledNotice,
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _navigateToStandardBooking,
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
            onPressed: _navigateToStandardBooking,
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

  String _getLocalizedError(String rawError, String? reasonCode, AppLocalizations l10n) {
    final lower = rawError.toLowerCase();
    final reason = (reasonCode ?? '').toLowerCase();
    final normError = lower.replaceAll('_', '-');
    final normReason = reason.replaceAll('_', '-');

    if (lower == 'assistanthistoryloadfailed' || reason == 'history_load_failed') {
      return l10n.assistantHistoryLoadFailed;
    }
    if (normError.contains('unauthenticated') || normReason.contains('unauthenticated')) {
      return l10n.assistantErrorUnauthenticated;
    }
    if (normError.contains('permission-denied') || normReason.contains('permission-denied')) {
      return l10n.assistantErrorPermissionDenied;
    }
    if (normError.contains('not-found') || normReason.contains('not-found')) {
      return l10n.assistantErrorNotFound;
    }
    if (reason.contains('daily_limit') || lower.contains('daily_limit') || reason == 'upstream_daily_limit_reached') {
      return l10n.assistantDailyLimitHeading;
    }
    if (reason.contains('throttled') ||
        lower.contains('throttled') ||
        reason == 'upstream_throttled' ||
        lower.contains('turn is already in progress') ||
        lower.contains('already in progress')) {
      return l10n.assistantThrottledNotice;
    }
    if (reason.contains('disabled') || lower.contains('disabled')) {
      return l10n.assistantDisabledNotice;
    }
    if (reason.contains('unavailable') ||
        lower.contains('unavailable') ||
        reason == 'upstream_unavailable' ||
        reason.contains('deadline') ||
        lower.contains('deadline') ||
        reason.contains('timeout') ||
        lower.contains('timeout') ||
        reason.contains('internal') ||
        lower.contains('internal') ||
        normError.contains('failed-precondition') ||
        lower.contains('unexpected error') ||
        lower.contains('failed to send message')) {
      return l10n.assistantUnavailableNotice;
    }
    return rawError;
  }

  Widget _buildGenericErrorBanner(
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final localizedMsg = _getLocalizedError(
      provider.errorMessage!,
      provider.reasonCode,
      l10n,
    );

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
          if (provider.reasonCode == 'history_load_failed')
            TextButton(
              onPressed: () => provider.refreshHistory(force: true),
              child: Text(l10n.assistantRetrySending),
            ),
        ],
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
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                  _buildOffersSection(offers, provider, l10n, isDark),
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
            child: const Icon(Icons.smart_toy, size: 16, color: AppColors.primary),
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

  Widget _buildOffersSection(
    List<AssistantOffer> offers,
    AssistantChatProvider provider,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: offers.map((offer) {
        final now = DateTime.now();
        final isPendingRetry = provider.activeBookingOfferId == offer.offerId;
        final isBookable = offer.isBookable(now);
        final isExpired = offer.isExpired(now);
        final minutesLeft = offer.expiresAt.difference(now.toUtc()).inMinutes;

        final isBusy = provider.isRefreshing ||
            provider.isRefreshPending ||
            provider.isLoading ||
            provider.isClearing ||
            provider.isConfirming;
        final canClick = (isBookable || isPendingRetry) && !isBusy;

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
                    _formatDate(offer.appointmentDate, context),
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
                  onPressed: canClick
                      ? () => _handleOfferSelection(offer)
                      : null,
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
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
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
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
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
                    hintText: isLimitReached
                        ? l10n.assistantDailyLimitHeading
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
                  onPressed: (!provider.isSending &&
                          !isLimitReached &&
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

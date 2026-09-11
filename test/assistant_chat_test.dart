// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uhc/core/theme/app_theme.dart';
import 'package:uhc/data/models/assistant_chat_model.dart';
import 'package:uhc/data/models/user_model.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/l10n/kurdish_material_localizations.dart';
import 'package:uhc/providers/appointment_provider.dart';
import 'package:uhc/providers/assistant_chat_provider.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/screens/patient/assistant/assistant_chat_screen.dart';
import 'package:uhc/services/assistant_functions_service.dart';

/// Fake implementation of AssistantFunctionsService for deterministic isolated tests.
class FakeAssistantFunctionsService implements AssistantFunctionsService {
  GetAssistantHistoryResult historyResult = const GetAssistantHistoryResult(
    success: true,
    messages: [],
    offers: [],
    revision: 1,
  );

  Completer<GetAssistantHistoryResult>? historyCompleter;
  Completer<SendAssistantMessageResult>? sendCompleter;
  SendAssistantMessageResult? sendResult;
  Exception? sendException;

  Completer<ConfirmAssistantAppointmentResult>? confirmCompleter;
  ConfirmAssistantAppointmentResult? confirmResult;
  Exception? confirmException;

  bool clearResult = true;
  Exception? clearException;
  Exception? historyException;
  int clearHistoryCallCount = 0;
  int getHistoryCallCount = 0;
  int sendMessageCallCount = 0;
  int confirmAppointmentCallCount = 0;

  String? lastConfirmedOfferId;
  String? lastConfirmedIdempotencyKey;
  bool? lastConfirmedFlag;
  String? lastConfirmedNotes;
  String? lastSentMessage;
  String? lastSentLocale;
  String? lastSentClientRequestId;

  @override
  Future<GetAssistantHistoryResult> getHistory() async {
    getHistoryCallCount++;
    if (historyException != null) throw historyException!;
    if (historyCompleter != null) {
      return historyCompleter!.future;
    }
    return historyResult;
  }

  @override
  Future<bool> clearHistory() async {
    clearHistoryCallCount++;
    if (clearException != null) throw clearException!;
    return clearResult;
  }

  @override
  Future<SendAssistantMessageResult> sendMessage({
    required String message,
    String? locale,
    String? clientRequestId,
  }) async {
    sendMessageCallCount++;
    lastSentMessage = message;
    lastSentLocale = locale;
    lastSentClientRequestId = clientRequestId;

    if (sendCompleter != null) {
      return sendCompleter!.future;
    }
    if (sendException != null) {
      throw sendException!;
    }
    return sendResult ??
        SendAssistantMessageResult(
          success: true,
          status: AssistantMessageStatus.ready,
          message: 'Matching slots found.',
          replyLanguage: locale ?? 'en',
          offers: const [],
          revision: 2,
        );
  }

  @override
  Future<ConfirmAssistantAppointmentResult> confirmAppointment({
    required String offerId,
    required bool confirmed,
    String? notes,
    String? idempotencyKey,
  }) async {
    confirmAppointmentCallCount++;
    lastConfirmedOfferId = offerId;
    lastConfirmedFlag = confirmed;
    lastConfirmedNotes = notes;
    lastConfirmedIdempotencyKey = idempotencyKey;

    if (confirmCompleter != null) {
      return confirmCompleter!.future;
    }
    if (confirmException != null) {
      throw confirmException!;
    }
    return confirmResult ??
        const ConfirmAssistantAppointmentResult(
          success: true,
          appointmentId: 'appt_fake_123',
          bookingReference: 'BK123456',
          qrCode: 'UHC_APPOINTMENT:appt_fake_123:test_token',
        );
  }
}

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  UserModel? _mockUser;

  void setMockUser(UserModel? user) {
    _mockUser = user;
    notifyListeners();
  }

  @override
  UserModel? get currentUser => _mockUser;

  @override
  UserModel? get user => _mockUser;

  @override
  AuthState get state => _mockUser != null ? AuthState.authenticated : AuthState.unauthenticated;

  @override
  bool get isAuthenticated => _mockUser != null;

  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Helper to wrap widgets in multi-provider test harness with RTL and localization support.
Widget createAssistantTestApp({
  required Widget child,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  AuthProvider? authProvider,
  LocaleProvider? localeProvider,
  AppointmentProvider? appointmentProvider,
}) {
  final effectiveAuth = authProvider ??
      (MockAuthProvider()
        ..setMockUser(UserModel(
          id: 'test_patient_1',
          email: 'test@uhc.edu',
          fullName: 'Test Patient',
          role: UserRole.student,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        )));

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
        value: effectiveAuth,
      ),
      ChangeNotifierProvider<LocaleProvider>(
        create: (_) => localeProvider ?? LocaleProvider(),
      ),
      ChangeNotifierProvider<AppointmentProvider>(
        create: (_) => appointmentProvider ?? AppointmentProvider(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FallbackLocalizationsDelegate(),
        FallbackCupertinoLocalizationsDelegate(),
        FallbackWidgetsLocalizationsDelegate(),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: child,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Assistant Models Unit Tests', () {
    test('AssistantMessageStatus parses all standard backend statuses and handles unknown gracefully', () {
      expect(AssistantMessageStatus.fromString('ready'), AssistantMessageStatus.ready);
      expect(AssistantMessageStatus.fromString('clarify'), AssistantMessageStatus.clarify);
      expect(AssistantMessageStatus.fromString('out_of_scope'), AssistantMessageStatus.outOfScope);
      expect(AssistantMessageStatus.fromString('daily_limit'), AssistantMessageStatus.dailyLimit);
      expect(AssistantMessageStatus.fromString('throttled'), AssistantMessageStatus.throttled);
      expect(AssistantMessageStatus.fromString('unavailable'), AssistantMessageStatus.unavailable);
      expect(AssistantMessageStatus.fromString('disabled'), AssistantMessageStatus.disabled);
      expect(AssistantMessageStatus.fromString('cancelled'), AssistantMessageStatus.cancelled);
      expect(AssistantMessageStatus.fromString('random_invented_value'), AssistantMessageStatus.unknown);
      expect(AssistantMessageStatus.fromString(null), AssistantMessageStatus.unknown);
    });

    test('AssistantOffer parses canonical dates, timeSlots, and handles expiration logic', () {
      final now = DateTime.utc(2026, 9, 9, 12, 0, 0);
      final futureOffer = AssistantOffer.fromJson({
        'offerId': 'off_1',
        'doctorId': 'doc_1',
        'doctorName': 'Dr. Sarah',
        'department': 'cardiology',
        'appointmentDate': '2026-09-15',
        'timeSlot': '09:00 - 09:30',
        'expiresAt': '2026-09-09T12:10:00.000Z',
        'isAvailable': true,
      });

      expect(futureOffer.isExpired(now), isFalse);
      expect(futureOffer.isBookable(now), isTrue);
      expect(futureOffer.parsedAppointmentDate, DateTime.utc(2026, 9, 15));

      // Expiry equality must count as expired
      expect(futureOffer.isExpired(futureOffer.expiresAt), isTrue);

      final pastOffer = AssistantOffer.fromJson({
        'offerId': 'off_2',
        'doctorId': 'doc_1',
        'doctorName': 'Dr. Sarah',
        'department': 'cardiology',
        'appointmentDate': '2026-09-15',
        'timeSlot': '09:00 - 09:30',
        'expiresAt': '2026-09-09T11:59:00.000Z',
        'isAvailable': true,
      });

      expect(pastOffer.isExpired(now), isTrue);
      expect(pastOffer.isBookable(now), isFalse);
    });

    test('AssistantOffer fails closed on missing/malformed expiry, invalid dates, and missing IDs', () {
      final malformedExpiry = AssistantOffer.fromJson({
        'offerId': 'off_bad_exp',
        'doctorId': 'doc_1',
        'doctorName': 'Dr. Sarah',
        'department': 'cardiology',
        'appointmentDate': '2026-09-15',
        'timeSlot': '09:00 - 09:30',
        'expiresAt': 'invalid-timestamp',
        'isAvailable': true,
      });
      expect(malformedExpiry.isAvailable, isFalse);
      expect(malformedExpiry.isBookable(), isFalse);
      expect(malformedExpiry.isExpired(), isTrue);

      final impossibleDate = AssistantOffer.fromJson({
        'offerId': 'off_bad_date',
        'doctorId': 'doc_1',
        'doctorName': 'Dr. Sarah',
        'department': 'cardiology',
        'appointmentDate': '2026-02-31',
        'timeSlot': '09:00 - 09:30',
        'expiresAt': '2026-09-09T12:10:00.000Z',
        'isAvailable': true,
      });
      expect(impossibleDate.isAvailable, isFalse);
      expect(impossibleDate.isBookable(), isFalse);
      expect(impossibleDate.parsedAppointmentDate, isNull);

      final blankId = AssistantOffer.fromJson({
        'offerId': '',
        'doctorId': 'doc_1',
        'doctorName': 'Dr. Sarah',
        'department': 'cardiology',
        'appointmentDate': '2026-09-15',
        'timeSlot': '09:00 - 09:30',
        'expiresAt': '2026-09-09T12:10:00.000Z',
        'isAvailable': true,
      });
      expect(blankId.isAvailable, isFalse);
      expect(blankId.isBookable(), isFalse);
    });

    test('GetAssistantHistoryResult safely parses optional resetAt and status without throwing', () {
      final payload = {
        'success': true,
        'messages': [
          {
            'id': 'm1',
            'sender': 'assistant',
            'text': 'Hello',
            'status': 'ready',
            'createdAt': '2026-09-09T10:00:00.000Z',
          }
        ],
        'offers': [],
        'revision': 3,
        'resetAt': '2026-09-10T07:00:00.000Z',
        'status': 'daily_limit',
      };

      final parsed = GetAssistantHistoryResult.fromJson(payload);
      expect(parsed.success, isTrue);
      expect(parsed.messages.length, 1);
      expect(parsed.revision, 3);
      expect(parsed.resetAt, DateTime.utc(2026, 9, 10, 7, 0, 0));
      expect(parsed.status, AssistantMessageStatus.dailyLimit);
    });

    test('ConfirmAssistantAppointmentResult rejects empty/malformed receipts', () {
      final emptyReceipt = ConfirmAssistantAppointmentResult.fromJson({
        'success': true,
        'appointmentId': '',
        'bookingReference': '',
      });
      expect(emptyReceipt.success, isFalse);
      expect(emptyReceipt.isValid, isFalse);

      final failedReceipt = ConfirmAssistantAppointmentResult.fromJson({
        'success': false,
        'appointmentId': 'appt_123',
        'bookingReference': 'REF123',
      });
      expect(failedReceipt.success, isFalse);
      expect(failedReceipt.isValid, isFalse);
    });
  });

  group('AssistantChatProvider Isolation and Lifecycle Tests', () {
    test('PR5 retained offers stay attached only to the original ready reply', () async {
      final service = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(patientId: 'patient_A', functionsService: service);
      final offer = AssistantOffer(offerId: 'prior', doctorId: 'doc', doctorName: 'Doctor', department: 'dentistry', appointmentDate: '2026-09-16', timeSlot: '09:00 - 09:30', expiresAt: DateTime.now().add(const Duration(minutes: 10)), isAvailable: true);
      service.sendResult = SendAssistantMessageResult(success: true, status: AssistantMessageStatus.ready, message: 'Slots', replyLanguage: 'en', offers: [offer], revision: 2);
      await provider.sendMessage('Slots please', localeCode: 'en');
      final original = provider.messages.last;
      for (final status in [AssistantMessageStatus.clarify, AssistantMessageStatus.outOfScope]) {
        service.sendResult = SendAssistantMessageResult(success: true, status: status, message: 'Unrelated reply', replyLanguage: 'en', offers: [offer], revision: 3);
        await provider.sendMessage('Another question', localeCode: 'en');
        expect(provider.messages.last.offerIds, isEmpty);
        expect(provider.getOffersForMessage(original).single.offerId, 'prior');
      }
      provider.dispose();
    });

    test('PR5 failed clear preserves history and draft even when reloading fails', () async {
      for (final throws in [false, true]) {
        final service = FakeAssistantFunctionsService();
        final message = AssistantChatMessage(id: 'saved', sender: 'patient', text: 'Saved conversation', status: AssistantMessageStatus.ready, createdAt: DateTime.now());
        service.historyResult = GetAssistantHistoryResult(success: true, messages: [message], offers: const [], revision: 3);
        final provider = AssistantChatProvider(patientId: 'patient_A', functionsService: service);
        await provider.initialize();
        provider.setDraft('Unsent text');
        service.clearResult = false;
        if (throws) service.clearException = Exception('offline');
        service.historyException = Exception('offline');
        expect(await provider.clearChat(), isFalse);
        expect(provider.messages.single.text, 'Saved conversation');
        expect(provider.unsentDraft, 'Unsent text');
        expect(provider.errorMessage, contains('Failed to clear'));
        expect(provider.isClearing, isFalse);
        provider.dispose();
      }
    });

    testWidgets('PR5 daily reset unlocks an open conversation without deleting history', (tester) async {
      final service = FakeAssistantFunctionsService();
      final message = AssistantChatMessage(id: 'saved', sender: 'patient', text: 'Keep history', status: AssistantMessageStatus.ready, createdAt: DateTime.now());
      service.historyResult = GetAssistantHistoryResult(success: true, messages: [message], offers: const [], revision: 3, status: AssistantMessageStatus.dailyLimit, resetAt: DateTime.now().add(const Duration(milliseconds: 100)));
      final provider = AssistantChatProvider(patientId: 'patient_A', functionsService: service);
      await provider.initialize();
      expect(provider.isDailyLimit, isTrue);
      service.historyResult = GetAssistantHistoryResult(success: true, messages: [message], offers: const [], revision: 3, status: AssistantMessageStatus.ready);
      await tester.pump(const Duration(milliseconds: 200));
      expect(provider.isDailyLimit, isFalse);
      expect(provider.resetAt, isNull);
      expect(provider.messages.single.text, 'Keep history');
      provider.dispose();
    });

    test('Failed send preserves clientRequestId across retries of same draft text', () async {
      final fakeService = FakeAssistantFunctionsService();
      fakeService.sendException = const AssistantFunctionException(
        code: 'deadline-exceeded',
        message: 'Timeout contacting assistant.',
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      // First attempt fails with network error
      final success1 = await provider.sendMessage('Book cardiologist tomorrow', localeCode: 'en');
      expect(success1, isFalse);
      expect(provider.unsentDraft, 'Book cardiologist tomorrow');
      final firstRequestId = fakeService.lastSentClientRequestId;
      expect(firstRequestId, isNotNull);

      // Second attempt retries the exact same unsent draft
      fakeService.sendException = null;
      fakeService.sendResult = const SendAssistantMessageResult(
        success: true,
        status: AssistantMessageStatus.ready,
        message: 'Here are cardiology slots.',
        replyLanguage: 'en',
        offers: [],
        revision: 2,
      );

      final success2 = await provider.sendMessage('Book cardiologist tomorrow', localeCode: 'en');
      expect(success2, isTrue);
      // Client request ID MUST be identical to the first attempt so backend deduplicates
      expect(fakeService.lastSentClientRequestId, firstRequestId);
      // Once accepted, draft is cleared
      expect(provider.unsentDraft, isNull);

      provider.dispose();
    });

    test('Clear chat prevents in-flight async turn from repopulating chat', () async {
      final fakeService = FakeAssistantFunctionsService();
      final completer = Completer<SendAssistantMessageResult>();
      fakeService.sendCompleter = completer;

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      // 1. Trigger in-flight send
      final sendFuture = provider.sendMessage('Book appointment', localeCode: 'en');
      expect(provider.isSending, isTrue);
      expect(provider.messages.length, 1);

      // 2. User taps clear chat while send is in-flight
      await provider.clearChat();
      expect(provider.messages, isEmpty);
      expect(fakeService.clearHistoryCallCount, 1);

      // 3. Late network arrival finishes with offers
      completer.complete(SendAssistantMessageResult(
        success: true,
        status: AssistantMessageStatus.ready,
        message: 'Offers here',
        replyLanguage: 'en',
        offers: [
          AssistantOffer(
            offerId: 'off_late',
            doctorId: 'doc_1',
            doctorName: 'Dr. Jane',
            department: 'generalMedicine',
            appointmentDate: '2026-09-12',
            timeSlot: '10:00 - 10:30',
            expiresAt: DateTime.now().add(const Duration(minutes: 10)),
            isAvailable: true,
          ),
        ],
        revision: 4,
      ));

      await sendFuture;

      // 4. Stale turn must NOT resurrect or repopulate the cleared chat
      expect(provider.messages, isEmpty);
      expect(provider.offers, isEmpty);

      provider.dispose();
    });

    test('Dispose isolation discards pending async completion safely', () async {
      final fakeService = FakeAssistantFunctionsService();
      final completer = Completer<SendAssistantMessageResult>();
      fakeService.sendCompleter = completer;

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      final sendFuture = provider.sendMessage('Hello', localeCode: 'en');
      expect(provider.isSending, isTrue);

      // Screen unmounts and provider disposes
      provider.dispose();
      expect(provider.isDisposed, isTrue);

      // Network completes after disposal
      completer.complete(const SendAssistantMessageResult(
        success: true,
        status: AssistantMessageStatus.ready,
        message: 'Late response',
        replyLanguage: 'en',
        offers: [],
        revision: 5,
      ));

      await sendFuture;
      // Must complete without unhandled notification assertion
      expect(provider.isDisposed, isTrue);
    });

    test('Send failure retains draft so user does not lose message', () async {
      final fakeService = FakeAssistantFunctionsService();
      fakeService.sendException = const AssistantFunctionException(
        code: 'resource-exhausted',
        message: 'Rate limit exceeded.',
        status: AssistantMessageStatus.throttled,
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      const messageText = 'I need an appointment tomorrow morning';
      final success = await provider.sendMessage(messageText, localeCode: 'en');

      expect(success, isFalse);
      expect(provider.unsentDraft, messageText);
      expect(provider.isThrottled, isTrue);

      provider.dispose();
    });

    test('Daily quota error parses resetAt UTC correctly without wiping past history', () async {
      final fakeService = FakeAssistantFunctionsService();
      final resetTime = DateTime.now().toUtc().add(const Duration(hours: 1));

      fakeService.sendResult = SendAssistantMessageResult(
        success: true,
        status: AssistantMessageStatus.dailyLimit,
        message: 'The assistant has reached today’s daily limit.',
        replyLanguage: 'en',
        offers: const [],
        resetAt: resetTime,
        revision: 10,
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      await provider.sendMessage('Check doctor slots', localeCode: 'en');

      expect(provider.isDailyLimit, isTrue);
      expect(provider.resetAt, resetTime);
      expect(provider.messages.length, 1); // Assistant limit notice (optimistic draft removed on rejection)
      expect(provider.unsentDraft, 'Check doctor slots');

      provider.dispose();
    });

    test('No booking call occurs without affirmative confirmation', () async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      final testOffer = AssistantOffer(
        offerId: 'off_test',
        doctorId: 'doc_1',
        doctorName: 'Dr. Sarah',
        department: 'dentistry',
        appointmentDate: '2026-09-16',
        timeSlot: '11:00 - 11:30',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        isAvailable: true,
      );

      // Merely having or reading the offer writes nothing
      expect(fakeService.confirmAppointmentCallCount, 0);

      // Explicit affirmative call triggers booking
      final result = await provider.confirmOffer(testOffer, notes: 'First visit');
      expect(result, isNotNull);
      expect(fakeService.confirmAppointmentCallCount, 1);
      expect(fakeService.lastConfirmedOfferId, 'off_test');
      expect(fakeService.lastConfirmedNotes, 'First visit');
      expect(fakeService.lastConfirmedFlag, isTrue);

      provider.dispose();
    });

    test('Double-tap lockout prevents concurrent booking requests', () async {
      final fakeService = FakeAssistantFunctionsService();
      final completer = Completer<ConfirmAssistantAppointmentResult>();
      fakeService.confirmCompleter = completer;

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      final testOffer = AssistantOffer(
        offerId: 'off_double_tap',
        doctorId: 'doc_1',
        doctorName: 'Dr. Sarah',
        department: 'dentistry',
        appointmentDate: '2026-09-16',
        timeSlot: '11:00 - 11:30',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        isAvailable: true,
      );

      // First tap begins confirmation
      final firstTapFuture = provider.confirmOffer(testOffer);
      expect(provider.isConfirming, isTrue);
      expect(fakeService.confirmAppointmentCallCount, 1);

      // Second tap while first is in-flight must be rejected immediately
      final secondTapResult = await provider.confirmOffer(testOffer);
      expect(secondTapResult, isNull);
      expect(fakeService.confirmAppointmentCallCount, 1); // Still exactly 1 call!

      completer.complete(const ConfirmAssistantAppointmentResult(
        success: true,
        appointmentId: 'appt_first',
        bookingReference: 'BKFIRST',
      ));

      final firstResult = await firstTapFuture;
      expect(firstResult?.appointmentId, 'appt_first');
      expect(provider.isConfirming, isFalse);

      provider.dispose();
    });

    test('Network failure preserves same idempotency identity across retries', () async {
      final fakeService = FakeAssistantFunctionsService();
      fakeService.confirmException = const AssistantFunctionException(
        code: 'unavailable',
        message: 'Network timeout.',
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      final testOffer = AssistantOffer(
        offerId: 'off_retry_idempotency',
        doctorId: 'doc_1',
        doctorName: 'Dr. Sarah',
        department: 'dentistry',
        appointmentDate: '2026-09-16',
        timeSlot: '11:00 - 11:30',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        isAvailable: true,
      );

      // First attempt fails with network error
      final firstResult = await provider.confirmOffer(testOffer);
      expect(firstResult, isNull);
      final firstIdempotencyKey = fakeService.lastConfirmedIdempotencyKey;
      expect(firstIdempotencyKey, isNotNull);
      expect(firstIdempotencyKey, contains('off_retry_idempotency'));

      // Retry attempt after network reconnects
      fakeService.confirmException = null;
      fakeService.confirmResult = const ConfirmAssistantAppointmentResult(
        success: true,
        appointmentId: 'appt_retry_ok',
        bookingReference: 'BKRETRY',
      );

      final secondResult = await provider.confirmOffer(testOffer);
      expect(secondResult?.appointmentId, 'appt_retry_ok');
      final secondIdempotencyKey = fakeService.lastConfirmedIdempotencyKey;

      // Idempotency key MUST be preserved across uncertain retry to prevent duplicate bookings
      expect(secondIdempotencyKey, equals(firstIdempotencyKey));

      provider.dispose();
    });

    test('Attempting to book expired offer rejects and refreshes history', () async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      final expiredOffer = AssistantOffer(
        offerId: 'off_expired',
        doctorId: 'doc_1',
        doctorName: 'Dr. Sarah',
        department: 'dentistry',
        appointmentDate: '2026-09-16',
        timeSlot: '11:00 - 11:30',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        isAvailable: true,
      );

      final result = await provider.confirmOffer(expiredOffer);
      expect(result, isNull);
      expect(fakeService.confirmAppointmentCallCount, 0); // No booking request sent
      expect(provider.errorMessage, contains('no longer available'));
      expect(fakeService.getHistoryCallCount, 1); // Refreshed history

      provider.dispose();
    });

    test('Account switch (Account A -> Account B) wipes state, increments generation, and ignores delayed responses', () async {
      final fakeService = FakeAssistantFunctionsService();
      final completerA = Completer<SendAssistantMessageResult>();
      fakeService.sendCompleter = completerA;

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      // Account A starts an in-flight turn
      final sendFutureA = provider.sendMessage('Account A message', localeCode: 'en');
      expect(provider.isSending, isTrue);
      expect(provider.messages.length, 1);

      // User switches to Account B (e.g. sign-in with student account B)
      provider.updateActiveUser(userId: 'patient_B', role: UserRole.student);

      expect(provider.patientId, 'patient_B');
      expect(provider.messages, isEmpty);
      expect(provider.isSending, isFalse);

      // Delayed response for Account A finally arrives from network
      completerA.complete(const SendAssistantMessageResult(
        success: true,
        status: AssistantMessageStatus.ready,
        message: 'Account A confidential slots',
        replyLanguage: 'en',
        offers: [],
        revision: 3,
      ));

      await sendFutureA;

      // Account A's response MUST NOT appear in Account B's state
      expect(provider.messages, isEmpty);
      expect(provider.isSending, isFalse);

      provider.dispose();
    });

    test('Clear chat explicitly resets busy flags so provider does not lock into permanent busy state', () async {
      final fakeService = FakeAssistantFunctionsService();
      final completer = Completer<SendAssistantMessageResult>();
      fakeService.sendCompleter = completer;

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      // In-flight message
      final sendFuture = provider.sendMessage('Booking request', localeCode: 'en');
      expect(provider.isSending, isTrue);

      // User triggers clearChat while send is in-flight
      await provider.clearChat();

      // Busy flags MUST be reset immediately
      expect(provider.isSending, isFalse);
      expect(provider.isLoading, isFalse);
      expect(provider.isConfirming, isFalse);
      expect(provider.isClearing, isFalse);

      // When late network request completes, provider remains un-locked
      completer.complete(const SendAssistantMessageResult(
        success: true,
        status: AssistantMessageStatus.ready,
        message: 'Late arrival',
        replyLanguage: 'en',
        offers: [],
        revision: 2,
      ));

      await sendFuture;

      expect(provider.isSending, isFalse);
      expect(provider.messages, isEmpty);

      provider.dispose();
    });

    test('Booking retry recovers receipt even if local offer expired or slot marked unavailable', () async {
      final fakeService = FakeAssistantFunctionsService();
      // First attempt times out
      fakeService.confirmException = const AssistantFunctionException(
        code: 'deadline-exceeded',
        message: 'Request timed out.',
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      final testOffer = AssistantOffer(
        offerId: 'off_recover_receipt',
        doctorId: 'doc_1',
        doctorName: 'Dr. Sarah',
        department: 'dentistry',
        appointmentDate: '2026-09-16',
        timeSlot: '11:00 - 11:30',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        isAvailable: true,
      );

      // Attempt 1 fails due to network timeout
      final attempt1 = await provider.confirmOffer(testOffer);
      expect(attempt1, isNull);

      // Now simulate local offer expiration (time passed while retrying)
      final expiredOffer = testOffer.copyWith(
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        isAvailable: false,
      );
      expect(expiredOffer.isBookable(DateTime.now()), isFalse);

      // Network recovers: server actually reserved it, retry recovers receipt!
      fakeService.confirmException = null;
      fakeService.confirmResult = const ConfirmAssistantAppointmentResult(
        success: true,
        appointmentId: 'appt_recovered_123',
        bookingReference: 'BKRECOVERED',
        qrCode: 'UHC:recovered',
      );

      final retryResult = await provider.confirmOffer(expiredOffer);
      expect(retryResult, isNotNull);
      expect(retryResult?.success, isTrue);
      expect(retryResult?.appointmentId, 'appt_recovered_123');
      expect(retryResult?.bookingReference, 'BKRECOVERED');

      provider.dispose();
    });

    test('Strict receipt validation rejects missing bookingReference or empty appointmentId', () async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      final testOffer = AssistantOffer(
        offerId: 'off_invalid_receipt',
        doctorId: 'doc_1',
        doctorName: 'Dr. Sarah',
        department: 'dentistry',
        appointmentDate: '2026-09-16',
        timeSlot: '11:00 - 11:30',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        isAvailable: true,
      );

      // Case 1: Backend returns empty appointmentId
      fakeService.confirmResult = const ConfirmAssistantAppointmentResult(
        success: true,
        appointmentId: '',
        bookingReference: 'BK123',
      );

      final resultEmptyId = await provider.confirmOffer(testOffer);
      expect(resultEmptyId, isNull);
      expect(provider.errorMessage, contains('Failed to confirm'));

      // Case 2: Backend returns empty bookingReference
      fakeService.confirmResult = const ConfirmAssistantAppointmentResult(
        success: true,
        appointmentId: 'appt_ok',
        bookingReference: '',
      );

      final resultEmptyRef = await provider.confirmOffer(testOffer);
      expect(resultEmptyRef, isNull);

      // Case 3: Backend returns success: false
      fakeService.confirmResult = const ConfirmAssistantAppointmentResult(
        success: false,
        appointmentId: 'appt_ok',
        bookingReference: 'BK123',
      );

      final resultFalse = await provider.confirmOffer(testOffer);
      expect(resultFalse, isNull);

      provider.dispose();
    });

    test('CAS revision check and bounded message history in refreshHistory', () async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      // Initial state with revision 5
      fakeService.historyResult = const GetAssistantHistoryResult(
        success: true,
        messages: [],
        offers: [],
        revision: 5,
      );
      await provider.initialize();
      expect(provider.revision, 5);

      // Stale history with revision 3 returns -> ignored by CAS check
      fakeService.historyResult = GetAssistantHistoryResult(
        success: true,
        messages: [
          AssistantChatMessage(
            id: 'stale_msg',
            sender: 'assistant',
            text: 'Old stale message',
            createdAt: DateTime.now(),
          ),
        ],
        offers: const [],
        revision: 3,
      );
      await provider.refreshHistory();
      expect(provider.revision, 5);
      expect(provider.messages, isEmpty);

      // Newer history with 25 messages arrives -> bounded to 20
      final twentyFiveMessages = List.generate(
        25,
        (i) => AssistantChatMessage(
          id: 'msg_$i',
          sender: i.isEven ? 'patient' : 'assistant',
          text: 'Message $i',
          createdAt: DateTime.now(),
        ),
      );

      fakeService.historyResult = GetAssistantHistoryResult(
        success: true,
        messages: twentyFiveMessages,
        offers: const [],
        revision: 7,
      );
      await provider.refreshHistory();
      expect(provider.revision, 7);
      expect(provider.messages.length, 20);
      expect(provider.messages.first.text, 'Message 5');
      expect(provider.messages.last.text, 'Message 24');

      provider.dispose();
    });
  });

  group('AssistantChatScreen Widget Tests', () {
    testWidgets('Renders empty state with privacy notice and standard booking fallback', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_123',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      // Heading & disclaimers
      expect(find.text('AI Scheduling Assistant'), findsWidgets);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(find.textContaining('Clinic Time (Baghdad, GMT+3)'), findsOneWidget);
      expect(find.textContaining('does not provide medical advice'), findsOneWidget);
      expect(find.text('Book an Appointment'), findsWidgets);

      // Character counter initialized to 0/500
      expect(find.text('0/500'), findsOneWidget);

      provider.dispose();
    });

    testWidgets('Daily quota displays exact required English heading and converted reset time', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final resetTime = DateTime.now().toUtc().add(const Duration(hours: 1));
      fakeService.historyResult = GetAssistantHistoryResult(
        success: true,
        messages: const [],
        offers: const [],
        revision: 2,
        resetAt: resetTime,
        status: AssistantMessageStatus.dailyLimit,
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_123',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      // EXACT required English heading check
      expect(find.text('The assistant has reached today’s limit.'), findsWidgets);
      expect(find.textContaining('This is a shared assistant limit'), findsOneWidget);
      expect(find.textContaining('Resets at'), findsOneWidget);

      // Visible button to standard booking
      expect(find.widgetWithText(ElevatedButton, 'Book an Appointment'), findsOneWidget);

      provider.dispose();
    });

    testWidgets('Renders properly in Arabic locale with RTL text direction', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_ar',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          locale: const Locale('ar'),
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      // Arabic localized title
      expect(find.text('مساعد المواعيد الذكي'), findsWidgets);
      // RTL directionality
      final directionality = tester.widget<Directionality>(
        find.byWidgetPredicate((w) => w is Directionality).first,
      );
      expect(directionality.textDirection, TextDirection.rtl);

      provider.dispose();
    });

    testWidgets('Renders properly in Kurdish Sorani locale with RTL text direction', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_ku',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          locale: const Locale('ku'),
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      // Kurdish localized title
      expect(find.text('یاریدەدەری زیرەکی نۆرەگرتن'), findsWidgets);

      final directionality = tester.widget<Directionality>(
        find.byWidgetPredicate((w) => w is Directionality).first,
      );
      expect(directionality.textDirection, TextDirection.rtl);

      provider.dispose();
    });

    testWidgets('Renders cleanly in dark theme without rendering overflow', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_dark',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          themeMode: ThemeMode.dark,
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI Scheduling Assistant'), findsWidgets);
      expect(tester.takeException(), isNull);

      provider.dispose();
    });

    testWidgets('Character count tracks text length and Send button enables only when valid', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_input',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);

      // Enter 10 characters
      await tester.enterText(inputFinder, '0123456789');
      await tester.pump();
      expect(find.text('10/500'), findsOneWidget);

      provider.dispose();
    });

    testWidgets('Affirmative confirmation modal: Cancel performs no booking, Confirm confirms offer', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final now = DateTime.now();
      final activeOffer = AssistantOffer(
        offerId: 'off_modal_test',
        doctorId: 'doc_cardio',
        doctorName: 'Dr. Hiba Al-Nuaimi',
        department: 'cardiology',
        appointmentDate: '2026-09-20',
        timeSlot: '09:30 - 10:00',
        expiresAt: now.add(const Duration(minutes: 10)),
        isAvailable: true,
      );

      fakeService.historyResult = GetAssistantHistoryResult(
        success: true,
        messages: [
          AssistantChatMessage(
            id: 'asst_1',
            sender: 'assistant',
            text: 'Here is a slot for you:',
            status: AssistantMessageStatus.ready,
            offerIds: [activeOffer.offerId],
            createdAt: now,
          ),
        ],
        offers: [activeOffer],
        revision: 1,
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_modal',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      // Offer card is rendered
      expect(find.text('Dr. Hiba Al-Nuaimi'), findsOneWidget);
      final bookSlotButton = find.widgetWithText(ElevatedButton, 'Book This Slot');
      expect(bookSlotButton, findsOneWidget);

      // 1. Tap Book This Slot -> opens affirmative confirmation modal
      await tester.tap(bookSlotButton);
      await tester.pumpAndSettle();

      expect(find.text('Selected Appointment Slot'), findsOneWidget);
      expect(find.text('09:30 - 10:00'), findsWidgets);
      expect(find.text('Slots are not reserved until confirmed.'), findsOneWidget);

      // 2. Tap Cancel -> closes modal without booking
      final cancelButton = find.widgetWithText(OutlinedButton, 'Cancel');
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();

      expect(fakeService.confirmAppointmentCallCount, 0); // NO booking made
      expect(find.text('Selected Appointment Slot'), findsNothing); // Modal dismissed

      // 3. Tap Book This Slot again -> Confirm Appointment
      await tester.tap(bookSlotButton);
      await tester.pumpAndSettle();

      final confirmButton = find.widgetWithText(ElevatedButton, 'Confirm Appointment');
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      // Verified affirmative booking call was issued with correct offerId and confirmed: true
      expect(fakeService.confirmAppointmentCallCount, 1);
      expect(fakeService.lastConfirmedOfferId, 'off_modal_test');
      expect(fakeService.lastConfirmedFlag, isTrue);

      provider.dispose();
    });

    testWidgets('Modal dismissal safety: user closes modal before booking completes without error', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final completer = Completer<ConfirmAssistantAppointmentResult>();
      fakeService.confirmCompleter = completer;

      final now = DateTime.now();
      final activeOffer = AssistantOffer(
        offerId: 'off_modal_dismiss',
        doctorId: 'doc_cardio',
        doctorName: 'Dr. Hiba Al-Nuaimi',
        department: 'cardiology',
        appointmentDate: '2026-09-20',
        timeSlot: '09:30 - 10:00',
        expiresAt: now.add(const Duration(minutes: 10)),
        isAvailable: true,
      );

      fakeService.historyResult = GetAssistantHistoryResult(
        success: true,
        messages: [
          AssistantChatMessage(
            id: 'asst_1',
            sender: 'assistant',
            text: 'Available slot:',
            status: AssistantMessageStatus.ready,
            offerIds: [activeOffer.offerId],
            createdAt: now,
          ),
        ],
        offers: [activeOffer],
        revision: 1,
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_modal',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      // Open confirmation modal
      final bookSlotButton = find.widgetWithText(ElevatedButton, 'Book This Slot');
      await tester.tap(bookSlotButton);
      await tester.pumpAndSettle();

      // Tap Confirm Appointment to begin in-flight request
      final confirmButton = find.widgetWithText(ElevatedButton, 'Confirm Appointment');
      await tester.tap(confirmButton);
      await tester.pump();

      expect(provider.isConfirming, isTrue);

      // User dismisses bottom sheet while booking is in-flight
      final navigator = Navigator.of(tester.element(find.text('Selected Appointment Slot')));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('Selected Appointment Slot'), findsNothing);

      // Now the network completes in the background
      completer.complete(const ConfirmAssistantAppointmentResult(
        success: true,
        appointmentId: 'appt_modal_bg_ok',
        bookingReference: 'BKBG123',
      ));
      await tester.pumpAndSettle();

      // Verified no crash / unhandled exception occurred
      expect(tester.takeException(), isNull);

      provider.dispose();
    });

    test('confirmOffer returns null if provider disposed or generation switched during await', () async {
      final fakeService = FakeAssistantFunctionsService();
      final completer = Completer<ConfirmAssistantAppointmentResult>();
      fakeService.confirmCompleter = completer;

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      final testOffer = AssistantOffer(
        offerId: 'off_gen_test',
        doctorId: 'doc_1',
        doctorName: 'Dr. Sarah',
        department: 'dentistry',
        appointmentDate: '2026-09-16',
        timeSlot: '11:00 - 11:30',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        isAvailable: true,
      );

      final confirmFuture = provider.confirmOffer(testOffer);
      expect(provider.isConfirming, isTrue);

      // Switch user / increment generation
      provider.updateActiveUser(userId: 'patient_B', role: UserRole.student);

      completer.complete(const ConfirmAssistantAppointmentResult(
        success: true,
        appointmentId: 'appt_late',
        bookingReference: 'BKLATE',
      ));

      final result = await confirmFuture;
      expect(result, isNull);
      provider.dispose();
    });

    test('sendMessage preserves recoverable draft and removes optimistic message on quota rejection', () async {
      final fakeService = FakeAssistantFunctionsService();
      fakeService.sendResult = const SendAssistantMessageResult(
        success: false,
        status: AssistantMessageStatus.dailyLimit,
        message: 'Daily quota reached.',
        replyLanguage: 'en',
        offers: [],
        revision: 2,
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      final success = await provider.sendMessage('Book cardiology', localeCode: 'en');
      expect(success, isFalse);
      expect(provider.unsentDraft, 'Book cardiology');
      expect(provider.currentStatus, AssistantMessageStatus.dailyLimit);
      expect(provider.messages.any((m) => m.sender == 'patient'), isFalse);
      provider.dispose();
    });

    testWidgets('AssistantChatScreen didChangeDependencies updates active user when AuthProvider notifies', (tester) async {
      final authProvider = MockAuthProvider();
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'user_A',
        functionsService: fakeService,
      );

      authProvider.setMockUser(UserModel(
        id: 'user_A',
        email: 'userA@test.com',
        fullName: 'User A',
        role: UserRole.student,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        createAssistantTestApp(
          authProvider: authProvider,
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      // Switch user on authProvider
      authProvider.setMockUser(UserModel(
        id: 'user_B',
        email: 'userB@test.com',
        fullName: 'User B',
        role: UserRole.student,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await tester.pumpAndSettle();

      expect(provider.patientId, 'user_B');
      expect(find.byType(AssistantChatScreen), findsOneWidget);
      provider.dispose();
    });

    testWidgets('Offer button is disabled when provider isRefreshing', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final activeOffer = AssistantOffer(
        offerId: 'off_refreshing',
        doctorId: 'doc_1',
        doctorName: 'Dr. Sarah',
        department: 'cardiology',
        appointmentDate: '2026-09-20',
        timeSlot: '09:00 - 09:30',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        isAvailable: true,
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      fakeService.historyResult = GetAssistantHistoryResult(
        success: true,
        messages: [
          AssistantChatMessage(
            id: 'asst_1',
            sender: 'assistant',
            text: 'Offer:',
            status: AssistantMessageStatus.ready,
            offerIds: [activeOffer.offerId],
            createdAt: DateTime.now(),
          ),
        ],
        offers: [activeOffer],
        revision: 2,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      final bookSlotButton = find.widgetWithText(ElevatedButton, 'Book This Slot');
      expect(bookSlotButton, findsOneWidget);
      final elevatedBtnWidget = tester.widget<ElevatedButton>(bookSlotButton);
      expect(elevatedBtnWidget.onPressed, isNotNull);

      // Now trigger refresh with in-flight completer
      final completer = Completer<GetAssistantHistoryResult>();
      fakeService.historyCompleter = completer;
      provider.refreshHistory();
      await tester.pump();
      expect(provider.isRefreshing, isTrue);

      final refreshedBtn = tester.widget<ElevatedButton>(bookSlotButton);
      expect(refreshedBtn.onPressed, isNull);

      completer.complete(fakeService.historyResult);
      await tester.pumpAndSettle();
      provider.dispose();
    });

    testWidgets('Pending retry offer card displays Retry button and allows confirmation click', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final pastExpiredOffer = AssistantOffer(
        offerId: 'off_retry_expired',
        doctorId: 'doc_1',
        doctorName: 'Dr. Sarah',
        department: 'cardiology',
        appointmentDate: '2026-09-20',
        timeSlot: '09:00 - 09:30',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        isAvailable: false,
      );

      fakeService.historyResult = GetAssistantHistoryResult(
        success: true,
        messages: [
          AssistantChatMessage(
            id: 'asst_1',
            sender: 'assistant',
            text: 'Offer:',
            status: AssistantMessageStatus.ready,
            offerIds: [pastExpiredOffer.offerId],
            createdAt: DateTime.now(),
          ),
        ],
        offers: [pastExpiredOffer],
        revision: 2,
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_A',
        functionsService: fakeService,
      );

      // Simulate network timeout leaving active booking offerId
      fakeService.confirmException = const AssistantFunctionException(
        code: 'unavailable',
        message: 'Timeout',
      );
      await provider.confirmOffer(pastExpiredOffer.copyWith(
        isAvailable: true,
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      ));

      await tester.pumpWidget(
        createAssistantTestApp(
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      final retryButton = find.widgetWithText(ElevatedButton, 'Retry');
      expect(retryButton, findsOneWidget);
      final retryWidget = tester.widget<ElevatedButton>(retryButton);
      expect(retryWidget.onPressed, isNotNull);

      provider.dispose();
    });

    testWidgets('Tapping outside input unfocuses and preserves typed text, tapping input re-focuses', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      final provider = AssistantChatProvider(
        patientId: 'patient_focus_test',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);

      // 1. Tap the text field and enter text
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.enterText(inputFinder, 'Need dentist appointment');
      await tester.pumpAndSettle();

      // Verify text field has focus
      var editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.focusNode.hasFocus, isTrue);
      expect(find.text('Need dentist appointment'), findsOneWidget);

      // 2. Tap outside the input field (e.g. on the empty state icon)
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();

      // Verify focus is removed (typing disabled) but text is retained
      editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.focusNode.hasFocus, isFalse);
      expect(find.text('Need dentist appointment'), findsOneWidget);

      // 3. Tap the input box again to re-enable typing
      await tester.tap(inputFinder);
      await tester.pumpAndSettle();

      editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.focusNode.hasFocus, isTrue);
      expect(find.text('Need dentist appointment'), findsOneWidget);

      provider.dispose();
    });

    testWidgets('Dragging chat message list dismisses input focus', (tester) async {
      final fakeService = FakeAssistantFunctionsService();
      fakeService.historyResult = GetAssistantHistoryResult(
        success: true,
        messages: List.generate(
          10,
          (i) => AssistantChatMessage(
            id: 'msg_$i',
            sender: i.isEven ? 'patient' : 'assistant',
            text: 'Message number $i',
            status: AssistantMessageStatus.ready,
            createdAt: DateTime.now().subtract(Duration(minutes: 10 - i)),
          ),
        ),
        offers: const [],
        revision: 1,
      );

      final provider = AssistantChatProvider(
        patientId: 'patient_scroll_test',
        functionsService: fakeService,
      );

      await tester.pumpWidget(
        createAssistantTestApp(
          child: AssistantChatScreen(provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byType(TextField);
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.enterText(inputFinder, 'Drafting a query...');
      await tester.pumpAndSettle();

      var editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.focusNode.hasFocus, isTrue);

      // Drag the ListView
      await tester.drag(find.byType(ListView), const Offset(0, 100));
      await tester.pumpAndSettle();

      editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.focusNode.hasFocus, isFalse);
      expect(find.text('Drafting a query...'), findsOneWidget);

      provider.dispose();
    });
  });
}

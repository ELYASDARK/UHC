import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readProjectFile(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('security regression guards', () {
    test('web App Check is fully disabled for prelaunch testing', () {
      final mainDart = readProjectFile('lib/main.dart');

      expect(mainDart, isNot(contains('firebase_app_check')));
      expect(mainDart, isNot(contains('FirebaseAppCheck')));
      expect(
          mainDart, isNot(contains('FIREBASE_APPCHECK_RECAPTCHA_V3_SITE_KEY')));
    });

    test('appointment slot checks use deterministic lock documents', () {
      final functionsSource = readProjectFile('functions/src/index.ts');

      expect(functionsSource, contains('await db.runTransaction'));
      expect(functionsSource, contains("collection('appointment_slot_locks')"));
      expect(functionsSource, contains('lockAppointmentSlot(transaction'));
      expect(functionsSource, isNot(contains('appointmentSlotQuery')));
      expect(functionsSource, isNot(contains('assertNoSlotConflict')));
      expect(functionsSource, isNot(contains('doctorName: data.doctorName')));
      expect(
          functionsSource, isNot(contains('doctorName: data.doctorName ||')));
    });

    test('legacy medical document uploads still require file validation', () {
      final storageRules = readProjectFile('storage.rules');

      expect(
        storageRules,
        isNot(contains(
          'allow read, write, delete: if activeUser() && request.auth.uid == userId;',
        )),
      );
      expect(storageRules, contains('allow write: if activeUser() &&'));
      expect(storageRules, contains('validMedicalDocument();'));
    });

    test('admin notification sends are audited and idempotent', () {
      final functionsSource = readProjectFile('functions/src/index.ts');
      final serviceSource =
          readProjectFile('lib/services/admin_notification_service.dart');

      expect(functionsSource, contains('reserveAdminNotificationSend'));
      expect(
          functionsSource, contains("collection('admin_notification_sends')"));
      expect(functionsSource, contains("action: 'notifications.send.attempt'"));
      expect(functionsSource, contains("action: 'notifications.send.failed'"));
      expect(functionsSource, contains('createdCount: notificationIds.length'));
      expect(functionsSource, contains('bodyLength: body.length'));
      expect(functionsSource, isNot(contains('bodyPreview')));
      expect(serviceSource, contains("'requestId': _uuid.v4()"));
    });

    test('legacy topic notifications are disabled', () {
      final functionsSource = readProjectFile('functions/src/index.ts');

      expect(
        functionsSource,
        contains("action: 'notifications.topicSend.blocked'"),
      );
      expect(
        functionsSource,
        contains('Topic notifications are disabled. Use sendAdminNotification'),
      );
      expect(functionsSource, isNot(contains('messaging.send({')));
    });

    test('admin permissions are strict booleans before storage', () {
      final functionsSource = readProjectFile('functions/src/index.ts');

      expect(functionsSource, contains('function sanitizeAdminPermissions'));
      expect(functionsSource, contains('perms[permissionKey] !== true'));
      expect(functionsSource, contains('Unknown permission key'));
      expect(functionsSource, contains('must be true or false'));
      expect(
        functionsSource,
        contains('adminPermissions: sanitizedPermissions'),
      );
    });

    test('admin appointment mutations require manage permission', () {
      final functionsSource = readProjectFile('functions/src/index.ts');

      expect(functionsSource, contains('isAdminWithAppointmentMutationAccess'));
      expect(
        functionsSource,
        contains("perms?.['appointments.manage'] === true"),
      );
      expect(
        functionsSource,
        isNot(contains(
          "perms?.['appointments.view'] || perms?.['analytics.view'] || perms?.['reports.view']",
        )),
      );
    });

    test('push delivery records push status separately from in-app delivery',
        () {
      final functionsSource = readProjectFile('functions/src/index.ts');

      expect(functionsSource, contains("pushStatus: 'skipped_no_token'"));
      expect(functionsSource, contains("pushStatus: 'sent'"));
      expect(functionsSource, contains("pushStatus: 'retryable_error'"));
      expect(functionsSource, contains("'failed_retry_exhausted'"));
      expect(functionsSource, contains('MAX_PUSH_DELIVERY_ATTEMPTS'));
    });

    test('admin notification sender blocks empty recipient confirmation', () {
      final senderSource = readProjectFile(
        'lib/screens/admin/notifications/admin_notification_sender_screen.dart',
      );

      expect(senderSource, contains('preview.recipientCount <= 0'));
      expect(
          senderSource, contains('No active recipients matched this target.'));
      expect(senderSource, contains('_completedSearchQuery'));
      expect(senderSource, contains('No active recipients found.'));
    });

    test('admin notification recipient search avoids brittle indexes', () {
      final functionsSource = readProjectFile('functions/src/index.ts');
      final senderSource = readProjectFile(
        'lib/screens/admin/notifications/admin_notification_sender_screen.dart',
      );

      expect(functionsSource, contains('function normalizeSearchText'));
      expect(functionsSource, contains("replace(/[أإآٱ]/g, 'ا')"));
      expect(functionsSource, contains("replace(/[ىئ]/g, 'ي')"));
      expect(functionsSource, contains('doctorRecipientFromDocs'));
      expect(
        functionsSource,
        contains("console.error('searchAdminNotificationRecipients failed:'"),
      );
      expect(
        functionsSource,
        contains("console.error('previewAdminNotificationRecipients failed:'"),
      );
      expect(
          functionsSource,
          isNot(contains(
            ".where('role', 'in', ['student', 'staff'])",
          )));
      expect(senderSource, contains('Unable to count'));
      expect(senderSource, contains('message == \'internal\''));
    });

    test('admin notification quick action stays locked without permission', () {
      final dashboardSource = readProjectFile(
        'lib/screens/admin/dashboard/admin_dashboard_screen.dart',
      );

      expect(dashboardSource, contains("title: 'Send Notification'"));
      expect(dashboardSource, contains('isEnabled: canSendNotifications'));
      expect(dashboardSource, contains('color: Colors.deepOrange'));
      expect(dashboardSource, contains('color: Colors.indigo'));
      expect(dashboardSource, contains('Icons.lock_outline'));
      expect(dashboardSource, isNot(contains('if (canSendNotifications)')));
    });

    test('mobile profile keeps logout above bottom navigation', () {
      final profileSource = readProjectFile(
        'lib/screens/patient/profile/profile_screen.dart',
      );

      expect(
        profileSource,
        contains(
            'bottomPadding: UhcResponsive.isWide(context)\n            ? 32\n            : (isSuperAdmin ? 32 : 100)'),
      );
      expect(profileSource, contains('logout,'));
    });

    test('notification list opens a full detail dialog', () {
      final notificationsSource = readProjectFile(
        'lib/screens/shared/notifications_screen.dart',
      );

      expect(notificationsSource, contains('_showNotificationDetails'));
      expect(notificationsSource, contains('SelectableText'));
      expect(notificationsSource, contains('_detailLine'));
      expect(notificationsSource, contains('notification.body'));
      expect(notificationsSource, isNot(contains('Appointment ID')));
    });

    test('local notification cleanup is safe on web and before init', () {
      final localNotificationSource =
          readProjectFile('lib/services/local_notification_service.dart');

      expect(localNotificationSource, contains('bool _isInitialized = false'));
      expect(localNotificationSource,
          contains('if (kIsWeb || !_isInitialized) return;'));
      expect(
        localNotificationSource,
        contains('if (kIsWeb || !_isInitialized) return const [];'),
      );
    });

    test('doctor appointment paging index includes document name ordering', () {
      final indexes = readProjectFile('firestore.indexes.json');

      expect(indexes, contains('"fieldPath": "doctorId"'));
      expect(indexes, contains('"fieldPath": "appointmentDate"'));
      expect(indexes, contains('"fieldPath": "__name__"'));
      expect(indexes, contains('"order": "DESCENDING"'));
    });

    test('doctor unavailable requests require admin approval', () {
      final functionsSource = readProjectFile('functions/src/index.ts');
      final firestoreRules = readProjectFile('firestore.rules');
      final dashboardSource = readProjectFile(
        'lib/screens/doctor/dashboard/doctor_dashboard_screen.dart',
      );
      final notificationsSource = readProjectFile(
        'lib/screens/shared/notifications_screen.dart',
      );

      expect(functionsSource, contains('requestDoctorUnavailable'));
      expect(functionsSource, contains('reviewDoctorAvailabilityRequest'));
      expect(functionsSource, contains('setDoctorAvailabilityByAdmin'));
      expect(
          functionsSource, contains('DOCTOR_AVAILABILITY_MONTHLY_LIMIT = 2'));
      expect(functionsSource,
          contains('cancelActiveAppointmentsForUnavailableDoctor'));
      expect(functionsSource, contains('doctorData?.isAvailable !== true'));
      expect(firestoreRules, contains("'isAvailable'"));
      expect(firestoreRules, contains('doctor_availability_requests'));
      expect(dashboardSource, contains('_showUnavailableRequestDialog'));
      expect(dashboardSource, contains('Pending approval'));
      expect(notificationsSource, contains('_buildAvailabilityRequestCard'));
      expect(notificationsSource, contains('showAvailabilityActions'));
      expect(notificationsSource, contains("hasPermission('doctors.manage')"));
    });

    test('patients cannot book unavailable doctors from UI paths', () {
      final doctorListSource = readProjectFile(
        'lib/screens/patient/browse_doctors/doctor_list_screen.dart',
      );
      final bookingSource = readProjectFile(
        'lib/screens/patient/booking/booking_screen.dart',
      );
      final scheduleSource = readProjectFile(
        'lib/screens/patient/browse_doctors/doctor_schedule_screen.dart',
      );

      expect(doctorListSource, contains('!doctor.isAvailable'));
      expect(doctorListSource,
          contains('This doctor is not available for booking right now.'));
      expect(bookingSource, contains('bool get _doctorCanBook'));
      expect(bookingSource, contains('doctorId: _doctor.id'));
      expect(scheduleSource, contains('!_doctor.isAvailable'));
      expect(scheduleSource, contains('.snapshots()'));
    });
  });
}

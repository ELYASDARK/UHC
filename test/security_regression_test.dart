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
      final functionsSource = [
        readProjectFile('functions/src/appointments.ts'),
        readProjectFile('functions/src/shared/appointmentHelpers.ts'),
      ].join('\n');

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
      expect(storageRules, contains('allow write: if googleLinkedUser() &&'));
      expect(storageRules, contains('validMedicalDocument();'));
    });

    test('mobile medical image documents use Flutter fullscreen viewer', () {
      final patientDocsSource = readProjectFile(
          'lib/screens/patient/documents/medical_documents_screen.dart');
      final doctorDocsSource = readProjectFile(
          'lib/screens/doctor/documents/doctor_patient_documents_screen.dart');
      final viewerSource = readProjectFile(
          'lib/screens/shared/medical_document_viewer_screen.dart');

      expect(patientDocsSource, contains('MedicalDocumentViewerScreen'));
      expect(doctorDocsSource, contains('MedicalDocumentViewerScreen'));
      expect(patientDocsSource, contains('!kIsWeb && _isImageDocument(doc)'));
      expect(doctorDocsSource, contains('!kIsWeb && _isImageDocument(doc)'));
      expect(viewerSource, contains('InteractiveViewer'));
      expect(viewerSource, contains('fit: BoxFit.contain'));
      expect(viewerSource, contains('alignment: Alignment.center'));
      expect(viewerSource, contains('panEnabled: false'));
      expect(viewerSource, contains('scaleEnabled: true'));
      expect(viewerSource, contains('TransformationController'));
      expect(viewerSource, contains('onDoubleTap: _handleDoubleTap'));
      expect(viewerSource, contains('Reset zoom'));
    });

    test('Flutter run does not rewrite generated l10n files every launch', () {
      final pubspec = readProjectFile('pubspec.yaml');

      expect(
        pubspec,
        contains('flutter:\n  generate: false\n  uses-material-design: true'),
      );
    });

    test('admin notification sends are audited and idempotent', () {
      final functionsSource =
          readProjectFile('functions/src/notifications/admin.ts');
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
      final functionsSource =
          readProjectFile('functions/src/notifications/admin.ts');

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
      final functionsSource = [
        readProjectFile('functions/src/shared/auth.ts'),
        readProjectFile('functions/src/admin.ts'),
      ].join('\n');

      expect(functionsSource, contains('function sanitizeAdminPermissions'));
      expect(functionsSource, contains('perms[permissionKey] !== true'));
      expect(functionsSource, contains('Unknown permission key'));
      expect(functionsSource, contains('must be true or false'));
      expect(
        functionsSource,
        contains('adminPermissions: sanitizedPermissions'),
      );
    });

    test('appointment admin permissions stay hidden until UI exists', () {
      final permissionsSource =
          readProjectFile('lib/data/models/admin_permissions_model.dart');
      final adminControlSource =
          readProjectFile('lib/screens/super_admin/admin_control_screen.dart');

      expect(permissionsSource, contains("static const List<String> allKeys"));
      expect(permissionsSource, contains("'appointments.view'"));
      expect(permissionsSource, contains("'appointments.manage'"));
      expect(
          permissionsSource, contains("static const List<String> visibleKeys"));

      final visibleKeysBlock = permissionsSource.substring(
        permissionsSource.indexOf('static const List<String> visibleKeys'),
        permissionsSource.indexOf('/// Human-readable labels'),
      );
      expect(visibleKeysBlock, isNot(contains("'appointments.view'")));
      expect(visibleKeysBlock, isNot(contains("'appointments.manage'")));
      expect(adminControlSource, contains('AdminPermissions.visibleKeys'));
      expect(
          adminControlSource, isNot(contains('AdminPermissions.allKeys.map')));
      expect(
          adminControlSource, contains("payload['appointments.view'] = false"));
      expect(adminControlSource,
          contains("payload['appointments.manage'] = false"));
    });

    test('push delivery records push status separately from in-app delivery',
        () {
      final functionsSource =
          readProjectFile('functions/src/notifications/delivery.ts');

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
      final functionsSource =
          readProjectFile('functions/src/notifications/admin.ts');
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

    test('auth startup avoids persistent Firestore cache logout deadlocks', () {
      final mainSource = readProjectFile('lib/main.dart');
      final authServiceSource =
          readProjectFile('lib/services/auth_service.dart');

      expect(mainSource, contains('persistenceEnabled: false'));
      expect(mainSource, isNot(contains('CACHE_SIZE_UNLIMITED')));
      expect(authServiceSource, isNot(contains('.terminate()')));
      expect(authServiceSource, isNot(contains('clearPersistence()')));
    });

    test('Google unlink clears security fields only through Functions', () {
      final authServiceSource =
          readProjectFile('lib/services/auth_service.dart');
      final usersFunctionsSource = readProjectFile('functions/src/users.ts');
      final indexSource = readProjectFile('functions/src/index.ts');

      expect(authServiceSource,
          contains("httpsCallable('unlinkOwnGoogleProvider')"));
      expect(
        authServiceSource,
        isNot(contains("'googleEmail': null")),
      );
      expect(usersFunctionsSource,
          contains('export const unlinkOwnGoogleProvider'));
      expect(
          usersFunctionsSource, contains("providersToUnlink: ['google.com']"));
      expect(usersFunctionsSource, contains('googleEmail: null'));
      expect(indexSource, contains('unlinkOwnGoogleProvider'));
    });

    test('doctor appointment paging index includes document name ordering', () {
      final indexes = readProjectFile('firestore.indexes.json');

      expect(indexes, contains('"fieldPath": "doctorId"'));
      expect(indexes, contains('"fieldPath": "appointmentDate"'));
      expect(indexes, contains('"fieldPath": "__name__"'));
      expect(indexes, contains('"order": "DESCENDING"'));
    });

    test('doctor unavailable requests require admin approval', () {
      final functionsSource =
          readProjectFile('functions/src/doctorAvailability.ts');
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
      expect(functionsSource, contains('doctorData.isActive !== true'));
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

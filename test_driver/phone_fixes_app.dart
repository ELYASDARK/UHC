import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:provider/provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:uhc/core/config/emulator_config.dart';
import 'package:uhc/core/constants/app_colors.dart';
import 'package:uhc/core/utils/app_messages.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/models/doctor_model.dart';
import 'package:uhc/data/models/medical_document_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/main.dart' as app;
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/doctor_appointment_provider.dart';
import 'package:uhc/providers/document_provider.dart';
import 'package:uhc/services/local_notification_service.dart';
import 'package:uhc/screens/doctor/documents/doctor_patient_documents_screen.dart';
import 'package:uhc/providers/theme_provider.dart';
import 'package:uhc/screens/admin/doctors/doctor_management_screen.dart';
import 'package:uhc/screens/doctor/appointments/doctor_appointment_detail_screen.dart';
import 'package:uhc/screens/doctor/schedule/doctor_schedule_management_screen.dart';
import 'package:uhc/screens/patient/booking/booking_screen.dart';
import 'package:uhc/screens/patient/main_shell.dart';
import 'package:uhc/screens/doctor/doctor_shell.dart';
import 'package:uhc/screens/patient/appointments/my_appointments_screen.dart';
import 'package:uhc/screens/patient/documents/medical_documents_screen.dart';
import 'package:uhc/screens/admin/reports/reports_screen.dart';
import 'package:uhc/screens/shared/language_screen.dart';
import 'package:uhc/screens/shared/medical_document_viewer_screen.dart';
import 'package:uhc/screens/patient/appointments/emergency_request_screen.dart';
import 'package:uhc/screens/patient/appointments/reschedule_screen.dart';
import 'package:uhc/screens/patient/profile/edit_profile_screen.dart';
import 'package:uhc/screens/doctor/profile/edit_doctor_profile_screen.dart';
import 'package:uhc/screens/doctor/appointments/patient_detail_screen.dart';
import 'package:uhc/screens/patient/browse_doctors/doctor_schedule_screen.dart';
import 'package:uhc/screens/patient/departments/department_browsing_screen.dart';
import 'package:uhc/screens/shared/notifications_screen.dart';
import 'package:uhc/screens/patient/browse_doctors/doctor_list_screen.dart';
import 'package:uhc/screens/patient/location/health_center_map_screen.dart';

/// Debug-only route access for repeatable synthetic emulator captures.
void main() {
  if (!kDebugMode || !EmulatorConfig.isEmulatorEnabled) {
    throw StateError(
        'Phone QA requires debug mode and local Firebase emulators.');
  }
  enableFlutterDriverExtension();
  developer.registerExtension('ext.uhc.phoneQa', (_, parameters) async {
    try {
      final navigator = app.navigatorKey.currentState!;
      final context = app.navigatorKey.currentContext!;
      switch (parameters['action']) {
        case 'locale':
          await context
              .read<LocaleProvider>()
              .setLocaleByCode(parameters['code']!);
        case 'theme':
          await context.read<ThemeProvider>().setThemeMode(
              parameters['mode'] == 'dark' ? ThemeMode.dark : ThemeMode.light);
        case 'signIn':
          final role = parameters['role'] ?? 'admin';
          final signedIn = await context.read<AuthProvider>().signInWithEmail(
              email: 'qa.$role@demo.uhc.edu', password: 'TestPassword123!');
          if (!signedIn) throw StateError('Synthetic role sign-in failed');
        case 'back':
          navigator.popUntil((route) => route.isFirst);
        case 'bottom':
          for (var frame = 0; frame < 6; frame++) {
            void visit(Element element) {
              if (element is StatefulElement &&
                  element.state is ScrollableState &&
                  ModalRoute.of(element)?.isCurrent == true) {
                final state = element.state as ScrollableState;
                if (state.position.hasContentDimensions &&
                    axisDirectionToAxis(state.axisDirection) == Axis.vertical) {
                  state.position.jumpTo(state.position.maxScrollExtent);
                }
              }
              element.visitChildren(visit);
            }

            context.visitChildElements(visit);
            await WidgetsBinding.instance.endOfFrame;
          }
        case 'managementProbe':
          final positions = <double>[];
          var skeletons = 0;
          void visit(Element element, bool insideManagement) {
            final inside =
                insideManagement || element.widget is DoctorManagementScreen;
            if (inside) {
              if (element.widget.runtimeType.toString() == 'CardSkeleton') {
                skeletons++;
              }
              if (element is StatefulElement &&
                  element.state is ScrollableState) {
                final state = element.state as ScrollableState;
                if (state.position.hasContentDimensions &&
                    axisDirectionToAxis(state.axisDirection) == Axis.vertical) {
                  positions.add(state.position.pixels);
                }
              }
            }
            element.visitChildren((child) => visit(child, inside));
          }
          context.visitChildElements((child) => visit(child, false));
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'scrollPositions': positions,
            'skeletons': skeletons,
          }));
        case 'pdfProbe':
          PdfViewPinch? viewer;
          void visit(Element element) {
            if (element.widget is PdfViewPinch) {
              viewer = element.widget as PdfViewPinch;
            }
            element.visitChildren(visit);
          }
          app.navigatorKey.currentContext!.visitChildElements(visit);
          if (viewer == null) {
            throw StateError('No native PDF viewer is mounted');
          }
          final document = await viewer!.controller.document;
          final page = await document.getPage(1);
          final rendered = await page.render(
              width: 400,
              height: page.height * 400 / page.width,
              backgroundColor: '#FFFFFF');
          await page.close();
          if (rendered == null) {
            throw StateError('Native PDF page render returned no pixels');
          }
          final codec = await ui.instantiateImageCodec(rendered.bytes);
          final frame = await codec.getNextFrame();
          final pixels =
              await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
          var ink = 0;
          for (var i = 0; i < pixels!.lengthInBytes; i += 4) {
            if (pixels.getUint8(i) < 220 ||
                pixels.getUint8(i + 1) < 220 ||
                pixels.getUint8(i + 2) < 220) {
              ink++;
            }
          }
          frame.image.dispose();
          codec.dispose();
          if (ink < 500) throw StateError('PDF page is blank: $ink ink pixels');
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'pages': document.pagesCount,
            'inkPixels': ink,
            'nativeRenderVerified': true
          }));
        case 'notifications':
          final service = LocalNotificationService();
          await service.initialize();
          if (parameters['cancel'] == 'true') {
            await service.cancelNotification(890001);
          } else {
            await service.scheduleNotification(
              id: 890001,
              title: 'QA synthetic reminder',
              body: 'Local scheduling check',
              scheduledTime: DateTime.now().add(
                  Duration(seconds: int.parse(parameters['seconds'] ?? '120'))),
              payload: '{"type":"qa_synthetic"}',
            );
          }
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'pending': (await service.getPendingNotifications())
                .map((item) => {'id': item.id, 'title': item.title})
                .toList(),
          }));
        case 'documentRoundTrip':
          final uid = FirebaseAuth.instance.currentUser!.uid;
          if (!['qa-phone-student', 'qa-phone-doctor'].contains(uid)) {
            throw StateError('Synthetic document owner required');
          }
          final provider = context.read<DocumentProvider>();
          final isDoctor = uid == 'qa-phone-doctor';
          final name = parameters['name'] ??
              (isDoctor ? 'QA_Final_Doctor' : 'QA_Final_Patient');
          if (!name.startsWith('QA_')) {
            throw StateError('Synthetic name required');
          }
          final first = base64Decode(parameters['first']!);
          final replacement = base64Decode(parameters['replacement']!);
          final uploaded = await provider.uploadAndAddDocument(
            userId: 'qa-phone-student',
            name: name,
            type: DocumentType.other,
            notes: 'Synthetic final Storage rule check',
            bytes: first,
            fileName: parameters['firstName']!,
            addedBy: uid,
            addedByRole: isDoctor ? 'doctor' : 'patient',
            appointmentId: isDoctor ? 'qa-phone-confirmed' : null,
          );
          if (!uploaded) throw StateError('Synthetic upload failed');
          final docs = await FirebaseFirestore.instance
              .collection('medical_documents')
              .where('userId', isEqualTo: 'qa-phone-student')
              .where('name', isEqualTo: name)
              .get(const GetOptions(source: Source.server));
          final doc = docs.docs.single;
          final oldPath = doc.data()['storagePath'] as String;
          if (parameters['replace'] == 'false') {
            final downloaded = await FirebaseStorage.instance
                .ref(oldPath)
                .getData(20 * 1024 * 1024);
            if (!listEquals(downloaded, first)) {
              throw StateError('Synthetic upload bytes differ');
            }
            return developer.ServiceExtensionResponse.result(jsonEncode({
              'id': doc.id,
              'actor': uid,
              'storagePath': oldPath,
              'nativeBytesMatch': true,
            }));
          }
          final replaced = await provider.updateDocumentWithFile(
            docId: doc.id,
            userId: 'qa-phone-student',
            metaData: {
              'name': name,
              'type': 'other',
              'notes': 'Synthetic final replacement'
            },
            bytes: replacement,
            fileName: parameters['replacementName']!,
            oldStoragePath: oldPath,
          );
          if (!replaced) throw StateError('Synthetic replacement failed');
          final finalDoc =
              await doc.reference.get(const GetOptions(source: Source.server));
          final path = finalDoc.data()!['storagePath'] as String;
          final downloaded = await FirebaseStorage.instance
              .ref(path)
              .getData(20 * 1024 * 1024);
          if (!listEquals(downloaded, replacement) || oldPath == path) {
            throw StateError('Synthetic native byte verification failed');
          }
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'id': doc.id,
            'actor': uid,
            'fileName': finalDoc.data()!['fileName'],
            'storagePath': path,
            'nativeBytesMatch': true,
          }));
        case 'pinch':
          final center = MediaQuery.sizeOf(context).center(Offset.zero);
          final viewId = View.of(context).viewId;
          for (final pointer in [41, 42]) {
            GestureBinding.instance.handlePointerEvent(PointerDownEvent(
                pointer: pointer,
                viewId: viewId,
                position: center + Offset(pointer == 41 ? -55 : 55, 0)));
          }
          for (var step = 1; step <= 25; step++) {
            final spread = 55 + step * 3.0;
            for (final pointer in [41, 42]) {
              GestureBinding.instance.handlePointerEvent(PointerMoveEvent(
                  pointer: pointer,
                  viewId: viewId,
                  position:
                      center + Offset(pointer == 41 ? -spread : spread, 0)));
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          for (final pointer in [41, 42]) {
            GestureBinding.instance.handlePointerEvent(
                PointerUpEvent(pointer: pointer, viewId: viewId));
          }
        case 'snack':
          final l10n = AppMessages.localizations(context);
          final kind = parameters['kind'];
          final message = kind == 'error'
              ? AppMessages.error(
                  context,
                  FirebaseFunctionsException(
                      code: parameters['code'] ?? 'internal',
                      message:
                          'Private fixture #0 package:private/source.dart:22'))
              : kind == 'warning'
                  ? l10n.documentsAccessLocked
                  : l10n.profileUpdated;
          AppMessages.show(
              context,
              SnackBar(
                content: Text(parameters['long'] == 'true'
                    ? List.filled(20, message).join(' ')
                    : message),
                duration: const Duration(seconds: 20),
                backgroundColor: kind == 'error'
                    ? AppColors.error
                    : kind == 'warning'
                        ? AppColors.warning
                        : AppColors.success,
                action: parameters['retry'] == 'true'
                    ? SnackBarAction(label: l10n.retry, onPressed: () {})
                    : null,
              ));
        case 'open':
          final screen = parameters['screen'];
          final doctor = DoctorModel.fromFirestore(await FirebaseFirestore
              .instance
              .collection('doctors')
              .doc('qa-phone-doctor')
              .get());
          Widget page;
          switch (screen) {
            case 'doctorShell':
              page = DoctorShell(
                  doctor: doctor,
                  initialIndex: int.parse(parameters['tab'] ?? '0'));
            case 'home':
              page =
                  MainShell(initialIndex: int.parse(parameters['tab'] ?? '0'));
            case 'emergency':
              page = const EmergencyRequestScreen();
            case 'editProfile':
              page = const EditProfileScreen();
            case 'editDoctorProfile':
              page = EditDoctorProfileScreen(doctor: doctor);
            case 'patientHistory':
              page = PatientDetailScreen(
                  patientId: 'qa-phone-student',
                  patientName: 'QA Synthetic Patient',
                  doctor: doctor);
            case 'departments':
              page = const DepartmentBrowsingScreen();
            case 'doctorBrowseSchedule':
              page = DoctorScheduleScreen(doctor: doctor);
            case 'notificationsList':
              page = const NotificationsScreen();
            case 'doctorDetail':
              page = DoctorDetailScreen(doctor: doctor);
            case 'location':
              page = const HealthCenterMapScreen();
            case 'bookingSuccess':
              page = BookingSuccessScreen(
                  appointmentId: 'qa-phone-pending',
                  doctorName: 'QA Synthetic Doctor',
                  date: DateTime(2026, 10, 28),
                  timeSlot: '09:00');
            case 'reschedule':
              final document = await FirebaseFirestore.instance
                  .doc('appointments/qa-phone-pending')
                  .get();
              page = RescheduleScreen(
                  appointment: AppointmentModel.fromFirestore(document),
                  doctor: doctor);
            case 'appointments':
              page = const MyAppointmentsScreen();
            case 'documents':
              page = const MedicalDocumentsScreen();
            case 'doctorDocuments':
              page = const DoctorPatientDocumentsScreen(
                patientId: 'qa-phone-student',
                patientName: 'QA Synthetic Patient',
                appointmentId: 'qa-phone-confirmed',
                doctorId: 'qa-phone-doctor',
                doctorName: 'QA Synthetic Doctor',
              );
            case 'reports':
              page = const ReportsScreen();
            case 'language':
              page = const LanguageScreen();
            case 'admin':
              page = const DoctorManagementScreen();
            case 'schedule':
              page = DoctorScheduleManagementScreen(doctor: doctor);
            case 'booking':
              page = BookingScreen(
                  doctor: doctor,
                  initialDate: DateTime(2026, 10, 26),
                  appointmentRepository: _QaAvailabilityRepository(
                      delay: int.tryParse(parameters['delay'] ?? '') ?? 0,
                      fail: parameters['fail'] == 'true'));
            case 'detail':
              final document = await FirebaseFirestore.instance
                  .collection('appointments')
                  .doc(parameters['id'] ?? 'qa-phone-pending')
                  .get();
              page = DoctorAppointmentDetailScreen(
                  appointment: AppointmentModel.fromFirestore(document),
                  doctor: doctor);
              if (parameters['notesFailure'] == 'true') {
                page = ChangeNotifierProvider(
                    create: (_) => DoctorAppointmentProvider(
                        appointmentRepository: _QaNotesFailureRepository()),
                    child: page);
              }
            case 'image':
              final portrait = parameters['shape'] == 'portrait';
              page = MedicalDocumentViewerScreen(
                imageUrl: '',
                title: 'Synthetic document',
                captureImageSize:
                    portrait ? const Size(400, 900) : const Size(1200, 600),
                captureContent: const _SyntheticDocument(),
              );
            default:
              throw ArgumentError('Unknown QA screen');
          }
          navigator.popUntil((route) => route.isFirst);
          unawaited(navigator.push(MaterialPageRoute(builder: (_) => page)));
        default:
          throw ArgumentError('Unknown QA action');
      }
      return developer.ServiceExtensionResponse.result(
          jsonEncode({'ok': true}));
    } catch (error) {
      return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          'Synthetic QA action failed: ${error.runtimeType}');
    }
  });
  app.main();
}

class _QaNotesFailureRepository extends AppointmentRepository {
  @override
  Future<void> updateMedicalNotes(String appointmentId, String notes) async {
    throw FirebaseFunctionsException(
        code: 'unavailable', message: 'Private synthetic notes failure');
  }
}

class _QaAvailabilityRepository extends AppointmentRepository {
  final int delay;
  final bool fail;
  _QaAvailabilityRepository({required this.delay, required this.fail});

  @override
  Future<DoctorDayAvailability> getDoctorDayAvailability({
    required String doctorId,
    required DateTime date,
  }) async {
    if (delay > 0) await Future<void>.delayed(Duration(seconds: delay));
    if (fail) {
      throw FirebaseFunctionsException(
          code: 'unavailable', message: 'Synthetic offline');
    }
    return super.getDoctorDayAvailability(doctorId: doctorId, date: date);
  }
}

class _SyntheticDocument extends StatelessWidget {
  const _SyntheticDocument();
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.white,
        child: CustomPaint(painter: _DocumentGrid()),
      );
}

class _DocumentGrid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()..color = Colors.blueGrey;
    for (var i = 0; i <= 12; i++) {
      canvas.drawLine(Offset(size.width * i / 12, 0),
          Offset(size.width * i / 12, size.height), pen);
      canvas.drawLine(Offset(0, size.height * i / 12),
          Offset(size.width, size.height * i / 12), pen);
    }
    pen.color = Colors.blue;
    canvas.drawCircle(size.center(Offset.zero), size.shortestSide * .13, pen);
    pen
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawRect(Offset.zero & size, pen);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

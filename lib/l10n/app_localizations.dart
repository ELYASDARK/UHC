import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ku.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('ku')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'UHC'**
  String get appName;

  /// No description provided for @appFullName.
  ///
  /// In en, this message translates to:
  /// **'University Health Center'**
  String get appFullName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Your Campus Health Partner'**
  String get appTagline;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @dontHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get dontHaveAccount;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get alreadyHaveAccount;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @orContinueWith.
  ///
  /// In en, this message translates to:
  /// **'Or continue with'**
  String get orContinueWith;

  /// No description provided for @onboardingTitle1.
  ///
  /// In en, this message translates to:
  /// **'Book Appointments'**
  String get onboardingTitle1;

  /// No description provided for @onboardingDesc1.
  ///
  /// In en, this message translates to:
  /// **'Schedule appointments with university doctors easily and quickly'**
  String get onboardingDesc1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In en, this message translates to:
  /// **'Get Reminders'**
  String get onboardingTitle2;

  /// No description provided for @onboardingDesc2.
  ///
  /// In en, this message translates to:
  /// **'Never miss an appointment with smart notifications and reminders'**
  String get onboardingDesc2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In en, this message translates to:
  /// **'Track Your Health'**
  String get onboardingTitle3;

  /// No description provided for @onboardingDesc3.
  ///
  /// In en, this message translates to:
  /// **'Keep all your medical records and appointment history in one place'**
  String get onboardingDesc3;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @continueText.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueText;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAll;

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show More'**
  String get showMore;

  /// No description provided for @showLess.
  ///
  /// In en, this message translates to:
  /// **'Show Less'**
  String get showLess;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @doctors.
  ///
  /// In en, this message translates to:
  /// **'Doctors'**
  String get doctors;

  /// No description provided for @appointments.
  ///
  /// In en, this message translates to:
  /// **'Appointments'**
  String get appointments;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @alerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @searchDoctors.
  ///
  /// In en, this message translates to:
  /// **'Search doctors...'**
  String get searchDoctors;

  /// No description provided for @allDepartments.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allDepartments;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @bookNow.
  ///
  /// In en, this message translates to:
  /// **'Book Now'**
  String get bookNow;

  /// No description provided for @bookAppointment.
  ///
  /// In en, this message translates to:
  /// **'Book Appointment'**
  String get bookAppointment;

  /// No description provided for @selectDoctor.
  ///
  /// In en, this message translates to:
  /// **'Select Doctor'**
  String get selectDoctor;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select Date'**
  String get selectDate;

  /// No description provided for @selectTime.
  ///
  /// In en, this message translates to:
  /// **'Select Time'**
  String get selectTime;

  /// No description provided for @availableSlots.
  ///
  /// In en, this message translates to:
  /// **'Available Slots'**
  String get availableSlots;

  /// No description provided for @noSlotsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No slots available'**
  String get noSlotsAvailable;

  /// No description provided for @confirmBooking.
  ///
  /// In en, this message translates to:
  /// **'Confirm Booking'**
  String get confirmBooking;

  /// No description provided for @bookingConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Booking Confirmed'**
  String get bookingConfirmed;

  /// No description provided for @bookingFailed.
  ///
  /// In en, this message translates to:
  /// **'Booking Failed'**
  String get bookingFailed;

  /// No description provided for @appointmentBooked.
  ///
  /// In en, this message translates to:
  /// **'Appointment booked successfully'**
  String get appointmentBooked;

  /// No description provided for @confirmDetails.
  ///
  /// In en, this message translates to:
  /// **'Confirm Details'**
  String get confirmDetails;

  /// No description provided for @bookAnAppointment.
  ///
  /// In en, this message translates to:
  /// **'Book an Appointment'**
  String get bookAnAppointment;

  /// No description provided for @findBestDoctors.
  ///
  /// In en, this message translates to:
  /// **'Find the best doctors and schedule your visit today'**
  String get findBestDoctors;

  /// No description provided for @howAreYouFeeling.
  ///
  /// In en, this message translates to:
  /// **'How are you feeling today?'**
  String get howAreYouFeeling;

  /// No description provided for @noDepartments.
  ///
  /// In en, this message translates to:
  /// **'No departments'**
  String get noDepartments;

  /// No description provided for @weeks.
  ///
  /// In en, this message translates to:
  /// **'weeks'**
  String get weeks;

  /// No description provided for @generalMedicine.
  ///
  /// In en, this message translates to:
  /// **'General Medicine'**
  String get generalMedicine;

  /// No description provided for @dentistry.
  ///
  /// In en, this message translates to:
  /// **'Dentistry'**
  String get dentistry;

  /// No description provided for @psychology.
  ///
  /// In en, this message translates to:
  /// **'Psychology'**
  String get psychology;

  /// No description provided for @pharmacy.
  ///
  /// In en, this message translates to:
  /// **'Pharmacy'**
  String get pharmacy;

  /// No description provided for @laboratory.
  ///
  /// In en, this message translates to:
  /// **'Laboratory'**
  String get laboratory;

  /// No description provided for @firstAid.
  ///
  /// In en, this message translates to:
  /// **'First Aid'**
  String get firstAid;

  /// No description provided for @dermatology.
  ///
  /// In en, this message translates to:
  /// **'Dermatology'**
  String get dermatology;

  /// No description provided for @ophthalmology.
  ///
  /// In en, this message translates to:
  /// **'Ophthalmology'**
  String get ophthalmology;

  /// No description provided for @orthopedics.
  ///
  /// In en, this message translates to:
  /// **'Orthopedics'**
  String get orthopedics;

  /// No description provided for @cardiology.
  ///
  /// In en, this message translates to:
  /// **'Cardiology'**
  String get cardiology;

  /// No description provided for @neurology.
  ///
  /// In en, this message translates to:
  /// **'Neurology'**
  String get neurology;

  /// No description provided for @pediatrics.
  ///
  /// In en, this message translates to:
  /// **'Pediatrics'**
  String get pediatrics;

  /// No description provided for @clinicalPharmacy.
  ///
  /// In en, this message translates to:
  /// **'Clinical Pharmacy'**
  String get clinicalPharmacy;

  /// No description provided for @clinicalPsychology.
  ///
  /// In en, this message translates to:
  /// **'Clinical Psychology'**
  String get clinicalPsychology;

  /// No description provided for @orthodontics.
  ///
  /// In en, this message translates to:
  /// **'Orthodontics'**
  String get orthodontics;

  /// No description provided for @counseling.
  ///
  /// In en, this message translates to:
  /// **'Counseling'**
  String get counseling;

  /// No description provided for @mdDegree.
  ///
  /// In en, this message translates to:
  /// **'MD'**
  String get mdDegree;

  /// No description provided for @phdDegree.
  ///
  /// In en, this message translates to:
  /// **'PhD'**
  String get phdDegree;

  /// No description provided for @pharmDDegree.
  ///
  /// In en, this message translates to:
  /// **'PharmD'**
  String get pharmDDegree;

  /// No description provided for @ddsDegree.
  ///
  /// In en, this message translates to:
  /// **'DDS'**
  String get ddsDegree;

  /// No description provided for @psyDDegree.
  ///
  /// In en, this message translates to:
  /// **'PsyD'**
  String get psyDDegree;

  /// No description provided for @boardCertified.
  ///
  /// In en, this message translates to:
  /// **'Board Certified'**
  String get boardCertified;

  /// No description provided for @boardCertifiedPharmacotherapy.
  ///
  /// In en, this message translates to:
  /// **'Board Certified Pharmacotherapy'**
  String get boardCertifiedPharmacotherapy;

  /// No description provided for @licensedTherapist.
  ///
  /// In en, this message translates to:
  /// **'Licensed Therapist'**
  String get licensedTherapist;

  /// No description provided for @licensedPsychologist.
  ///
  /// In en, this message translates to:
  /// **'Licensed Psychologist'**
  String get licensedPsychologist;

  /// No description provided for @licensedCounselor.
  ///
  /// In en, this message translates to:
  /// **'Licensed Counselor'**
  String get licensedCounselor;

  /// No description provided for @phdClinicalPsychology.
  ///
  /// In en, this message translates to:
  /// **'PhD Clinical Psychology'**
  String get phdClinicalPsychology;

  /// No description provided for @certifiedOrthodontist.
  ///
  /// In en, this message translates to:
  /// **'Certified Orthodontist'**
  String get certifiedOrthodontist;

  /// No description provided for @fellowship.
  ///
  /// In en, this message translates to:
  /// **'Fellowship'**
  String get fellowship;

  /// No description provided for @residency.
  ///
  /// In en, this message translates to:
  /// **'Residency'**
  String get residency;

  /// No description provided for @boardCertifiedInternalMedicine.
  ///
  /// In en, this message translates to:
  /// **'Board Certified Internal Medicine'**
  String get boardCertifiedInternalMedicine;

  /// No description provided for @msOrthodontics.
  ///
  /// In en, this message translates to:
  /// **'MS Orthodontics'**
  String get msOrthodontics;

  /// No description provided for @phdPharmacology.
  ///
  /// In en, this message translates to:
  /// **'PhD Pharmacology'**
  String get phdPharmacology;

  /// No description provided for @certifiedInInvisalign.
  ///
  /// In en, this message translates to:
  /// **'Certified in Invisalign'**
  String get certifiedInInvisalign;

  /// No description provided for @familyMedicineSpecialist.
  ///
  /// In en, this message translates to:
  /// **'Family Medicine Specialist'**
  String get familyMedicineSpecialist;

  /// No description provided for @boardCertifiedCardiovascularDisease.
  ///
  /// In en, this message translates to:
  /// **'Board Certified Cardiovascular Disease'**
  String get boardCertifiedCardiovascularDisease;

  /// No description provided for @facc.
  ///
  /// In en, this message translates to:
  /// **'FACC'**
  String get facc;

  /// No description provided for @boardCertifiedCardiology.
  ///
  /// In en, this message translates to:
  /// **'Board Certified Cardiology'**
  String get boardCertifiedCardiology;

  /// No description provided for @internalMedicine.
  ///
  /// In en, this message translates to:
  /// **'Internal Medicine'**
  String get internalMedicine;

  /// No description provided for @generalDentistry.
  ///
  /// In en, this message translates to:
  /// **'General Dentistry'**
  String get generalDentistry;

  /// No description provided for @familyMedicine.
  ///
  /// In en, this message translates to:
  /// **'Family Medicine'**
  String get familyMedicine;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcoming;

  /// No description provided for @past.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get past;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get thisMonth;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @reschedule.
  ///
  /// In en, this message translates to:
  /// **'Reschedule'**
  String get reschedule;

  /// No description provided for @noUpcomingAppointments.
  ///
  /// In en, this message translates to:
  /// **'No upcoming appointments'**
  String get noUpcomingAppointments;

  /// No description provided for @noPastAppointments.
  ///
  /// In en, this message translates to:
  /// **'No past appointments'**
  String get noPastAppointments;

  /// No description provided for @appointmentDetails.
  ///
  /// In en, this message translates to:
  /// **'Appointment Details'**
  String get appointmentDetails;

  /// No description provided for @appointmentCancelled.
  ///
  /// In en, this message translates to:
  /// **'Appointment cancelled'**
  String get appointmentCancelled;

  /// No description provided for @cancelAppointment.
  ///
  /// In en, this message translates to:
  /// **'Cancel Appointment'**
  String get cancelAppointment;

  /// No description provided for @cancelAppointmentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to cancel this appointment?'**
  String get cancelAppointmentConfirm;

  /// No description provided for @appointmentStatus.
  ///
  /// In en, this message translates to:
  /// **'Appointment Status'**
  String get appointmentStatus;

  /// No description provided for @scheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get scheduled;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmed;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not Available'**
  String get notAvailable;

  /// No description provided for @specialty.
  ///
  /// In en, this message translates to:
  /// **'Specialty'**
  String get specialty;

  /// No description provided for @qualifications.
  ///
  /// In en, this message translates to:
  /// **'Qualifications'**
  String get qualifications;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @departments.
  ///
  /// In en, this message translates to:
  /// **'Departments'**
  String get departments;

  /// No description provided for @healthTips.
  ///
  /// In en, this message translates to:
  /// **'Health Tips'**
  String get healthTips;

  /// No description provided for @emergencyContact.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contact'**
  String get emergencyContact;

  /// No description provided for @callEmergency.
  ///
  /// In en, this message translates to:
  /// **'Call Emergency'**
  String get callEmergency;

  /// No description provided for @nearbyHospitals.
  ///
  /// In en, this message translates to:
  /// **'Nearby Hospitals'**
  String get nearbyHospitals;

  /// No description provided for @stayHydrated.
  ///
  /// In en, this message translates to:
  /// **'Stay Hydrated'**
  String get stayHydrated;

  /// No description provided for @stayHydratedDesc.
  ///
  /// In en, this message translates to:
  /// **'Drink at least 8 glasses of water daily'**
  String get stayHydratedDesc;

  /// No description provided for @regularExercise.
  ///
  /// In en, this message translates to:
  /// **'Regular Exercise'**
  String get regularExercise;

  /// No description provided for @regularExerciseDesc.
  ///
  /// In en, this message translates to:
  /// **'30 minutes of daily activity keeps you fit'**
  String get regularExerciseDesc;

  /// No description provided for @getEnoughSleep.
  ///
  /// In en, this message translates to:
  /// **'Get Enough Sleep'**
  String get getEnoughSleep;

  /// No description provided for @getEnoughSleepDesc.
  ///
  /// In en, this message translates to:
  /// **'7-8 hours of quality sleep is essential'**
  String get getEnoughSleepDesc;

  /// No description provided for @aboutDoctor.
  ///
  /// In en, this message translates to:
  /// **'About Doctor'**
  String get aboutDoctor;

  /// No description provided for @experience.
  ///
  /// In en, this message translates to:
  /// **'Experience'**
  String get experience;

  /// No description provided for @yearsExperience.
  ///
  /// In en, this message translates to:
  /// **'years'**
  String get yearsExperience;

  /// No description provided for @patients.
  ///
  /// In en, this message translates to:
  /// **'Patients'**
  String get patients;

  /// No description provided for @reviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get reviews;

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get rating;

  /// No description provided for @writeReview.
  ///
  /// In en, this message translates to:
  /// **'Write a Review'**
  String get writeReview;

  /// No description provided for @rateAndReview.
  ///
  /// In en, this message translates to:
  /// **'Rate & Review'**
  String get rateAndReview;

  /// No description provided for @submitReview.
  ///
  /// In en, this message translates to:
  /// **'Submit Review'**
  String get submitReview;

  /// No description provided for @submitAnonymously.
  ///
  /// In en, this message translates to:
  /// **'Submit anonymously'**
  String get submitAnonymously;

  /// No description provided for @yourNameWillNotBeShown.
  ///
  /// In en, this message translates to:
  /// **'Your name will not be shown'**
  String get yourNameWillNotBeShown;

  /// No description provided for @reviewSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Review submitted successfully'**
  String get reviewSubmitted;

  /// No description provided for @noReviews.
  ///
  /// In en, this message translates to:
  /// **'No reviews yet'**
  String get noReviews;

  /// No description provided for @averageRating.
  ///
  /// In en, this message translates to:
  /// **'Average Rating'**
  String get averageRating;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @languageChanged.
  ///
  /// In en, this message translates to:
  /// **'Language changed'**
  String get languageChanged;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get notificationSettings;

  /// No description provided for @pushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get pushNotifications;

  /// No description provided for @emailNotifications.
  ///
  /// In en, this message translates to:
  /// **'Email Notifications'**
  String get emailNotifications;

  /// No description provided for @smsNotifications.
  ///
  /// In en, this message translates to:
  /// **'SMS Notifications'**
  String get smsNotifications;

  /// No description provided for @appointmentReminders.
  ///
  /// In en, this message translates to:
  /// **'Appointment Reminders'**
  String get appointmentReminders;

  /// No description provided for @promotionalNotifications.
  ///
  /// In en, this message translates to:
  /// **'Promotional Notifications'**
  String get promotionalNotifications;

  /// No description provided for @appointmentNotifications.
  ///
  /// In en, this message translates to:
  /// **'Appointment Notifications'**
  String get appointmentNotifications;

  /// No description provided for @receiveRemindersForUpcomingAppointments.
  ///
  /// In en, this message translates to:
  /// **'Receive reminders for upcoming appointments'**
  String get receiveRemindersForUpcomingAppointments;

  /// No description provided for @hourReminder24.
  ///
  /// In en, this message translates to:
  /// **'Hour Reminder-24'**
  String get hourReminder24;

  /// No description provided for @getNotified24HoursBefore.
  ///
  /// In en, this message translates to:
  /// **'Get notified 24 hours before'**
  String get getNotified24HoursBefore;

  /// No description provided for @hourReminder1.
  ///
  /// In en, this message translates to:
  /// **'Hour Reminder-1'**
  String get hourReminder1;

  /// No description provided for @getNotified1HourBefore.
  ///
  /// In en, this message translates to:
  /// **'Get notified 1 hour before'**
  String get getNotified1HourBefore;

  /// No description provided for @updatesAndTips.
  ///
  /// In en, this message translates to:
  /// **'Updates & Tips'**
  String get updatesAndTips;

  /// No description provided for @healthTipsNotification.
  ///
  /// In en, this message translates to:
  /// **'Health Tips'**
  String get healthTipsNotification;

  /// No description provided for @dailyHealthTipsAndWellnessAdvice.
  ///
  /// In en, this message translates to:
  /// **'Daily health tips and wellness advice'**
  String get dailyHealthTipsAndWellnessAdvice;

  /// No description provided for @doctorUpdates.
  ///
  /// In en, this message translates to:
  /// **'Doctor Updates'**
  String get doctorUpdates;

  /// No description provided for @updatesFromYourDoctors.
  ///
  /// In en, this message translates to:
  /// **'Updates from your doctors'**
  String get updatesFromYourDoctors;

  /// No description provided for @specialOffersAndPromotions.
  ///
  /// In en, this message translates to:
  /// **'Special offers and promotions'**
  String get specialOffersAndPromotions;

  /// No description provided for @soundAndVibration.
  ///
  /// In en, this message translates to:
  /// **'Sound & Vibration'**
  String get soundAndVibration;

  /// No description provided for @sound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get sound;

  /// No description provided for @playSoundForNotifications.
  ///
  /// In en, this message translates to:
  /// **'Play sound for notifications'**
  String get playSoundForNotifications;

  /// No description provided for @vibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get vibration;

  /// No description provided for @vibrateForNotifications.
  ///
  /// In en, this message translates to:
  /// **'Vibrate for notifications'**
  String get vibrateForNotifications;

  /// No description provided for @manageNotificationPermissionsInSettings.
  ///
  /// In en, this message translates to:
  /// **'You can also manage notification permissions in your device settings'**
  String get manageNotificationPermissionsInSettings;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @helpAndSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpAndSupport;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact Us'**
  String get contactUs;

  /// No description provided for @faq.
  ///
  /// In en, this message translates to:
  /// **'FAQ'**
  String get faq;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @rateApp.
  ///
  /// In en, this message translates to:
  /// **'Rate App'**
  String get rateApp;

  /// No description provided for @shareApp.
  ///
  /// In en, this message translates to:
  /// **'Share App'**
  String get shareApp;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @updateProfile.
  ///
  /// In en, this message translates to:
  /// **'Update Profile'**
  String get updateProfile;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPassword;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get passwordChanged;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdated;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get changePhoto;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhoto;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get chooseFromGallery;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove Photo'**
  String get removePhoto;

  /// No description provided for @useCamera.
  ///
  /// In en, this message translates to:
  /// **'Use camera to take a new photo'**
  String get useCamera;

  /// No description provided for @selectFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Select from your photo library'**
  String get selectFromLibrary;

  /// No description provided for @deleteCurrentPhoto.
  ///
  /// In en, this message translates to:
  /// **'Delete current profile photo'**
  String get deleteCurrentPhoto;

  /// No description provided for @medicalDocuments.
  ///
  /// In en, this message translates to:
  /// **'Medical Documents'**
  String get medicalDocuments;

  /// No description provided for @uploadDocument.
  ///
  /// In en, this message translates to:
  /// **'Upload Document'**
  String get uploadDocument;

  /// No description provided for @documentType.
  ///
  /// In en, this message translates to:
  /// **'Document Type'**
  String get documentType;

  /// No description provided for @documentName.
  ///
  /// In en, this message translates to:
  /// **'Document Name'**
  String get documentName;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get selectFile;

  /// No description provided for @noDocuments.
  ///
  /// In en, this message translates to:
  /// **'No documents yet'**
  String get noDocuments;

  /// No description provided for @deleteDocument.
  ///
  /// In en, this message translates to:
  /// **'Delete Document'**
  String get deleteDocument;

  /// No description provided for @deleteDocumentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this document?'**
  String get deleteDocumentConfirm;

  /// No description provided for @documentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Document deleted'**
  String get documentDeleted;

  /// No description provided for @documentUploaded.
  ///
  /// In en, this message translates to:
  /// **'Document uploaded successfully'**
  String get documentUploaded;

  /// No description provided for @healthCenterLocation.
  ///
  /// In en, this message translates to:
  /// **'Health Center Location'**
  String get healthCenterLocation;

  /// No description provided for @getDirections.
  ///
  /// In en, this message translates to:
  /// **'Get Directions'**
  String get getDirections;

  /// No description provided for @callNow.
  ///
  /// In en, this message translates to:
  /// **'Call Now'**
  String get callNow;

  /// No description provided for @openingHours.
  ///
  /// In en, this message translates to:
  /// **'Opening Hours'**
  String get openingHours;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// No description provided for @workingDays.
  ///
  /// In en, this message translates to:
  /// **'Working Days'**
  String get workingDays;

  /// No description provided for @mondayToFriday.
  ///
  /// In en, this message translates to:
  /// **'Monday to Friday'**
  String get mondayToFriday;

  /// No description provided for @saturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get saturday;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get sunday;

  /// No description provided for @monday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get monday;

  /// No description provided for @tuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get tuesday;

  /// No description provided for @wednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get wednesday;

  /// No description provided for @thursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get thursday;

  /// No description provided for @friday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get friday;

  /// No description provided for @sun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get sun;

  /// No description provided for @mon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get mon;

  /// No description provided for @tue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get tue;

  /// No description provided for @wed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get wed;

  /// No description provided for @thu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get thu;

  /// No description provided for @fri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get fri;

  /// No description provided for @sat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get sat;

  /// No description provided for @closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @openNow.
  ///
  /// In en, this message translates to:
  /// **'Open Now'**
  String get openNow;

  /// No description provided for @closedNow.
  ///
  /// In en, this message translates to:
  /// **'Closed Now'**
  String get closedNow;

  /// No description provided for @january.
  ///
  /// In en, this message translates to:
  /// **'January'**
  String get january;

  /// No description provided for @february.
  ///
  /// In en, this message translates to:
  /// **'February'**
  String get february;

  /// No description provided for @march.
  ///
  /// In en, this message translates to:
  /// **'March'**
  String get march;

  /// No description provided for @april.
  ///
  /// In en, this message translates to:
  /// **'April'**
  String get april;

  /// No description provided for @may.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get may;

  /// No description provided for @june.
  ///
  /// In en, this message translates to:
  /// **'June'**
  String get june;

  /// No description provided for @july.
  ///
  /// In en, this message translates to:
  /// **'July'**
  String get july;

  /// No description provided for @august.
  ///
  /// In en, this message translates to:
  /// **'August'**
  String get august;

  /// No description provided for @september.
  ///
  /// In en, this message translates to:
  /// **'September'**
  String get september;

  /// No description provided for @october.
  ///
  /// In en, this message translates to:
  /// **'October'**
  String get october;

  /// No description provided for @november.
  ///
  /// In en, this message translates to:
  /// **'November'**
  String get november;

  /// No description provided for @december.
  ///
  /// In en, this message translates to:
  /// **'December'**
  String get december;

  /// No description provided for @sendTestNotification.
  ///
  /// In en, this message translates to:
  /// **'Send Test Notification'**
  String get sendTestNotification;

  /// No description provided for @testNotificationSent.
  ///
  /// In en, this message translates to:
  /// **'Test notification sent'**
  String get testNotificationSent;

  /// No description provided for @clearNotifications.
  ///
  /// In en, this message translates to:
  /// **'Clear Notifications'**
  String get clearNotifications;

  /// No description provided for @clearNotificationsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all notifications? This action cannot be undone.'**
  String get clearNotificationsConfirm;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAll;

  /// No description provided for @notificationsCleared.
  ///
  /// In en, this message translates to:
  /// **'Notifications cleared'**
  String get notificationsCleared;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @markAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markAsRead;

  /// No description provided for @deleteNotification.
  ///
  /// In en, this message translates to:
  /// **'Delete notification'**
  String get deleteNotification;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get logoutConfirm;

  /// No description provided for @loggingOut.
  ///
  /// In en, this message translates to:
  /// **'Logging out...'**
  String get loggingOut;

  /// No description provided for @loggedOut.
  ///
  /// In en, this message translates to:
  /// **'Logged out successfully'**
  String get loggedOut;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get fieldRequired;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get invalidEmail;

  /// No description provided for @weakPassword.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get weakPassword;

  /// No description provided for @passwordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordMismatch;

  /// No description provided for @invalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid phone number'**
  String get invalidPhone;

  /// No description provided for @invalidDate.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid date'**
  String get invalidDate;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @pleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait...'**
  String get pleaseWait;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @noInternetConnection.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get noInternetConnection;

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get connectionError;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please login again'**
  String get sessionExpired;

  /// No description provided for @unauthorized.
  ///
  /// In en, this message translates to:
  /// **'Unauthorized access'**
  String get unauthorized;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFound;

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get serverError;

  /// No description provided for @years.
  ///
  /// In en, this message translates to:
  /// **'years'**
  String get years;

  /// No description provided for @months.
  ///
  /// In en, this message translates to:
  /// **'months'**
  String get months;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get days;

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'hours'**
  String get hours;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'minutes'**
  String get minutes;

  /// No description provided for @ago.
  ///
  /// In en, this message translates to:
  /// **'ago'**
  String get ago;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @male.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get male;

  /// No description provided for @female.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get female;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @dateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth'**
  String get dateOfBirth;

  /// No description provided for @age.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get age;

  /// No description provided for @bloodType.
  ///
  /// In en, this message translates to:
  /// **'Blood Type'**
  String get bloodType;

  /// No description provided for @allergies.
  ///
  /// In en, this message translates to:
  /// **'Allergies'**
  String get allergies;

  /// No description provided for @medicalHistory.
  ///
  /// In en, this message translates to:
  /// **'Medical History'**
  String get medicalHistory;

  /// No description provided for @emergencyContactName.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contact Name'**
  String get emergencyContactName;

  /// No description provided for @emergencyContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contact Phone'**
  String get emergencyContactPhone;

  /// No description provided for @fees.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get fees;

  /// No description provided for @free.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get free;

  /// No description provided for @paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethod;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash;

  /// No description provided for @card.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get card;

  /// No description provided for @insurance.
  ///
  /// In en, this message translates to:
  /// **'Insurance'**
  String get insurance;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @adminDashboard.
  ///
  /// In en, this message translates to:
  /// **'Admin Dashboard'**
  String get adminDashboard;

  /// No description provided for @manageUsers.
  ///
  /// In en, this message translates to:
  /// **'Manage Users'**
  String get manageUsers;

  /// No description provided for @manageDoctors.
  ///
  /// In en, this message translates to:
  /// **'Manage Doctors'**
  String get manageDoctors;

  /// No description provided for @manageAppointments.
  ///
  /// In en, this message translates to:
  /// **'Manage Appointments'**
  String get manageAppointments;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @noDataFound.
  ///
  /// In en, this message translates to:
  /// **'No data found'**
  String get noDataFound;

  /// No description provided for @pullToRefresh.
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh'**
  String get pullToRefresh;

  /// No description provided for @loadingMore.
  ///
  /// In en, this message translates to:
  /// **'Loading more...'**
  String get loadingMore;

  /// No description provided for @endOfList.
  ///
  /// In en, this message translates to:
  /// **'End of list'**
  String get endOfList;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Add Note'**
  String get addNote;

  /// No description provided for @noNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes'**
  String get noNotes;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @symptoms.
  ///
  /// In en, this message translates to:
  /// **'Symptoms'**
  String get symptoms;

  /// No description provided for @diagnosis.
  ///
  /// In en, this message translates to:
  /// **'Diagnosis'**
  String get diagnosis;

  /// No description provided for @prescription.
  ///
  /// In en, this message translates to:
  /// **'Prescription'**
  String get prescription;

  /// No description provided for @followUp.
  ///
  /// In en, this message translates to:
  /// **'Follow-up'**
  String get followUp;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetails;

  /// No description provided for @moreInfo.
  ///
  /// In en, this message translates to:
  /// **'More Info'**
  String get moreInfo;

  /// No description provided for @lessInfo.
  ///
  /// In en, this message translates to:
  /// **'Less Info'**
  String get lessInfo;

  /// No description provided for @expand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// No description provided for @collapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapse;

  /// No description provided for @availableTimesFor.
  ///
  /// In en, this message translates to:
  /// **'Available Times for'**
  String get availableTimesFor;

  /// No description provided for @appointmentType.
  ///
  /// In en, this message translates to:
  /// **'Appointment Type'**
  String get appointmentType;

  /// No description provided for @regularVisit.
  ///
  /// In en, this message translates to:
  /// **'Regular Visit'**
  String get regularVisit;

  /// No description provided for @consultation.
  ///
  /// In en, this message translates to:
  /// **'Consultation'**
  String get consultation;

  /// No description provided for @emergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get emergency;

  /// No description provided for @additionalNotes.
  ///
  /// In en, this message translates to:
  /// **'Additional Notes'**
  String get additionalNotes;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @additionalNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'Additional Notes (Optional)'**
  String get additionalNotesOptional;

  /// No description provided for @describeSymptoms.
  ///
  /// In en, this message translates to:
  /// **'Describe your symptoms or reason for visit...'**
  String get describeSymptoms;

  /// No description provided for @pleaseSelectDateFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a date first'**
  String get pleaseSelectDateFirst;

  /// No description provided for @noAvailableSlotsOnThisDay.
  ///
  /// In en, this message translates to:
  /// **'No available slots on this day'**
  String get noAvailableSlotsOnThisDay;

  /// No description provided for @appointmentScheduledSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Your appointment has been scheduled successfully'**
  String get appointmentScheduledSuccessfully;

  /// No description provided for @showQRCodeAtCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Show this QR code at check-in'**
  String get showQRCodeAtCheckIn;

  /// No description provided for @doctor.
  ///
  /// In en, this message translates to:
  /// **'Doctor'**
  String get doctor;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @bookingId.
  ///
  /// In en, this message translates to:
  /// **'Booking ID'**
  String get bookingId;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get backToHome;

  /// No description provided for @viewMyAppointments.
  ///
  /// In en, this message translates to:
  /// **'View My Appointments'**
  String get viewMyAppointments;

  /// No description provided for @noNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Your appointment reminders will appear here'**
  String get noNotificationsDesc;

  /// No description provided for @profileSettings.
  ///
  /// In en, this message translates to:
  /// **'Profile Settings'**
  String get profileSettings;

  /// No description provided for @accountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get accountSettings;

  /// No description provided for @myDocuments.
  ///
  /// In en, this message translates to:
  /// **'My Documents'**
  String get myDocuments;

  /// No description provided for @healthCenterInfo.
  ///
  /// In en, this message translates to:
  /// **'Health Center Info'**
  String get healthCenterInfo;

  /// No description provided for @myAppointments.
  ///
  /// In en, this message translates to:
  /// **'My Appointments'**
  String get myAppointments;

  /// No description provided for @myReviews.
  ///
  /// In en, this message translates to:
  /// **'My Reviews'**
  String get myReviews;

  /// No description provided for @pleaseSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Please select a date'**
  String get pleaseSelectDate;

  /// No description provided for @pleaseSelectTime.
  ///
  /// In en, this message translates to:
  /// **'Please select a time slot'**
  String get pleaseSelectTime;

  /// No description provided for @pleaseLoginToBook.
  ///
  /// In en, this message translates to:
  /// **'Please login to book an appointment'**
  String get pleaseLoginToBook;

  /// No description provided for @bookingCancellationPolicy.
  ///
  /// In en, this message translates to:
  /// **'You can cancel or reschedule up to 24 hours before the appointment.'**
  String get bookingCancellationPolicy;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @tapToChangePhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to change photo'**
  String get tapToChangePhoto;

  /// No description provided for @enterFullName.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name'**
  String get enterFullName;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumberLabel;

  /// No description provided for @enterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get enterPhoneNumber;

  /// No description provided for @selectDateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Select your date of birth'**
  String get selectDateOfBirth;

  /// No description provided for @bloodTypeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., A+, B-, O+'**
  String get bloodTypeHint;

  /// No description provided for @allergiesHint.
  ///
  /// In en, this message translates to:
  /// **'List any allergies (optional)'**
  String get allergiesHint;

  /// No description provided for @choosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose Photo'**
  String get choosePhoto;

  /// No description provided for @pleaseEnterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get pleaseEnterName;

  /// No description provided for @nameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Name must be at least 2 characters'**
  String get nameTooShort;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @labResults.
  ///
  /// In en, this message translates to:
  /// **'Lab Results'**
  String get labResults;

  /// No description provided for @medicalRecord.
  ///
  /// In en, this message translates to:
  /// **'Medical Record'**
  String get medicalRecord;

  /// No description provided for @imaging.
  ///
  /// In en, this message translates to:
  /// **'X-Ray / Imaging'**
  String get imaging;

  /// No description provided for @manageYourMedicalRecords.
  ///
  /// In en, this message translates to:
  /// **'Manage your medical records'**
  String get manageYourMedicalRecords;

  /// No description provided for @pleaseFillRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill required fields'**
  String get pleaseFillRequiredFields;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get uploadFailed;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get updateFailed;

  /// No description provided for @documentUpdated.
  ///
  /// In en, this message translates to:
  /// **'Document updated successfully'**
  String get documentUpdated;

  /// No description provided for @openingDocument.
  ///
  /// In en, this message translates to:
  /// **'Opening document...'**
  String get openingDocument;

  /// No description provided for @couldNotOpenDocument.
  ///
  /// In en, this message translates to:
  /// **'Could not open the document'**
  String get couldNotOpenDocument;

  /// No description provided for @errorOpeningDocument.
  ///
  /// In en, this message translates to:
  /// **'Error opening document'**
  String get errorOpeningDocument;

  /// No description provided for @updateDocument.
  ///
  /// In en, this message translates to:
  /// **'Update Document'**
  String get updateDocument;

  /// No description provided for @currentFile.
  ///
  /// In en, this message translates to:
  /// **'Current File'**
  String get currentFile;

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @noURLProvided.
  ///
  /// In en, this message translates to:
  /// **'Error: No URL provided for this document'**
  String get noURLProvided;

  /// No description provided for @errorLoadingDocuments.
  ///
  /// In en, this message translates to:
  /// **'Error loading documents'**
  String get errorLoadingDocuments;

  /// No description provided for @uploadMedicalDocumentsDescription.
  ///
  /// In en, this message translates to:
  /// **'Upload your medical documents to keep them organized'**
  String get uploadMedicalDocumentsDescription;

  /// No description provided for @cancelAppointmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel Appointment?'**
  String get cancelAppointmentTitle;

  /// No description provided for @cannotCancel.
  ///
  /// In en, this message translates to:
  /// **'Cannot Cancel'**
  String get cannotCancel;

  /// No description provided for @cancelPolicyMessage.
  ///
  /// In en, this message translates to:
  /// **'This appointment cannot be cancelled as it is past the cancellation window.'**
  String get cancelPolicyMessage;

  /// No description provided for @lateCancellationWarning.
  ///
  /// In en, this message translates to:
  /// **'Late cancellation may affect your booking priority.'**
  String get lateCancellationWarning;

  /// No description provided for @reasonForCancellation.
  ///
  /// In en, this message translates to:
  /// **'Reason for Cancellation'**
  String get reasonForCancellation;

  /// No description provided for @reasonScheduleConflict.
  ///
  /// In en, this message translates to:
  /// **'Schedule conflict'**
  String get reasonScheduleConflict;

  /// No description provided for @reasonFeelingBetter.
  ///
  /// In en, this message translates to:
  /// **'Feeling better'**
  String get reasonFeelingBetter;

  /// No description provided for @reasonFoundAnotherDoctor.
  ///
  /// In en, this message translates to:
  /// **'Found another doctor'**
  String get reasonFoundAnotherDoctor;

  /// No description provided for @reasonPersonalEmergency.
  ///
  /// In en, this message translates to:
  /// **'Personal emergency'**
  String get reasonPersonalEmergency;

  /// No description provided for @reasonTransportationIssues.
  ///
  /// In en, this message translates to:
  /// **'Transportation issues'**
  String get reasonTransportationIssues;

  /// No description provided for @pleaseSpecify.
  ///
  /// In en, this message translates to:
  /// **'Please specify...'**
  String get pleaseSpecify;

  /// No description provided for @keepAppointment.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keepAppointment;

  /// No description provided for @rescheduleAppointmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Reschedule Appointment'**
  String get rescheduleAppointmentTitle;

  /// No description provided for @cannotReschedule.
  ///
  /// In en, this message translates to:
  /// **'Cannot Reschedule'**
  String get cannotReschedule;

  /// No description provided for @reschedulePolicyMessage.
  ///
  /// In en, this message translates to:
  /// **'Appointments can only be rescheduled at least 24 hours before the scheduled time.'**
  String get reschedulePolicyMessage;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @currentAppointment.
  ///
  /// In en, this message translates to:
  /// **'Current Appointment'**
  String get currentAppointment;

  /// No description provided for @reasonForReschedule.
  ///
  /// In en, this message translates to:
  /// **'Reason for Reschedule'**
  String get reasonForReschedule;

  /// No description provided for @pleaseProvideReason.
  ///
  /// In en, this message translates to:
  /// **'Please provide a reason...'**
  String get pleaseProvideReason;

  /// No description provided for @confirmReschedule.
  ///
  /// In en, this message translates to:
  /// **'Confirm Reschedule'**
  String get confirmReschedule;

  /// No description provided for @rescheduleSuccess.
  ///
  /// In en, this message translates to:
  /// **'Appointment rescheduled successfully'**
  String get rescheduleSuccess;

  /// No description provided for @selectNewDate.
  ///
  /// In en, this message translates to:
  /// **'Select New Date'**
  String get selectNewDate;

  /// No description provided for @selectNewTime.
  ///
  /// In en, this message translates to:
  /// **'Select New Time'**
  String get selectNewTime;

  /// No description provided for @doctorBioAmandaWhite.
  ///
  /// In en, this message translates to:
  /// **'Dr. Amanda White provides medication management and pharmaceutical care consultations.'**
  String get doctorBioAmandaWhite;

  /// No description provided for @doctorBioLisaBrown.
  ///
  /// In en, this message translates to:
  /// **'Dr. Lisa Brown provides counseling for anxiety, depression, and stress management for university students.'**
  String get doctorBioLisaBrown;

  /// No description provided for @doctorBioJamesWilson.
  ///
  /// In en, this message translates to:
  /// **'Dr. James Wilson is an orthodontist specializing in braces and teeth alignment for students.'**
  String get doctorBioJamesWilson;

  /// No description provided for @doctorBioRobertTaylor.
  ///
  /// In en, this message translates to:
  /// **'Dr. Robert Taylor specializes in academic stress, relationships, and personal development counseling.'**
  String get doctorBioRobertTaylor;

  /// No description provided for @doctorBioDavidLee.
  ///
  /// In en, this message translates to:
  /// **'Dr. David Lee specializes in drug interactions and medication optimization for complex cases.'**
  String get doctorBioDavidLee;

  /// No description provided for @doctorBioSarahJohnson.
  ///
  /// In en, this message translates to:
  /// **'Dr. Sarah Johnson specializes in internal medicine with over 10 years of experience in treating chronic conditions.'**
  String get doctorBioSarahJohnson;

  /// No description provided for @doctorBioEmilyDavis.
  ///
  /// In en, this message translates to:
  /// **'Dr. Emily Davis offers comprehensive dental care, including preventive, restorative, and cosmetic dentistry.'**
  String get doctorBioEmilyDavis;

  /// No description provided for @doctorBioMichaelChen.
  ///
  /// In en, this message translates to:
  /// **'Dr. Michael Chen provides comprehensive family medicine care for patients of all ages.'**
  String get doctorBioMichaelChen;

  /// No description provided for @developerTesting.
  ///
  /// In en, this message translates to:
  /// **'Developer Testing'**
  String get developerTesting;

  /// No description provided for @scheduleTestNotification.
  ///
  /// In en, this message translates to:
  /// **'Schedule Test Notification (30s)'**
  String get scheduleTestNotification;

  /// No description provided for @testNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'This is a test notification to verify the system is working!'**
  String get testNotificationBody;

  /// No description provided for @scheduledTestNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Test Notification'**
  String get scheduledTestNotificationTitle;

  /// No description provided for @scheduledTestNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'This notification was scheduled 30 seconds ago.'**
  String get scheduledTestNotificationBody;

  /// No description provided for @testNotificationScheduled.
  ///
  /// In en, this message translates to:
  /// **'Notification scheduled for 30 seconds from now!'**
  String get testNotificationScheduled;

  /// No description provided for @pleaseLoginFirst.
  ///
  /// In en, this message translates to:
  /// **'Please login first'**
  String get pleaseLoginFirst;

  /// No description provided for @testNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Test Notification 🔔'**
  String get testNotificationTitle;

  /// No description provided for @checkEmail.
  ///
  /// In en, this message translates to:
  /// **'Check Your Email'**
  String get checkEmail;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Login'**
  String get backToLogin;

  /// No description provided for @resetEmailSentMessage.
  ///
  /// In en, this message translates to:
  /// **'We have sent a password reset link to {email}'**
  String resetEmailSentMessage(String email);

  /// No description provided for @enterEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get enterEmailHint;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get sendResetLink;

  /// No description provided for @resetPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send you a link to reset your password'**
  String get resetPasswordSubtitle;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue to {appName}'**
  String loginSubtitle(String appName);

  /// No description provided for @enterPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterPasswordHint;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get or;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'ku'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'ku':
      return AppLocalizationsKu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

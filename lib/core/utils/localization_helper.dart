import '../../l10n/app_localizations.dart';
import '../../data/models/appointment_model.dart';

/// Helper class to translate dynamic content like department names and qualifications
class LocalizationHelper {
  /// Translate department/specialty name from English to current locale
  static String translateDepartment(String englishName, AppLocalizations l10n) {
    final Map<String, String> translations = {
      // Departments
      'General': l10n.general,
      'General Medicine': l10n.generalMedicine,
      'Dentistry': l10n.dentistry,
      'Psychology': l10n.psychology,
      'Pharmacy': l10n.pharmacy,
      'Laboratory': l10n.laboratory,
      'First Aid': l10n.firstAid,
      'Dermatology': l10n.dermatology,
      'Ophthalmology': l10n.ophthalmology,
      'Orthopedics': l10n.orthopedics,
      'Cardiology': l10n.cardiology,
      'Neurology': l10n.neurology,
      'Pediatrics': l10n.pediatrics,
      'Clinical Pharmacy': l10n.clinicalPharmacy,
      'Clinical Psychology': l10n.clinicalPsychology,
      'Orthodontics': l10n.orthodontics,
      'Counseling': l10n.counseling,
      // Additional specialties
      'Internal Medicine': l10n.internalMedicine,
      'General Dentistry': l10n.generalDentistry,
      'Family Medicine': l10n.familyMedicine,
    };

    final translatedName = translations[englishName];
    if (translatedName != null) return translatedName;

    // DepartmentModel stores camelCase keys; older appointments store names.
    // Only recognize known catalog keys, leaving custom values untouched.
    for (final entry in translations.entries) {
      final words = entry.key.split(' ');
      final key = words.first.toLowerCase() + words.skip(1).join();
      if (englishName == key) return entry.value;
    }
    return englishName;
  }

  static String translateAppointmentType(
    AppointmentType type,
    AppLocalizations l10n,
  ) {
    return switch (type) {
      AppointmentType.regularCheckup => l10n.regularVisit,
      AppointmentType.followUp => l10n.followUp,
      AppointmentType.consultation => l10n.consultation,
      AppointmentType.emergency => l10n.emergency,
    };
  }

  /// Translate qualification/certification from English to current locale
  static String translateQualification(
    String englishName,
    AppLocalizations l10n,
  ) {
    final Map<String, String> translations = {
      // Common qualifications and degrees
      'MD': l10n.mdDegree,
      'PhD': l10n.phdDegree,
      'PharmD': l10n.pharmDDegree,
      'DDS': l10n.ddsDegree,
      'PsyD': l10n.psyDDegree,
      'Board Certified': l10n.boardCertified,
      'Board Certified Pharmacotherapy': l10n.boardCertifiedPharmacotherapy,
      'Licensed Therapist': l10n.licensedTherapist,
      'Licensed Psychologist': l10n.licensedPsychologist,
      'Licensed Counselor': l10n.licensedCounselor,
      'PhD Clinical Psychology': l10n.phdClinicalPsychology,
      'Certified Orthodontist': l10n.certifiedOrthodontist,
      'Fellowship': l10n.fellowship,
      'Residency': l10n.residency,
      // New qualifications from doctor profiles
      'Board Certified Internal Medicine': l10n.boardCertifiedInternalMedicine,
      'MS Orthodontics': l10n.msOrthodontics,
      'PhD Pharmacology': l10n.phdPharmacology,
      'Certified in Invisalign': l10n.certifiedInInvisalign,
      'Family Medicine Specialist': l10n.familyMedicineSpecialist,
      'Board Certified Cardiovascular Disease':
          l10n.boardCertifiedCardiovascularDisease,
      'FACC': l10n.facc,
      'Board Certified Cardiology': l10n.boardCertifiedCardiology,
    };

    return translations[englishName] ?? englishName;
  }

  /// Format experience years with localization
  static String formatExperience(int years, AppLocalizations l10n) {
    return '$years ${l10n.yearsExperience}';
  }
}

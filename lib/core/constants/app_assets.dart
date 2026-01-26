/// App asset paths
class AppAssets {
  AppAssets._();

  // Base paths
  static const String _imagesPath = 'assets/images';
  static const String _animationsPath = 'assets/animations';
  static const String _iconsPath = 'assets/icons';

  // Logo
  static const String logo = '$_imagesPath/logo.png';
  static const String logoWhite = '$_imagesPath/logo_white.png';

  // Onboarding
  static const String onboarding1 = '$_animationsPath/booking.json';
  static const String onboarding2 = '$_animationsPath/reminder.json';
  static const String onboarding3 = '$_animationsPath/records.json';

  // Animations
  static const String loadingAnimation = '$_animationsPath/loading.json';
  static const String successAnimation = '$_animationsPath/success.json';
  static const String errorAnimation = '$_animationsPath/error.json';
  static const String emptyAnimation = '$_animationsPath/empty.json';
  static const String doctorAnimation = '$_animationsPath/doctor.json';
  static const String healthAnimation = '$_animationsPath/health.json';

  // Placeholders
  static const String avatarPlaceholder = '$_imagesPath/avatar_placeholder.png';
  static const String doctorPlaceholder = '$_imagesPath/doctor_placeholder.png';

  // Department icons
  static const String generalMedicineIcon = '$_iconsPath/general_medicine.svg';
  static const String dentistryIcon = '$_iconsPath/dentistry.svg';
  static const String psychologyIcon = '$_iconsPath/psychology.svg';
  static const String pharmacyIcon = '$_iconsPath/pharmacy.svg';

  // Misc
  static const String mapPlaceholder = '$_imagesPath/map_placeholder.png';
  static const String healthTipPlaceholder = '$_imagesPath/health_tip.png';
}

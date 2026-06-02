/// Granular admin permissions for RBAC
///
/// Super Admin bypasses all permission checks (full access).
/// Admin users have a permissions map that controls what they can see and do.
class AdminPermissions {
  // User management
  final bool usersView;
  final bool usersManageNonAdmin;

  // Doctor management
  final bool doctorsView;
  final bool doctorsManage;

  // Department management
  final bool departmentsView;
  final bool departmentsManage;

  // Analytics
  final bool appointmentsView;
  final bool appointmentsManage;

  // Analytics
  final bool analyticsView;

  // Reports
  final bool reportsView;
  final bool reportsExport;

  // Notifications
  final bool notificationsSend;

  const AdminPermissions({
    this.usersView = false,
    this.usersManageNonAdmin = false,
    this.doctorsView = false,
    this.doctorsManage = false,
    this.departmentsView = false,
    this.departmentsManage = false,
    this.appointmentsView = false,
    this.appointmentsManage = false,
    this.analyticsView = false,
    this.reportsView = false,
    this.reportsExport = false,
    this.notificationsSend = false,
  });

  /// Full access preset — optional preset for trusted admins
  static const AdminPermissions fullAccess = AdminPermissions(
    usersView: true,
    usersManageNonAdmin: true,
    doctorsView: true,
    doctorsManage: true,
    departmentsView: true,
    departmentsManage: true,
    appointmentsView: false,
    appointmentsManage: false,
    analyticsView: true,
    reportsView: true,
    reportsExport: true,
    notificationsSend: true,
  );

  /// No-access preset — everything disabled
  static const AdminPermissions noAccess = AdminPermissions();

  /// Read-only preset
  static const AdminPermissions readOnly = AdminPermissions(
    usersView: true,
    usersManageNonAdmin: false,
    doctorsView: true,
    doctorsManage: false,
    departmentsView: true,
    departmentsManage: false,
    appointmentsView: false,
    appointmentsManage: false,
    analyticsView: true,
    reportsView: true,
    reportsExport: false,
    notificationsSend: false,
  );

  /// Operations admin preset — day-to-day management without sensitive actions
  static const AdminPermissions operations = AdminPermissions(
    usersView: true,
    usersManageNonAdmin: true,
    doctorsView: true,
    doctorsManage: true,
    departmentsView: true,
    departmentsManage: true,
    appointmentsView: false,
    appointmentsManage: false,
    analyticsView: true,
    reportsView: true,
    reportsExport: false,
    notificationsSend: false,
  );

  factory AdminPermissions.fromMap(Map<String, dynamic>? map) {
    if (map == null) return AdminPermissions.fullAccess;
    return AdminPermissions(
      usersView: map['users.view'] ?? false,
      usersManageNonAdmin: map['users.manageNonAdmin'] ?? false,
      doctorsView: map['doctors.view'] ?? false,
      doctorsManage: map['doctors.manage'] ?? false,
      departmentsView: map['departments.view'] ?? false,
      departmentsManage: map['departments.manage'] ?? false,
      appointmentsView: map['appointments.view'] ?? false,
      appointmentsManage: map['appointments.manage'] ?? false,
      analyticsView: map['analytics.view'] ?? false,
      reportsView: map['reports.view'] ?? false,
      reportsExport: map['reports.export'] ?? false,
      notificationsSend: map['notifications.send'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'users.view': usersView,
      'users.manageNonAdmin': usersManageNonAdmin,
      'doctors.view': doctorsView,
      'doctors.manage': doctorsManage,
      'departments.view': departmentsView,
      'departments.manage': departmentsManage,
      'appointments.view': appointmentsView,
      'appointments.manage': appointmentsManage,
      'analytics.view': analyticsView,
      'reports.view': reportsView,
      'reports.export': reportsExport,
      'notifications.send': notificationsSend,
    };
  }

  AdminPermissions copyWith({
    bool? usersView,
    bool? usersManageNonAdmin,
    bool? doctorsView,
    bool? doctorsManage,
    bool? departmentsView,
    bool? departmentsManage,
    bool? appointmentsView,
    bool? appointmentsManage,
    bool? analyticsView,
    bool? reportsView,
    bool? reportsExport,
    bool? notificationsSend,
  }) {
    return AdminPermissions(
      usersView: usersView ?? this.usersView,
      usersManageNonAdmin: usersManageNonAdmin ?? this.usersManageNonAdmin,
      doctorsView: doctorsView ?? this.doctorsView,
      doctorsManage: doctorsManage ?? this.doctorsManage,
      departmentsView: departmentsView ?? this.departmentsView,
      departmentsManage: departmentsManage ?? this.departmentsManage,
      appointmentsView: appointmentsView ?? this.appointmentsView,
      appointmentsManage: appointmentsManage ?? this.appointmentsManage,
      analyticsView: analyticsView ?? this.analyticsView,
      reportsView: reportsView ?? this.reportsView,
      reportsExport: reportsExport ?? this.reportsExport,
      notificationsSend: notificationsSend ?? this.notificationsSend,
    );
  }

  /// List of all permission keys for iteration in UI
  static const List<String> allKeys = [
    'users.view',
    'users.manageNonAdmin',
    'doctors.view',
    'doctors.manage',
    'departments.view',
    'departments.manage',
    'appointments.view',
    'appointments.manage',
    'analytics.view',
    'reports.view',
    'reports.export',
    'notifications.send',
  ];

  /// Permission keys shown in the Super Admin permissions UI.
  ///
  /// Appointment permissions remain in [allKeys] for backend security checks,
  /// but are hidden until the app has visible admin appointment workflows.
  static const List<String> visibleKeys = [
    'users.view',
    'users.manageNonAdmin',
    'doctors.view',
    'doctors.manage',
    'departments.view',
    'departments.manage',
    'analytics.view',
    'reports.view',
    'reports.export',
    'notifications.send',
  ];

  /// Human-readable labels for permission keys
  static const Map<String, String> labels = {
    'users.view': 'View Users',
    'users.manageNonAdmin': 'Manage Non-Admin Users',
    'doctors.view': 'View Doctors',
    'doctors.manage': 'Manage Doctors',
    'departments.view': 'View Departments',
    'departments.manage': 'Manage Departments',
    'appointments.view': 'View Appointments',
    'appointments.manage': 'Manage Appointments',
    'analytics.view': 'View Analytics',
    'reports.view': 'View Reports',
    'reports.export': 'Export Reports',
    'notifications.send': 'Send Notifications',
  };

  /// Human-readable descriptions for permission keys
  static const Map<String, String> descriptions = {
    'users.view': 'Can view the user list and user details',
    'users.manageNonAdmin':
        'Can create, edit, activate/deactivate non-admin users',
    'doctors.view': 'Can view doctor profiles and schedules',
    'doctors.manage': 'Can create, edit, and delete doctor accounts',
    'departments.view': 'Can view department information',
    'departments.manage': 'Can create, edit, and delete departments',
    'appointments.view': 'Can view appointment records',
    'appointments.manage':
        'Can reschedule, cancel, update, and delete appointments',
    'analytics.view': 'Can view analytics dashboard and statistics',
    'reports.view': 'Can view generated reports',
    'reports.export': 'Can export reports to CSV/PDF',
    'notifications.send': 'Can send push notifications to users',
  };

  /// Get permission value by dot-notation key
  bool getByKey(String key) {
    switch (key) {
      case 'users.view':
        return usersView;
      case 'users.manageNonAdmin':
        return usersManageNonAdmin;
      case 'doctors.view':
        return doctorsView;
      case 'doctors.manage':
        return doctorsManage;
      case 'departments.view':
        return departmentsView;
      case 'departments.manage':
        return departmentsManage;
      case 'appointments.view':
        return appointmentsView;
      case 'appointments.manage':
        return appointmentsManage;
      case 'analytics.view':
        return analyticsView;
      case 'reports.view':
        return reportsView;
      case 'reports.export':
        return reportsExport;
      case 'notifications.send':
        return notificationsSend;
      default:
        return false;
    }
  }

  @override
  String toString() => 'AdminPermissions(${toMap()})';
}

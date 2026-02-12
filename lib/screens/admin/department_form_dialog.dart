import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';

/// All available icon options for departments — organized by category
const Map<String, IconData> departmentIcons = {
  // ── Popular Hospital Departments ──────────────────────────────────────
  'cardiology': Icons.monitor_heart,
  'neurology': Icons.psychology,
  'pediatrics': Icons.child_care,
  'maternity': Icons.pregnant_woman,
  'ophthalmology': Icons.visibility,
  'orthopedics': Icons.accessibility_new,
  'emergency': Icons.emergency,
  'surgery': Icons.content_cut,
  'dermatology': Icons.face,
  'laboratory': Icons.biotech,
  'radiology': Icons.science,
  'pharmacy': Icons.local_pharmacy,
  'physiotherapy': Icons.fitness_center,
  'ent': Icons.hearing,
  'nutrition': Icons.restaurant,
  'dental': Icons.masks,
  'general': Icons.local_hospital,
  'telemedicine': Icons.video_camera_front,
  'administration': Icons.admin_panel_settings,
  'pulmonology': Icons.air,
  'oncology': Icons.coronavirus,
  'gastroenterology': Icons.lunch_dining,
  'urology': Icons.water_drop,
  'nephrology': Icons.opacity,
  'hematology': Icons.bloodtype,
  'psychiatry': Icons.self_improvement,
  'neonatology': Icons.child_friendly,
  'icu': Icons.monitor,
  'pain_management': Icons.healing,
  'pathology': Icons.biotech,
  'allergy': Icons.spa,
  'infectious_disease': Icons.bug_report,
  'endocrinology': Icons.thermostat,
  'burn_unit': Icons.local_fire_department,
  'rehabilitation': Icons.directions_walk,
  'dialysis': Icons.invert_colors,
  'transfusion': Icons.bloodtype,
  'ambulance': Icons.local_shipping,
  'palliative_care': Icons.volunteer_activism,
  'sports_medicine': Icons.sports_gymnastics,
  'sleep_medicine': Icons.nightlight,
  'genetics': Icons.hub,
  'trauma': Icons.personal_injury,
  'wound_care': Icons.healing,
  'geriatrics': Icons.elderly,
  'anesthesiology': Icons.airline_seat_flat,
  'rheumatology': Icons.accessibility,

  // ── Medical & Health ──────────────────────────────────────────────────
  'medical_services': Icons.medical_services,
  'medication': Icons.medication,
  'medication_liquid': Icons.medication_liquid,
  'vaccines': Icons.vaccines,
  'health_and_safety': Icons.health_and_safety,
  'medical_info': Icons.medical_information,
  'emergency_share': Icons.emergency_share,
  'heart_broken': Icons.heart_broken,
  'monitor_heart': Icons.monitor_heart,
  'pill': Icons.medication,

  // ── Body & Care ───────────────────────────────────────────────────────
  'favorite': Icons.favorite,
  'face_2': Icons.face_2,
  'face_3': Icons.face_3,
  'face_retouching': Icons.face_retouching_natural,
  'directions_run': Icons.directions_run,
  'sick': Icons.sick,
  'clean_hands': Icons.clean_hands,
  'baby_changing': Icons.baby_changing_station,
  'wc': Icons.wc,
  'body': Icons.boy,
  'woman': Icons.woman,
  'man': Icons.man,
  'ear': Icons.hearing,
  'eye': Icons.remove_red_eye,
  'brain': Icons.psychology_alt,
  'lungs': Icons.air,
  'bone': Icons.accessibility_new,
  'blood_pressure': Icons.speed,

  // ── Equipment & Facilities ────────────────────────────────────────────
  'sanitizer': Icons.sanitizer,
  'scale': Icons.scale,
  'straighten': Icons.straighten,
  'king_bed': Icons.king_bed,
  'single_bed': Icons.single_bed,
  'wheelchair': Icons.wheelchair_pickup,
  'stethoscope': Icons.medical_services,
  'syringe': Icons.vaccines,
  'device_thermostat': Icons.device_thermostat,
  'monitor_weight': Icons.monitor_weight,
  'bloodmonitor': Icons.monitor_weight,
  'local_laundry': Icons.local_laundry_service,
  'shower': Icons.shower,
  'bathtub': Icons.bathtub,

  // ── Research & Analytics ──────────────────────────────────────────────
  'memory': Icons.memory,
  'analytics': Icons.analytics,
  'insights': Icons.insights,
  'query_stats': Icons.query_stats,
  'data_exploration': Icons.data_exploration,
  'biotech': Icons.biotech,
  'microscope_alt': Icons.science,

  // ── Places & Building ─────────────────────────────────────────────────
  'apartment': Icons.apartment,
  'meeting_room': Icons.meeting_room,
  'storefront': Icons.storefront,
  'home_health': Icons.home,
  'room_service': Icons.room_service,
  'domain': Icons.domain,
  'business': Icons.business,
  'location_city': Icons.location_city,
  'local_hospital_alt': Icons.local_hospital,

  // ── People & Groups ───────────────────────────────────────────────────
  'groups': Icons.groups,
  'diversity_1': Icons.diversity_1,
  'diversity_2': Icons.diversity_2,
  'diversity_3': Icons.diversity_3,
  'person': Icons.person,
  'family_restroom': Icons.family_restroom,
  'people': Icons.people,
  'supervisor_account': Icons.supervisor_account,
  'support_agent': Icons.support_agent,
  'engineering': Icons.engineering,

  // ── General & Symbols ─────────────────────────────────────────────────
  'star': Icons.star,
  'shield': Icons.shield,
  'verified': Icons.verified,
  'lightbulb': Icons.lightbulb,
  'bolt': Icons.bolt,
  'eco': Icons.eco,
  'pets': Icons.pets,
  'palette': Icons.palette,
  'email': Icons.email,
  'call': Icons.call,
  'notifications': Icons.notifications,
  'schedule': Icons.schedule,
  'event': Icons.event,
  'assignment': Icons.assignment,
  'description': Icons.description,
  'receipt_long': Icons.receipt_long,
  'task_alt': Icons.task_alt,
  'check_circle': Icons.check_circle,
  'info': Icons.info,
  'warning': Icons.warning,
  'help': Icons.help,
  'thumb_up': Icons.thumb_up,
  'flag': Icons.flag,
  'bookmark': Icons.bookmark,
  'grade': Icons.grade,
  'extension': Icons.extension,
  'settings': Icons.settings,
  'tune': Icons.tune,
  'build': Icons.build,
  'construction': Icons.construction,
};

/// Quick-pick color palette
const List<String> departmentColors = [
  '#2196F3', // Blue
  '#9C27B0', // Purple
  '#4CAF50', // Green
  '#FF5722', // Deep Orange
  '#FF9800', // Orange
  '#E91E63', // Pink
  '#00BCD4', // Cyan
  '#009688', // Teal
  '#3F51B5', // Indigo
  '#795548', // Brown
  '#607D8B', // Blue Grey
  '#F44336', // Red
];

class DepartmentFormDialog extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? data;

  const DepartmentFormDialog({super.key, this.id, this.data});

  @override
  State<DepartmentFormDialog> createState() => _DepartmentFormDialogState();
}

class _DepartmentFormDialogState extends State<DepartmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  bool _isSubmitting = false;

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late String _selectedIcon;
  late String _selectedColor;

  // Working hours data
  static const List<String> _weekDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final Map<String, bool> _dayEnabled = {};
  final Map<String, TimeOfDay> _dayStart = {};
  final Map<String, TimeOfDay> _dayEnd = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.data?['name'] ?? '');
    _descriptionController = TextEditingController(
      text: widget.data?['description'] ?? '',
    );
    _selectedIcon = widget.data?['iconName'] ?? 'medical_services';
    _selectedColor = widget.data?['colorHex'] ?? '#2196F3';

    // Initialize working hours from Firestore data
    final rawHours =
        widget.data?['workingHours'] as Map<String, dynamic>? ?? {};
    // Is this a new department (no existing data)?
    final isNew = rawHours.isEmpty;

    for (final day in _weekDays) {
      final value = rawHours[day.toLowerCase()];
      if (value is Map) {
        final start = value['start']?.toString() ?? '';
        final end = value['end']?.toString() ?? '';
        // Support both old format (no 'enabled' key = always enabled)
        // and new format (has 'enabled' key)
        final isEnabled = value.containsKey('enabled')
            ? (value['enabled'] == true)
            : (start.isNotEmpty && end.isNotEmpty);
        _dayEnabled[day] = isEnabled;
        _dayStart[day] = start.isNotEmpty
            ? _parseTime(start)
            : const TimeOfDay(hour: 8, minute: 0);
        _dayEnd[day] = end.isNotEmpty
            ? _parseTime(end)
            : const TimeOfDay(hour: 20, minute: 0);
      } else if (value is String && value.contains('-')) {
        // Legacy string format: "08:00 - 20:00"
        final parts = value.split('-').map((s) => s.trim()).toList();
        if (parts.length == 2) {
          _dayEnabled[day] = true;
          _dayStart[day] = _parseTime(parts[0]);
          _dayEnd[day] = _parseTime(parts[1]);
        } else {
          _dayEnabled[day] = false;
          _dayStart[day] = const TimeOfDay(hour: 8, minute: 0);
          _dayEnd[day] = const TimeOfDay(hour: 20, minute: 0);
        }
      } else {
        // Default for new departments: Mon–Fri ON, Sat–Sun OFF
        final isWeekday = day != 'Saturday' && day != 'Sunday';
        _dayEnabled[day] = isNew ? isWeekday : false;
        _dayStart[day] = const TimeOfDay(hour: 8, minute: 0);
        _dayEnd[day] = const TimeOfDay(hour: 20, minute: 0);
      }
    }
  }

  TimeOfDay _parseTime(String s) {
    final parts = s.replaceAll(RegExp(r'[^0-9:]'), '').split(':');
    if (parts.length == 2) {
      return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 8,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }
    return const TimeOfDay(hour: 8, minute: 0);
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  /// Opens a fullscreen dialog to browse and search all icons
  Future<void> _showIconPicker() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _IconPickerDialog(
        selectedIcon: _selectedIcon,
        selectedColor: _hexToColor(_selectedColor),
      ),
    );
    if (result != null) {
      setState(() => _selectedIcon = result);
    }
  }

  /// Opens a color picker dialog
  Future<void> _showColorPicker() async {
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(
        initialColor: _hexToColor(_selectedColor),
      ),
    );
    if (result != null) {
      setState(() => _selectedColor = _colorToHex(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.id != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Department' : 'Add Department'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Department Icon Preview
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color:
                          _hexToColor(_selectedColor).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      departmentIcons[_selectedIcon] ?? Icons.medical_services,
                      size: 40,
                      color: _hexToColor(_selectedColor),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Department Name *',
                    prefixIcon: Icon(Icons.business),
                    hintText: 'e.g., General Medicine',
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Please enter a department name'
                      : null,
                ),
                const SizedBox(height: 12),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description *',
                    prefixIcon: Icon(Icons.description),
                    hintText: 'Brief description of the department',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Please enter a description'
                      : null,
                ),
                const SizedBox(height: 16),

                // Icon Selection Header + Browse Button
                Row(
                  children: [
                    Text(
                      'Department Icon',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showIconPicker,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Browse All'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Show quick-pick icons (first 18 from the map)
                      ...departmentIcons.entries.take(18).map((entry) {
                        final isSelected = _selectedIcon == entry.key;
                        return InkWell(
                          onTap: () =>
                              setState(() => _selectedIcon = entry.key),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _hexToColor(_selectedColor)
                                      .withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(
                                      color: _hexToColor(_selectedColor),
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: Icon(
                              entry.value,
                              size: 22,
                              color: isSelected
                                  ? _hexToColor(_selectedColor)
                                  : isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                            ),
                          ),
                        );
                      }),
                      // "More" button at the end
                      InkWell(
                        onTap: _showIconPicker,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.more_horiz,
                            size: 22,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Color Selection Header + Custom Color Button
                Row(
                  children: [
                    Text(
                      'Department Color',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showColorPicker,
                      icon: const Icon(Icons.colorize, size: 18),
                      label: const Text('Custom'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...departmentColors.map((colorHex) {
                      final isSelected = _selectedColor == colorHex;
                      final color = _hexToColor(colorHex);
                      return InkWell(
                        onTap: () => setState(() => _selectedColor = colorHex),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: isDark ? Colors.white : Colors.black,
                                    width: 3,
                                  )
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      );
                    }),
                    // Show currently selected custom color if not in preset list
                    if (!departmentColors.contains(_selectedColor))
                      InkWell(
                        onTap: _showColorPicker,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _hexToColor(_selectedColor),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? Colors.white : Colors.black,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _hexToColor(_selectedColor)
                                    .withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    // Custom color picker button
                    InkWell(
                      onTap: _showColorPicker,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isDark ? Colors.grey[600]! : Colors.grey[400]!,
                            width: 2,
                          ),
                          gradient: const SweepGradient(
                            colors: [
                              Colors.red,
                              Colors.orange,
                              Colors.yellow,
                              Colors.green,
                              Colors.blue,
                              Colors.purple,
                              Colors.red,
                            ],
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[900] : Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add,
                              size: 12,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Working Hours
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  shape: const RoundedRectangleBorder(side: BorderSide.none),
                  collapsedShape:
                      const RoundedRectangleBorder(side: BorderSide.none),
                  title: Text(
                    'Working Hours',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'Set open/close times per day',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                  children: _weekDays.map((day) {
                    final enabled = _dayEnabled[day] ?? false;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            height: 30,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Switch(
                                value: enabled,
                                onChanged: (v) =>
                                    setState(() => _dayEnabled[day] = v),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 50,
                            child: Text(
                              day.substring(0, 3),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: enabled
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark
                                        ? Colors.grey[600]
                                        : Colors.grey[400]),
                              ),
                            ),
                          ),
                          if (enabled) ...[
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: _dayStart[day]!,
                                    helpText: '$day — Start Time',
                                  );
                                  if (t != null) {
                                    setState(() => _dayStart[day] = t);
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.grey[700]!
                                          : Colors.grey[300]!,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _formatTime(_dayStart[day]!),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text('–',
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.grey[500]
                                          : Colors.grey[600])),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: _dayEnd[day]!,
                                    helpText: '$day — End Time',
                                  );
                                  if (t != null) {
                                    setState(() => _dayEnd[day] = t);
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.grey[700]!
                                          : Colors.grey[300]!,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _formatTime(_dayEnd[day]!),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ),
                            ),
                          ] else
                            Expanded(
                              child: Text(
                                'Closed',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[400],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  isEditing ? 'Update' : 'Create',
                  style: const TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      // Build working hours map — save ALL days to preserve times
      final workingHours = <String, dynamic>{};
      for (final day in _weekDays) {
        workingHours[day.toLowerCase()] = {
          'start': _formatTime(_dayStart[day]!),
          'end': _formatTime(_dayEnd[day]!),
          'enabled': _dayEnabled[day] == true,
        };
      }

      // Generate key from name
      final name = _nameController.text.trim();
      final words = name.split(' ');
      final key = words.first.toLowerCase() +
          words
              .skip(1)
              .map((w) => w.isNotEmpty
                  ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
                  : '')
              .join('');

      final data = {
        'key': key,
        'name': name,
        'description': _descriptionController.text.trim(),
        'iconName': _selectedIcon,
        'colorHex': _selectedColor,
        'workingHours': workingHours,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      if (widget.id != null) {
        // Update existing department
        await _firestore.collection('departments').doc(widget.id).update(data);
      } else {
        // Create new department
        data['isActive'] = true;
        data['doctorCount'] = 0;
        data['createdAt'] = Timestamp.fromDate(DateTime.now());
        await _firestore.collection('departments').add(data);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.id != null
                  ? 'Department updated successfully'
                  : 'Department created successfully',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

// =============================================================================
// Icon Picker Dialog — searchable fullscreen dialog with all icons
// =============================================================================
class _IconPickerDialog extends StatefulWidget {
  final String selectedIcon;
  final Color selectedColor;

  const _IconPickerDialog({
    required this.selectedIcon,
    required this.selectedColor,
  });

  @override
  State<_IconPickerDialog> createState() => _IconPickerDialogState();
}

class _IconPickerDialogState extends State<_IconPickerDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<MapEntry<String, IconData>> get _filteredIcons {
    if (_searchQuery.isEmpty) return departmentIcons.entries.toList();
    return departmentIcons.entries
        .where((e) => e.key.replaceAll('_', ' ').contains(_searchQuery))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Text(
                  'Choose Icon',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search field
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search icons...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
            const SizedBox(height: 8),

            // Results count
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${_filteredIcons.length} icons',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ),

            // Icon grid
            Expanded(
              child: _filteredIcons.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No icons found',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: _filteredIcons.length,
                      itemBuilder: (context, index) {
                        final entry = _filteredIcons[index];
                        final isSelected = widget.selectedIcon == entry.key;
                        return Tooltip(
                          message: entry.key.replaceAll('_', ' '),
                          child: InkWell(
                            onTap: () => Navigator.pop(context, entry.key),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? widget.selectedColor
                                        .withValues(alpha: 0.2)
                                    : isDark
                                        ? Colors.grey[800]
                                        : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: isSelected
                                    ? Border.all(
                                        color: widget.selectedColor,
                                        width: 2,
                                      )
                                    : null,
                              ),
                              child: Icon(
                                entry.value,
                                size: 28,
                                color: isSelected
                                    ? widget.selectedColor
                                    : isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[700],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Color Picker Dialog — HSL color wheel + hex input
// =============================================================================
class _ColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _ColorPickerDialog({required this.initialColor});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _lightness;
  late TextEditingController _hexController;

  // Cached values to avoid recalculation on every build
  late Color _cachedColor;
  late String _cachedHex;
  late LinearGradient _satGradient;
  late LinearGradient _lightGradient;

  @override
  void initState() {
    super.initState();
    final hsl = HSLColor.fromColor(widget.initialColor);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
    _recomputeCache();
    _hexController = TextEditingController(text: _cachedHex);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  /// Recompute all cached values at once
  void _recomputeCache() {
    _cachedColor =
        HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness).toColor();
    _cachedHex =
        '#${_cachedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    _satGradient = LinearGradient(
      colors: [
        HSLColor.fromAHSL(1, _hue, 0, _lightness).toColor(),
        HSLColor.fromAHSL(1, _hue, 1, _lightness).toColor(),
      ],
    );
    _lightGradient = LinearGradient(
      colors: [
        Colors.black,
        HSLColor.fromAHSL(1, _hue, _saturation, 0.5).toColor(),
        Colors.white,
      ],
    );
  }

  void _setHSL({double? h, double? s, double? l}) {
    setState(() {
      if (h != null) _hue = h;
      if (s != null) _saturation = s;
      if (l != null) _lightness = l;
      _recomputeCache();
    });
  }

  void _syncHexField() {
    _hexController.text = _cachedHex;
  }

  void _onHexSubmitted(String value) {
    var hex = value.trim().replaceAll('#', '');
    if (hex.length == 6) {
      try {
        final color = Color(int.parse('FF$hex', radix: 16));
        final hsl = HSLColor.fromColor(color);
        setState(() {
          _hue = hsl.hue;
          _saturation = hsl.saturation;
          _lightness = hsl.lightness;
          _recomputeCache();
          _hexController.text = '#${hex.toUpperCase()}';
        });
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Pick a Color'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Color preview
              Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: _cachedColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    _cachedHex,
                    style: TextStyle(
                      color: _lightness > 0.5 ? Colors.black87 : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Hue slider
              _buildSliderRow(
                'Hue',
                _hue,
                0,
                360,
                onChanged: (v) => _setHSL(h: v),
                onChangeEnd: (_) => _syncHexField(),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                ),
                isDark: isDark,
              ),

              // Saturation slider
              _buildSliderRow(
                'Saturation',
                _saturation,
                0,
                1,
                onChanged: (v) => _setHSL(s: v),
                onChangeEnd: (_) => _syncHexField(),
                gradient: _satGradient,
                isDark: isDark,
              ),

              // Lightness slider
              _buildSliderRow(
                'Lightness',
                _lightness,
                0,
                1,
                onChanged: (v) => _setHSL(l: v),
                onChangeEnd: (_) => _syncHexField(),
                gradient: _lightGradient,
                isDark: isDark,
              ),

              const SizedBox(height: 16),

              // Hex input
              Row(
                children: [
                  Text(
                    'HEX',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      onSubmitted: _onHexSubmitted,
                      onChanged: (v) {
                        if (v.replaceAll('#', '').length == 6) {
                          _onHexSubmitted(v);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: '#FF5722',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Quick color presets
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: departmentColors.map((hex) {
                  final color = Color(
                      int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
                  return InkWell(
                    onTap: () {
                      final hsl = HSLColor.fromColor(color);
                      _setHSL(h: hsl.hue, s: hsl.saturation, l: hsl.lightness);
                      _syncHexField();
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _cachedColor),
          style: ElevatedButton.styleFrom(
            backgroundColor: _cachedColor,
            foregroundColor: _lightness > 0.5 ? Colors.black : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Select Color'),
        ),
      ],
    );
  }

  static final _trackShape = _FullWidthTrackShape();

  Widget _buildSliderRow(
    String label,
    double value,
    double min,
    double max, {
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    required Gradient gradient,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: gradient,
            ),
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 32,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 14,
                ),
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                trackShape: _trackShape,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom track shape that fills the full width
class _FullWidthTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';
import '../../data/models/user_model.dart';
import '../../l10n/app_localizations.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bloodTypeController = TextEditingController();
  final _allergiesController = TextEditingController();

  XFile? _selectedImage;
  Uint8List? _webImageBytes; // For Web Preview
  bool _isPhotoRemoved = false; // New state to track removal
  DateTime? _dateOfBirth;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.user;
    if (user != null) {
      _fullNameController.text = user.fullName;
      _phoneController.text = user.phoneNumber ?? '';
      _bloodTypeController.text = user.bloodType ?? '';
      _allergiesController.text = user.allergies ?? '';
      _dateOfBirth = user.dateOfBirth;
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _selectedImage = pickedFile;
          _webImageBytes = bytes;
          _isPhotoRemoved = false;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).error),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(height: 20),
              Text(
                AppLocalizations.of(context).choosePhoto,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt, color: AppColors.primary),
                ),
                title: Text(AppLocalizations.of(context).takePhoto),
                subtitle: Text(AppLocalizations.of(context).useCamera),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.photo_library,
                    color: AppColors.secondary,
                  ),
                ),
                title: Text(AppLocalizations.of(context).chooseFromGallery),
                subtitle: Text(AppLocalizations.of(context).selectFromLibrary),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_selectedImage != null ||
                  (context.read<AuthProvider>().user?.photoUrl != null &&
                      !_isPhotoRemoved)) // Only show if not already removed
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete, color: AppColors.error),
                  ),
                  title: const Text('Remove Photo'),
                  subtitle: const Text('Delete current profile photo'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedImage = null;
                      _webImageBytes = null;
                      _isPhotoRemoved = true; // Mark as removed
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDateOfBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(2000),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimaryLight,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();

      String? photoUrl;
      if (_webImageBytes != null && _selectedImage != null) {
        final fileName = _selectedImage!.name;
        // Upload image bytes to Firebase Storage
        photoUrl = await authProvider.uploadProfileImageBytes(
          _webImageBytes!,
          fileName,
        );
      } else if (_isPhotoRemoved) {
        photoUrl = ''; // Pass empty string to remove the photo
      }

      await authProvider.updateProfile(
        fullName: _fullNameController.text.trim(),
        phoneNumber: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        dateOfBirth: _dateOfBirth,
        bloodType: _bloodTypeController.text.trim().isEmpty
            ? null
            : _bloodTypeController.text.trim(),
        allergies: _allergiesController.text.trim().isEmpty
            ? null
            : _allergiesController.text.trim(),
        photoUrl: photoUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context).profileUpdated),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    // Determine what to show in the avatar
    Widget avatarContent = _buildAvatarContent(user);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editProfile),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.save),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Profile Photo
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipOval(child: avatarContent),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _showImagePickerOptions,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tapToChangePhoto,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
              ),
              const SizedBox(height: 32),

              // Full Name
              CustomTextField(
                controller: _fullNameController,
                label: l10n.fullName,
                hintText: l10n.enterFullName,
                prefixIcon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.pleaseEnterName;
                  }
                  if (value.trim().length < 2) {
                    return l10n.nameTooShort;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone Number
              CustomTextField(
                controller: _phoneController,
                label: l10n.phoneNumberLabel,
                hintText: l10n.enterPhoneNumber,
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              // Date of Birth
              GestureDetector(
                onTap: _selectDateOfBirth,
                child: AbsorbPointer(
                  child: CustomTextField(
                    controller: TextEditingController(
                      text: _dateOfBirth != null
                          ? _formatDate(_dateOfBirth!)
                          : '',
                    ),
                    label: l10n.dateOfBirth,
                    hintText: l10n.selectDateOfBirth,
                    prefixIcon: Icons.cake_outlined,
                    suffix: const Icon(Icons.calendar_today, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Blood Type
              CustomTextField(
                controller: _bloodTypeController,
                label: l10n.bloodType,
                hintText: l10n.bloodTypeHint,
                prefixIcon: Icons.bloodtype_outlined,
              ),
              const SizedBox(height: 16),

              // Allergies
              CustomTextField(
                controller: _allergiesController,
                label: l10n.allergies,
                hintText: l10n.allergiesHint,
                prefixIcon: Icons.warning_amber_outlined,
                maxLines: 3,
              ),
              const SizedBox(height: 32),

              // Save Button
              PrimaryButton(
                text: l10n.saveChanges,
                onPressed: _saveProfile,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 16),

              // Email (read-only info)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDark
                      : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.emailAddress,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                    ),
                          ),
                          Text(
                            user?.email ?? l10n.notAvailable,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Google Account (linked info)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDark
                      : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.read<AuthProvider>().isGoogleLinked
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        context.read<AuthProvider>().isGoogleLinked
                            ? Icons.check_circle_rounded
                            : Icons.link_off_rounded,
                        color: context.read<AuthProvider>().isGoogleLinked
                            ? AppColors.success
                            : AppColors.warning,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Google Account',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                    ),
                          ),
                          const SizedBox(height: 2),
                          if (context.read<AuthProvider>().isGoogleLinked)
                            Text(
                              context.read<AuthProvider>().googleEmail ??
                                  'Linked',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            )
                          else
                            Text(
                              'Not linked',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    if (!context.read<AuthProvider>().isGoogleLinked)
                      TextButton(
                        onPressed: () async {
                          final authProvider = context.read<AuthProvider>();
                          final success = await authProvider.linkWithGoogle();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? 'Google account linked!'
                                    : authProvider.errorMessage ??
                                        'Failed to link',
                              ),
                              backgroundColor:
                                  success ? AppColors.success : AppColors.error,
                            ),
                          );
                          if (success) setState(() {});
                        },
                        child: const Text('Link Now'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarContent(UserModel? user) {
    // 1. New Image Selected
    if (_webImageBytes != null) {
      return Image.memory(
        _webImageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(user),
      );
    }

    // 2. Image Removed
    if (_isPhotoRemoved) {
      return _buildDefaultAvatar(user);
    }

    // 3. Existing Network URL
    if (user?.photoUrl != null && user!.photoUrl!.isNotEmpty) {
      return Image.network(
        user.photoUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: AppColors.backgroundLight,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(user),
      );
    }

    // 4. No Image (Default)
    return _buildDefaultAvatar(user);
  }

  Widget _buildDefaultAvatar(UserModel? user) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.1),
      child: Center(
        child: Text(
          user?.fullName.isNotEmpty == true
              ? user!.fullName[0].toUpperCase()
              : '?',
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

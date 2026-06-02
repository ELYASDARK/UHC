import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart'; // Added
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/local_notification_service.dart';
import '../data/models/user_model.dart';

/// Authentication state
enum AuthState { initial, loading, authenticated, unauthenticated, error }

/// Authentication provider for state management
class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthState _state = AuthState.initial;
  UserModel? _currentUser;
  String? _errorMessage;
  bool _skipNextAuthStateUserLoad = false;
  bool _receivedInitialAuthState = false;

  AuthState get state => _state;
  UserModel? get currentUser => _currentUser;
  UserModel? get user => _currentUser; // Alias for convenience
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isLoading => _state == AuthState.loading;
  User? get firebaseUser => _authService.currentUser;

  AuthProvider() {
    _init();
  }

  /// Initialize and listen to auth state changes
  void _init() {
    _authService.authStateChanges.listen((user) async {
      _receivedInitialAuthState = true;
      if (user != null) {
        if (_skipNextAuthStateUserLoad) {
          _skipNextAuthStateUserLoad = false;
          return;
        }
        await _loadUserData(user.uid);
      } else {
        _state = AuthState.unauthenticated;
        _currentUser = null;
        notifyListeners();
      }
    });

    Timer(const Duration(seconds: 2), () {
      if (_receivedInitialAuthState || _state != AuthState.initial) return;

      final user = _authService.currentUser;
      if (user != null) {
        _loadUserData(user.uid);
      } else {
        _state = AuthState.unauthenticated;
        _currentUser = null;
        notifyListeners();
      }
    });
  }

  /// Guard against stale async auth loads finishing after sign-out/switch-user.
  bool _isStaleAuthLoad(String uid) {
    final currentFirebaseUser = _authService.currentUser;
    return currentFirebaseUser == null || currentFirebaseUser.uid != uid;
  }

  /// Load user data from Firestore
  Future<void> _loadUserData(String uid) async {
    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      _currentUser = await _authService.getUserData(uid);

      if (_isStaleAuthLoad(uid)) {
        return;
      }

      if (_currentUser == null) {
        // Profile doc is missing for this auth UID.
        // Sign out to avoid falling back into a wrong shell.
        await _authService.signOut();
        _state = AuthState.error;
        _errorMessage =
            'Account profile not found for this login. Please ask admin to create users/$uid with your role.';
        notifyListeners();
        return;
      }

      // Check if user is active
      if (!_currentUser!.isActive) {
        // User is deactivated - sign them out
        await _authService.signOut();
        _currentUser = null;
        _state = AuthState.error;
        _errorMessage =
            'Your account has been deactivated. Please contact support.';
        notifyListeners();
        return;
      }

      _state = AuthState.authenticated;
    } catch (e) {
      if (_isStaleAuthLoad(uid)) {
        return;
      }
      _state = AuthState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Sign in with email and password
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      // Prevent duplicate _loadUserData() from the immediate authStateChanges event.
      _skipNextAuthStateUserLoad = true;
      final credential = await _authService.signInWithEmail(
        email: email,
        password: password,
      );

      await _loadUserData(credential.user!.uid);

      // Check if login was blocked due to deactivation
      if (_state == AuthState.error) {
        return false;
      }

      return true;
    } catch (e) {
      _skipNextAuthStateUserLoad = false;
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Register with email and password
  Future<bool> registerWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    DateTime? dateOfBirth,
  }) async {
    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      // Prevent duplicate _loadUserData() from the immediate authStateChanges event.
      _skipNextAuthStateUserLoad = true;
      final credential = await _authService.registerWithEmail(
        email: email,
        password: password,
        fullName: fullName,
        phoneNumber: phoneNumber,
        dateOfBirth: dateOfBirth,
      );

      await _loadUserData(credential.user!.uid);
      return true;
    } catch (e) {
      _skipNextAuthStateUserLoad = false;
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      // Prevent duplicate _loadUserData() from the immediate authStateChanges event.
      _skipNextAuthStateUserLoad = true;
      final credential = await _authService.signInWithGoogle();

      if (credential?.user != null) {
        await _loadUserData(credential!.user!.uid);

        // Check if login was blocked due to deactivation
        if (_state == AuthState.error) {
          return false;
        }

        return true;
      } else {
        _skipNextAuthStateUserLoad = false;
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _skipNextAuthStateUserLoad = false;
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Whether the current user has a Google provider linked and synced server-side.
  bool get isGoogleLinked =>
      _authService.isGoogleLinked &&
      (_currentUser?.googleEmail?.trim().isNotEmpty ?? false);

  /// Whether the current user has an email/password provider linked
  bool get isPasswordLinked => _authService.isPasswordLinked;

  /// The linked Google email (from Firestore or Firebase Auth fallback)
  String? get googleEmail =>
      _currentUser?.googleEmail ?? _authService.googleEmail;

  /// Link the current user's account with Google
  Future<bool> linkWithGoogle() async {
    try {
      _errorMessage = null;
      await _authService.linkWithGoogle();

      // Reload Firebase Auth user so providerData reflects the new link
      await _authService.currentUser?.reload();

      // Refresh user data to pick up updated photo, etc.
      if (_currentUser != null) {
        await _refreshUserData(_currentUser!.id);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Unlink the current user's account from Google (admin/super-admin only)
  Future<bool> unlinkGoogle() async {
    try {
      _errorMessage = null;

      if (_currentUser == null) {
        throw Exception('No user logged in.');
      }
      if (!_currentUser!.isAdminOrSuperAdmin) {
        throw Exception('Only admin and super admin can unlink Google.');
      }

      await _authService.unlinkGoogle();

      // Refresh user data after unlink.
      await _refreshUserData(_currentUser!.id);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      _errorMessage = null;

      await _authService.sendPasswordResetEmail(email);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Change password
  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      // Note: We don't set global loading state here to prevent
      // navigation disruption (since isAuthenticated checks state).
      // The UI should handle its own loading indicator.

      await _authService.changePassword(currentPassword, newPassword);
      return true;
    } catch (e) {
      // Just return false/throw so UI can show error
      debugPrint('Change password error: $e');
      rethrow;
    }
  }

  /// Complete the one-time password change required for admin-created accounts.
  Future<bool> completeInitialPasswordChange(String newPassword) async {
    try {
      _errorMessage = null;
      await _authService.completeInitialPasswordChange(newPassword);
      if (_currentUser != null) {
        await _refreshUserData(_currentUser!.id);
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      debugPrint('Initial password change error: $e');
      return false;
    }
  }

  /// Refresh user data without triggering loading state
  Future<void> _refreshUserData(String uid) async {
    try {
      final user = await _authService.getUserData(uid);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error refreshing user data: $e');
    }
  }

  /// Update user profile
  Future<bool> updateProfile({
    String? fullName,
    String? phoneNumber,
    String? photoUrl,
    DateTime? dateOfBirth,
    String? bloodType,
    String? allergies,
  }) async {
    if (_currentUser == null) return false;

    try {
      await _authService.updateUserProfile(
        uid: _currentUser!.id,
        fullName: fullName,
        phoneNumber: phoneNumber,
        photoUrl: photoUrl,
        dateOfBirth: dateOfBirth,
        bloodType: bloodType,
        allergies: allergies,
      );

      // Reload user data silently
      await _refreshUserData(_currentUser!.id);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Upload profile image
  Future<String?> uploadProfileImage(XFile imageFile) async {
    if (_currentUser == null) return null;
    try {
      return await _authService.uploadProfileImage(_currentUser!.id, imageFile);
    } catch (e) {
      debugPrint('Error uploading profile image: $e');
      rethrow;
    }
  }

  /// Upload profile image from bytes
  Future<String?> uploadProfileImageBytes(
    Uint8List imageBytes,
    String fileName,
  ) async {
    if (_currentUser == null) return null;
    try {
      return await _authService.uploadProfileImageBytes(
        _currentUser!.id,
        imageBytes,
        fileName,
      );
    } catch (e) {
      debugPrint('Error uploading profile image bytes: $e');
      rethrow;
    }
  }

  /// Update notification preferences
  Future<bool> updateNotificationPreferences(
    Map<String, dynamic> settings,
  ) async {
    if (_currentUser == null) return false;

    try {
      // Merge with existing settings
      final currentSettings = _currentUser!.notificationSettings ?? {};
      final newSettings = {...currentSettings, ...settings};

      await _authService.updateNotificationSettings(
        _currentUser!.id,
        newSettings,
      );

      // Reload user data silently
      await _refreshUserData(_currentUser!.id);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update user language preference
  Future<bool> updateLanguage(String languageCode) async {
    if (_currentUser == null) return false;

    try {
      await _authService.updateUserLanguage(_currentUser!.id, languageCode);
      _currentUser = _currentUser!.copyWith(language: languageCode);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update user theme preference
  Future<bool> updateThemeMode(String themeMode) async {
    if (_currentUser == null) return false;

    try {
      await _authService.updateUserThemeMode(_currentUser!.id, themeMode);
      _currentUser = _currentUser!.copyWith(themeMode: themeMode);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Sign out
  Future<void> signOut({
    Future<void> Function(String userId)? beforeSignOut,
  }) async {
    _errorMessage = null;
    final previousUser = _currentUser;
    final previousState = _state;

    if (previousUser != null) {
      var notificationProviderCleanedUp = false;
      if (beforeSignOut != null) {
        try {
          await beforeSignOut(previousUser.id);
          notificationProviderCleanedUp = true;
        } catch (e) {
          debugPrint(
              'Notification provider cleanup before sign out failed: $e');
        }
      }

      if (!notificationProviderCleanedUp) {
        await _cleanupNotificationSession(previousUser);
      }
    }

    // Clear local state before FirebaseAuth.signOut() so role-scoped Firestore
    // streams are disposed while the user still has permissions.
    _currentUser = null;
    _state = AuthState.unauthenticated;
    notifyListeners();

    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
      _currentUser = previousUser;
      _state = previousState;
      _errorMessage = 'Sign out failed. Please try again.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _cleanupNotificationSession(UserModel user) async {
    try {
      await FCMService().unsubscribeUserFromTopics(
        user.id,
        role: user.role.name,
      );
    } catch (e) {
      debugPrint('Topic unsubscribe before sign out failed: $e');
    }

    try {
      await FCMService().removeTokenFromDatabase(user.id);
    } catch (e) {
      debugPrint('FCM token cleanup before sign out failed: $e');
    }

    try {
      await LocalNotificationService().cancelAllNotifications();
    } catch (e) {
      debugPrint('Local notification cleanup before sign out failed: $e');
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

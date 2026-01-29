import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart'; // Added
import '../services/auth_service.dart';
import '../data/models/user_model.dart';

/// Authentication state
enum AuthState { initial, loading, authenticated, unauthenticated, error }

/// Authentication provider for state management
class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthState _state = AuthState.initial;
  UserModel? _currentUser;
  String? _errorMessage;

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
      if (user != null) {
        await _loadUserData(user.uid);
      } else {
        _state = AuthState.unauthenticated;
        _currentUser = null;
        notifyListeners();
      }
    });
  }

  /// Load user data from Firestore
  Future<void> _loadUserData(String uid) async {
    try {
      _state = AuthState.loading;
      notifyListeners();

      _currentUser = await _authService.getUserData(uid);
      _state = AuthState.authenticated;
    } catch (e) {
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

      final credential = await _authService.signInWithEmail(
        email: email,
        password: password,
      );

      await _loadUserData(credential.user!.uid);
      return true;
    } catch (e) {
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

      final credential = await _authService.signInWithGoogle();

      if (credential?.user != null) {
        await _loadUserData(credential!.user!.uid);
        return true;
      } else {
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      await _authService.sendPasswordResetEmail(email);

      _state = AuthState.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
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

  /// Sign out
  Future<void> signOut() async {
    await _authService.signOut();
    _currentUser = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

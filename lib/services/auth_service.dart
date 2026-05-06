import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart'; // Added
import 'package:image_picker/image_picker.dart'; // Added
import '../data/models/user_model.dart';

/// Authentication service handling Firebase Auth and Google Sign-In
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance; // Added
  bool _googleInitialized = false;

  static const String _googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Current Firebase user
  User? get currentUser => _auth.currentUser;

  /// Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Register with email and password
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    DateTime? dateOfBirth,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name
      await credential.user?.updateDisplayName(fullName);

      // Create user document in Firestore
      if (credential.user != null) {
        try {
          await _createUserDocument(
            credential.user!,
            fullName,
            phoneNumber: phoneNumber,
            dateOfBirth: dateOfBirth,
          );
        } catch (e) {
          // Roll back the auth user if profile bootstrap fails.
          await credential.user!.delete().catchError((_) {});
          rethrow;
        }
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      UserCredential? userCredential;

      if (kIsWeb) {
        // On web, use Firebase Auth popup directly
        final provider = GoogleAuthProvider();
        userCredential = await _auth.signInWithPopup(provider);
      } else {
        await _ensureGoogleInitializedForMobile();
        // On mobile, use google_sign_in package
        final googleUser = await _googleSignIn.authenticate();

        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        userCredential = await _auth.signInWithCredential(credential);
      }

      final user = userCredential.user!;

      // Check if this user already has an account in Firestore
      // (created by admin or via email/password registration).
      // Google sign-in must NOT create new accounts.
      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        // No account exists — reject this sign-in.
        // Delete the Firebase Auth user that was just created and sign out.
        await user.delete();
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        throw Exception(
          'No account found. Please contact your administrator to create an account.',
        );
      }

      // Account exists — update last login, preserving existing photo.
      await _updateExistingUserDocument(doc, user);

      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw Exception(
          'Google sign-in is not configured for Android. '
          'Please add a Web OAuth client in Firebase Auth, download a fresh android/google-services.json, '
          'and optionally set --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>. '
          'Details: ${e.description ?? e.details ?? e}',
        );
      }
      throw Exception('Google sign-in failed: ${e.description ?? e}');
    } catch (e) {
      // Re-throw our custom "no account" error as-is
      if (e.toString().contains('No account found')) {
        rethrow;
      }
      throw Exception('Google sign-in failed: $e');
    }
  }

  /// Check if current user has Google provider linked
  bool get isGoogleLinked {
    final user = currentUser;
    if (user == null) return false;
    return user.providerData.any((info) => info.providerId == 'google.com');
  }

  /// Check if current user has email/password provider linked
  bool get isPasswordLinked {
    final user = currentUser;
    if (user == null) return false;
    return user.providerData.any((info) => info.providerId == 'password');
  }

  /// Get the linked Google email from Firebase Auth provider data
  String? get googleEmail {
    final user = currentUser;
    if (user == null) return null;
    try {
      final googleInfo = user.providerData.firstWhere(
        (info) => info.providerId == 'google.com',
      );
      return googleInfo.email;
    } catch (_) {
      return null;
    }
  }

  /// Link current user's account with Google
  Future<UserCredential> linkWithGoogle() async {
    final user = currentUser;
    if (user == null) {
      throw Exception('No user logged in');
    }

    try {
      if (kIsWeb) {
        // On web, use Firebase Auth popup for linking
        final provider = GoogleAuthProvider();
        final userCredential = await user.linkWithPopup(provider);

        // Save Google email to Firestore
        if (userCredential.user != null) {
          final googleInfo = userCredential.user!.providerData.firstWhere(
            (info) => info.providerId == 'google.com',
            orElse: () => userCredential.user!.providerData.first,
          );
          await _firestore.collection('users').doc(user.uid).update({
            'updatedAt': Timestamp.fromDate(DateTime.now()),
            'googleEmail': googleInfo.email,
          });
        }
        return userCredential;
      }

      await _ensureGoogleInitializedForMobile();
      // On mobile, use google_sign_in package
      final googleUser = await _googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await user.linkWithCredential(credential);

      if (userCredential.user != null) {
        final googleInfo = userCredential.user!.providerData.firstWhere(
          (info) => info.providerId == 'google.com',
          orElse: () => userCredential.user!.providerData.first,
        );
        await _firestore.collection('users').doc(user.uid).update({
          'updatedAt': Timestamp.fromDate(DateTime.now()),
          'googleEmail': googleInfo.email,
        });
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        throw Exception(
            'This Google account is already linked to another user.');
      } else if (e.code == 'provider-already-linked') {
        throw Exception('A Google account is already linked.');
      }
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Failed to link Google account: $e');
    }
  }

  /// Unlink current user's account from Google
  Future<void> unlinkGoogle() async {
    final user = currentUser;
    if (user == null) {
      throw Exception('No user logged in');
    }

    try {
      final providerIds =
          user.providerData.map((info) => info.providerId).toSet();
      if (!providerIds.contains('google.com')) {
        throw Exception('No Google account is linked.');
      }
      if (providerIds.length <= 1) {
        throw Exception(
          'Cannot unlink Google because it is your only sign-in method.',
        );
      }

      await user.unlink('google.com');
      await user.reload();

      await _firestore.collection('users').doc(user.uid).update({
        'updatedAt': Timestamp.fromDate(DateTime.now()),
        'googleEmail': null,
      });

      if (!kIsWeb) {
        await _ensureGoogleInitializedForMobile();
        try {
          await _googleSignIn.disconnect();
        } catch (_) {
          try {
            await _googleSignIn.signOut();
          } catch (_) {}
        }
      }
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _ensureGoogleInitializedForMobile() async {
    if (kIsWeb || _googleInitialized) return;
    final serverClientId = _googleServerClientId.trim().isEmpty
        ? null
        : _googleServerClientId.trim();
    await _googleSignIn.initialize(serverClientId: serverClientId);
    _googleInitialized = true;
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Change user password
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final user = currentUser;
    if (user == null || user.email == null) {
      throw Exception('No user logged in or user has no email');
    }
    if (!isPasswordLinked) {
      throw Exception(
        'This account is not using email/password sign-in. Password cannot be changed here.',
      );
    }

    try {
      // Create credential with current password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      // Re-authenticate
      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign out
  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Ignore google sign out errors on mobile.
      }
    }

    await _auth.signOut();
    // Verify sign-out deterministically (helps on web where stream timing can vary).
    for (var i = 0; i < 20; i++) {
      final user = _auth.currentUser;
      if (user == null) return;
      try {
        await user.reload();
      } catch (_) {
        // Ignore reload errors during sign-out verification.
      }
      if (i == 5) {
        // Retry once in case the first call was interrupted by transient state.
        await _auth.signOut();
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (_auth.currentUser != null) {
      throw Exception('Firebase sign-out did not complete.');
    }
  }

  /// Create user document in Firestore
  Future<void> _createUserDocument(
    User user,
    String fullName, {
    String? phoneNumber,
    DateTime? dateOfBirth,
  }) async {
    final callable = _functions.httpsCallable('bootstrapSelfUserDocument');
    await callable.call<Map<String, dynamic>>({
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
    });
  }

  /// Update existing user document on Google sign-in.
  /// Only updates the login timestamp; preserves existing photo.
  Future<void> _updateExistingUserDocument(
    DocumentSnapshot doc,
    User user,
  ) async {
    final existingData = doc.data() as Map<String, dynamic>?;
    final existingPhoto = existingData?['photoUrl'] as String?;

    final updates = <String, dynamic>{
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };

    // Only set photoUrl from Google if the user has no existing photo
    if ((existingPhoto == null || existingPhoto.isEmpty) &&
        user.photoURL != null) {
      updates['photoUrl'] = user.photoURL;
    }

    await _firestore.collection('users').doc(user.uid).update(updates);
  }

  /// Get user data from Firestore
  Future<UserModel?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc);
    }

    // Helpful diagnostic: account exists in Auth but user profile doc ID
    // does not match auth.uid (common when created manually in console).
    final email = currentUser?.email;
    if (email != null && email.isNotEmpty) {
      final emailMatch = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(2)
          .get();
      if (emailMatch.docs.length == 1) {
        final wrongDocId = emailMatch.docs.first.id;
        throw Exception(
          'Profile UID mismatch. Auth UID is "$uid" but Firestore user doc is "$wrongDocId". '
          'Create users/$uid with the same data/role, then remove the old doc.',
        );
      }
      if (emailMatch.docs.length > 1) {
        throw Exception(
          'Multiple Firestore user profiles found for $email. Keep exactly one users/<auth_uid> document.',
        );
      }
    }
    return null;
  }

  /// Update user profile
  Future<void> updateUserProfile({
    required String uid,
    String? fullName,
    String? phoneNumber,
    String? photoUrl,
    DateTime? dateOfBirth,
    String? bloodType,
    String? allergies,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };

    if (fullName != null) updates['fullName'] = fullName;
    if (phoneNumber != null) updates['phoneNumber'] = phoneNumber;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    if (dateOfBirth != null) {
      updates['dateOfBirth'] = Timestamp.fromDate(dateOfBirth);
    }
    if (bloodType != null) updates['bloodType'] = bloodType;
    if (allergies != null) updates['allergies'] = allergies;

    await _firestore.collection('users').doc(uid).update(updates);

    // Update Firebase Auth display name if changed
    if (fullName != null && currentUser != null) {
      await currentUser!.updateDisplayName(fullName);
    }
  }

  /// Upload profile image to Firebase Storage
  Future<String> uploadProfileImage(String uid, XFile imageFile) async {
    try {
      final ref = _storage.ref().child('profile_images').child('$uid.jpg');

      // Use putData for cross-platform compatibility (works on Web & Mobile)
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      final data = await imageFile.readAsBytes();

      await ref.putData(data, metadata);
      final downloadUrl = await ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  /// Upload profile image from bytes (for Web/Optimized flows)
  Future<String> uploadProfileImageBytes(
    String uid,
    Uint8List data,
    String fileName,
  ) async {
    try {
      // Determine content type based on extension or default to jpeg
      final extension = fileName.split('.').last.toLowerCase();
      String contentType = 'image/jpeg';
      if (extension == 'png') contentType = 'image/png';
      if (extension == 'webp') contentType = 'image/webp';

      final ref = _storage
          .ref()
          .child('profile_images')
          .child('$uid.${extension == 'jpg' ? 'jpg' : extension}');

      final metadata = SettableMetadata(contentType: contentType);

      await ref.putData(data, metadata);
      final downloadUrl = await ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload image bytes: $e');
    }
  }

  /// Update user notification settings
  Future<void> updateNotificationSettings(
    String uid,
    Map<String, dynamic> settings,
  ) async {
    await _firestore.collection('users').doc(uid).update({
      'notificationSettings': settings,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'user-not-found':
      case 'wrong-password':
        return 'Incorrect email or password. Please try again.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return e.message ?? 'An error occurred.';
    }
  }
}

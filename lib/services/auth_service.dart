import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart'; // Added
import 'package:image_picker/image_picker.dart'; // Added
import '../data/models/user_model.dart';

/// Authentication service handling Firebase Auth and Google Sign-In
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance; // Added

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
        await _createUserDocument(
          credential.user!,
          fullName,
          phoneNumber: phoneNumber,
          dateOfBirth: dateOfBirth,
        );
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // On web, use Firebase Auth popup directly (no client ID meta tag needed)
        final provider = GoogleAuthProvider();
        final userCredential = await _auth.signInWithPopup(provider);
        if (userCredential.user != null) {
          await _createOrUpdateUserDocument(userCredential.user!);
        }
        return userCredential;
      }

      // On mobile, use google_sign_in package
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null; // User cancelled the sign-in
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        await _createOrUpdateUserDocument(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      throw Exception('Google sign-in failed: $e');
    }
  }

  /// Check if current user has Google provider linked
  bool get isGoogleLinked {
    final user = currentUser;
    if (user == null) return false;
    return user.providerData.any((info) => info.providerId == 'google.com');
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

      // On mobile, use google_sign_in package
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign-in cancelled');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
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
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      // Ignore google sign out errors (common on web if not signed in via google)
      await _auth.signOut();
    }
  }

  /// Create user document in Firestore
  Future<void> _createUserDocument(
    User user,
    String fullName, {
    String? phoneNumber,
    DateTime? dateOfBirth,
  }) async {
    final userModel = UserModel(
      id: user.uid,
      email: user.email ?? '',
      fullName: fullName,
      photoUrl: user.photoURL,
      phoneNumber: phoneNumber,
      dateOfBirth: dateOfBirth,
      role: UserRole.student,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(user.uid)
        .set(userModel.toFirestore());
  }

  /// Create or update user document for Google sign-in
  Future<void> _createOrUpdateUserDocument(User user) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final doc = await docRef.get();

    if (!doc.exists) {
      final userModel = UserModel(
        id: user.uid,
        email: user.email ?? '',
        fullName: user.displayName ?? '',
        photoUrl: user.photoURL,
        role: UserRole.student,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await docRef.set(userModel.toFirestore());
    } else {
      // Update last login
      await docRef.update({
        'updatedAt': Timestamp.fromDate(DateTime.now()),
        'photoUrl': user.photoURL,
      });
    }
  }

  /// Get user data from Firestore
  Future<UserModel?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc);
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
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
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

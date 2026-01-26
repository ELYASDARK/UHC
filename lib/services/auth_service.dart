import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/user_model.dart';

/// Authentication service handling Firebase Auth and Google Sign-In
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
        await _createUserDocument(credential.user!, fullName);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null; // User cancelled the sign-in
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final userCredential = await _auth.signInWithCredential(credential);

      // Create or update user document
      if (userCredential.user != null) {
        await _createOrUpdateUserDocument(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      throw Exception('Google sign-in failed: $e');
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

  /// Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Create user document in Firestore
  Future<void> _createUserDocument(User user, String fullName) async {
    final userModel = UserModel(
      id: user.uid,
      email: user.email ?? '',
      fullName: fullName,
      photoUrl: user.photoURL,
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

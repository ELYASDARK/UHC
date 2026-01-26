import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

/// Repository for user-related Firestore operations
class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'users';

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection(_collection);

  /// Get user by ID
  Future<UserModel?> getUserById(String userId) async {
    final doc = await _usersRef.doc(userId).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc);
    }
    return null;
  }

  /// Create user
  Future<void> createUser(UserModel user) async {
    await _usersRef.doc(user.id).set(user.toFirestore());
  }

  /// Update user
  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    data['updatedAt'] = Timestamp.fromDate(DateTime.now());
    await _usersRef.doc(userId).update(data);
  }

  /// Delete user
  Future<void> deleteUser(String userId) async {
    await _usersRef.doc(userId).delete();
  }

  /// Get all users (admin)
  Future<List<UserModel>> getAllUsers() async {
    final snapshot = await _usersRef.get();
    return snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
  }

  /// Get users by role (admin)
  Future<List<UserModel>> getUsersByRole(UserRole role) async {
    final snapshot = await _usersRef.where('role', isEqualTo: role.name).get();
    return snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
  }

  /// Stream user data for real-time updates
  Stream<UserModel?> streamUser(String userId) {
    return _usersRef.doc(userId).snapshots().map((doc) {
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    });
  }
}

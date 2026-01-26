import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/review_model.dart';

/// Repository for review-related Firestore operations
class ReviewRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'reviews';

  CollectionReference<Map<String, dynamic>> get _reviewsRef =>
      _firestore.collection(_collection);

  /// Get reviews for a doctor
  Future<List<ReviewModel>> getDoctorReviews(
    String doctorId, {
    int limit = 20,
  }) async {
    final snapshot = await _reviewsRef
        .where('doctorId', isEqualTo: doctorId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => ReviewModel.fromFirestore(doc)).toList();
  }

  /// Get user's review for a doctor
  Future<ReviewModel?> getUserReview(String doctorId, String patientId) async {
    final snapshot = await _reviewsRef
        .where('doctorId', isEqualTo: doctorId)
        .where('patientId', isEqualTo: patientId)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      return ReviewModel.fromFirestore(snapshot.docs.first);
    }
    return null;
  }

  /// Create review
  Future<String> createReview(ReviewModel review) async {
    final docRef = await _reviewsRef.add(review.toFirestore());
    await docRef.update({'id': docRef.id});
    return docRef.id;
  }

  /// Update review
  Future<void> updateReview(
    String reviewId,
    double rating,
    String comment,
  ) async {
    await _reviewsRef.doc(reviewId).update({
      'rating': rating,
      'comment': comment,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Delete review
  Future<void> deleteReview(String reviewId) async {
    await _reviewsRef.doc(reviewId).delete();
  }

  /// Get doctor's average rating
  Future<Map<String, dynamic>> getDoctorRatingStats(String doctorId) async {
    final snapshot = await _reviewsRef
        .where('doctorId', isEqualTo: doctorId)
        .get();

    if (snapshot.docs.isEmpty) {
      return {'averageRating': 0.0, 'totalReviews': 0};
    }

    double totalRating = 0;
    for (final doc in snapshot.docs) {
      totalRating += (doc.data()['rating'] as num).toDouble();
    }

    return {
      'averageRating': totalRating / snapshot.docs.length,
      'totalReviews': snapshot.docs.length,
    };
  }

  /// Stream reviews for real-time updates
  Stream<List<ReviewModel>> streamDoctorReviews(String doctorId) {
    return _reviewsRef
        .where('doctorId', isEqualTo: doctorId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ReviewModel.fromFirestore(doc))
              .toList(),
        );
  }
}

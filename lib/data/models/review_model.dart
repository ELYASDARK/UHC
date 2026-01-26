import 'package:cloud_firestore/cloud_firestore.dart';

/// Review model for doctor ratings
class ReviewModel {
  final String id;
  final String doctorId;
  final String patientId;
  final String patientName;
  final String? patientPhotoUrl;
  final String appointmentId;
  final double rating;
  final String? comment;
  final DateTime createdAt;
  final bool isAnonymous;

  ReviewModel({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
    this.patientPhotoUrl,
    required this.appointmentId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.isAnonymous = false,
  });

  factory ReviewModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReviewModel(
      id: doc.id,
      doctorId: data['doctorId'] ?? '',
      patientId: data['patientId'] ?? '',
      patientName: data['patientName'] ?? '',
      patientPhotoUrl: data['patientPhotoUrl'],
      appointmentId: data['appointmentId'] ?? '',
      rating: (data['rating'] ?? 0.0).toDouble(),
      comment: data['comment'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isAnonymous: data['isAnonymous'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'doctorId': doctorId,
      'patientId': patientId,
      'patientName': patientName,
      'patientPhotoUrl': patientPhotoUrl,
      'appointmentId': appointmentId,
      'rating': rating,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
      'isAnonymous': isAnonymous,
    };
  }

  String get displayName => isAnonymous ? 'Anonymous' : patientName;
}

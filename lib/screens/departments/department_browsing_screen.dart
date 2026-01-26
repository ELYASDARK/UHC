import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';
import '../../providers/doctor_provider.dart';
import '../doctors/doctor_list_screen.dart';

class DepartmentBrowsingScreen extends StatelessWidget {
  const DepartmentBrowsingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Departments'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a Department',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Find doctors and specialists by department',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 24),

            // Department Cards Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.9,
              children: Department.values.map((dept) {
                return _DepartmentCard(department: dept);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  final Department department;

  const _DepartmentCard({required this.department});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _navigateToDepartment(context),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _getDepartmentGradient(),
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _getDepartmentColor().withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background pattern
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              left: -10,
              bottom: -10,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _getDepartmentIcon(),
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _getDepartmentName(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getDepartmentDescription(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'View Doctors',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 16,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDepartment(BuildContext context) {
    // Load doctors by department
    context.read<DoctorProvider>().loadDoctorsByDepartment(department);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DoctorListScreen(initialDepartment: department),
      ),
    );
  }

  Color _getDepartmentColor() {
    switch (department) {
      case Department.generalMedicine:
        return AppColors.generalMedicine;
      case Department.dentistry:
        return AppColors.dentistry;
      case Department.psychology:
        return AppColors.psychology;
      case Department.pharmacy:
        return AppColors.pharmacy;
      case Department.cardiology:
        return const Color(0xFFE91E63);
    }
  }

  List<Color> _getDepartmentGradient() {
    switch (department) {
      case Department.generalMedicine:
        return [const Color(0xFF2196F3), const Color(0xFF1565C0)];
      case Department.dentistry:
        return [const Color(0xFF9C27B0), const Color(0xFF6A1B9A)];
      case Department.psychology:
        return [const Color(0xFF4CAF50), const Color(0xFF2E7D32)];
      case Department.pharmacy:
        return [const Color(0xFFFF5722), const Color(0xFFD84315)];
      case Department.cardiology:
        return [const Color(0xFFE91E63), const Color(0xFFC2185B)];
    }
  }

  IconData _getDepartmentIcon() {
    switch (department) {
      case Department.generalMedicine:
        return Icons.medical_services_outlined;
      case Department.dentistry:
        return Icons.medical_information_outlined;
      case Department.psychology:
        return Icons.psychology_outlined;
      case Department.pharmacy:
        return Icons.local_pharmacy_outlined;
      case Department.cardiology:
        return Icons.favorite_outlined;
    }
  }

  String _getDepartmentName() {
    switch (department) {
      case Department.generalMedicine:
        return 'General Medicine';
      case Department.dentistry:
        return 'Dentistry';
      case Department.psychology:
        return 'Psychology';
      case Department.pharmacy:
        return 'Pharmacy';
      case Department.cardiology:
        return 'Cardiology';
    }
  }

  String _getDepartmentDescription() {
    switch (department) {
      case Department.generalMedicine:
        return 'General health check-ups and consultations';
      case Department.dentistry:
        return 'Dental care and oral health services';
      case Department.psychology:
        return 'Mental health and counseling services';
      case Department.pharmacy:
        return 'Medication and pharmaceutical services';
      case Department.cardiology:
        return 'Heart and cardiovascular care services';
    }
  }
}

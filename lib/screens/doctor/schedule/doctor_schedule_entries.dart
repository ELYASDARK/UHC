import '../../../data/models/appointment_model.dart';
import '../../../data/models/doctor_model.dart';

/// Display rows only. Booking conflicts remain enforced by the server.
class DoctorScheduleEntry {
  final TimeSlot slot;
  final AppointmentModel? appointment;

  const DoctorScheduleEntry(this.slot, [this.appointment]);
}

/// Combine the current schedule with every active booking, including bookings
/// whose original slot was removed. Each booking appears exactly once.
List<DoctorScheduleEntry> doctorScheduleEntries({
  required String doctorId,
  required DateTime date,
  required List<TimeSlot> slots,
  required List<AppointmentModel> appointments,
}) {
  final bookings = appointments.where((appointment) =>
      appointment.doctorId == doctorId &&
      _sameDay(appointment.appointmentDate, date) &&
      (appointment.status == AppointmentStatus.pending ||
          appointment.status == AppointmentStatus.confirmed));
  final uniqueBookings = {for (final booking in bookings) booking.id: booking};
  final bookingRows = uniqueBookings.values.map((booking) {
    final range = _SlotInterval.parse(booking.timeSlot)?.withScheduleEnd(slots);
    return DoctorScheduleEntry(
      range == null
          ? TimeSlot(startTime: booking.timeSlot, endTime: '')
          : TimeSlot(
              startTime: _formatMinutes(range.start),
              endTime: range.end == null ? '' : _formatMinutes(range.end!),
            ),
      booking,
    );
  }).toList();
  final rows = [
    for (final slot in slots)
      if (!bookingRows.any((row) => scheduleSlotsOverlap(row.slot, slot)))
        DoctorScheduleEntry(slot),
    ...bookingRows,
  ];
  rows.sort((a, b) => (_SlotInterval.parse(a.slot.fullDisplay)?.start ?? 1440)
      .compareTo(_SlotInterval.parse(b.slot.fullDisplay)?.start ?? 1440));
  return rows;
}

bool scheduleSlotsOverlap(TimeSlot first, TimeSlot second) {
  final a = _SlotInterval.parse(first.fullDisplay);
  final b = _SlotInterval.parse(second.fullDisplay);
  if (a == null || b == null) return false;
  if (a.end != null && b.end != null) {
    return a.start < b.end! && b.start < a.end!;
  }
  if (a.start == b.start) return true;
  if (a.end != null) return b.start >= a.start && b.start < a.end!;
  if (b.end != null) return a.start >= b.start && a.start < b.end!;
  return false;
}

bool scheduleSlotIsPast(DateTime date, String startTime, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day.isBefore(today)) return true;
  if (day.isAfter(today)) return false;
  final minutes = _SlotInterval.parse(startTime)?.start;
  if (minutes == null) return false;
  return !day.add(Duration(minutes: minutes)).isAfter(now);
}

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

class _SlotInterval {
  final int start;
  final int? end;

  const _SlotInterval(this.start, this.end);

  static _SlotInterval? parse(String value) {
    final parts = value.trim().split(RegExp(r'\s*[-–—]\s*'));
    if (parts.isEmpty || parts.length > 2) return null;
    int? parseTime(String time) {
      final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time.trim());
      if (match == null) return null;
      return TimeSlot.parseMinutes('${match[1]!.padLeft(2, '0')}:${match[2]}');
    }

    final start = parseTime(parts.first);
    final end = parts.length == 2 ? parseTime(parts.last) : null;
    if (start == null || (parts.length == 2 && (end == null || end <= start))) {
      return null;
    }
    return _SlotInterval(start, end);
  }

  _SlotInterval withScheduleEnd(List<TimeSlot> slots) {
    if (end != null) return this;
    for (final slot in slots) {
      final range = parse(slot.fullDisplay);
      if (range?.start == start && range?.end != null) return range!;
    }
    return this;
  }
}

String _formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

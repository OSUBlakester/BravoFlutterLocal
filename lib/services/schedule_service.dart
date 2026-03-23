import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ScheduleService {
  // Check if a favorite's schedule is currently active
  static bool isScheduleActive(Map<String, dynamic> favorite) {
    final schedule = favorite['schedule'];
    if (schedule == null || schedule['enabled'] != true) return false;

    final now = DateTime.now();
    final currentDay = DateFormat('EEEE').format(now); // "Monday", "Tuesday", etc.

    final days = List<String>.from(schedule['days_of_week'] ?? []);
    if (!days.contains(currentDay)) return false;

    final startTimeStr = schedule['start_time'] as String?;
    final endTimeStr = schedule['end_time'] as String?;

    if (startTimeStr == null || endTimeStr == null) return false;

    final startTime = _parseTime(startTimeStr, now);
    final endTime = _parseTime(endTimeStr, now);

    if (startTime == null || endTime == null) return false;

    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  // Check if a favorite's schedule JUST started (within the last minute)
  // This is for the runtime check
  static bool didScheduleJustStart(Map<String, dynamic> favorite) {
    final schedule = favorite['schedule'];
    if (schedule == null || schedule['enabled'] != true) return false;

    final now = DateTime.now();
    final currentDay = DateFormat('EEEE').format(now);

    final days = List<String>.from(schedule['days_of_week'] ?? []);
    if (!days.contains(currentDay)) return false;

    final startTimeStr = schedule['start_time'] as String?;
    if (startTimeStr == null) return false;

    final startTime = _parseTime(startTimeStr, now);
    if (startTime == null) return false;

    // Check if now is between startTime and startTime + 1 minute
    // This assumes the check runs at least once a minute
    final diff = now.difference(startTime);
    return diff.inSeconds >= 0 && diff.inSeconds < 60;
  }

  static DateTime? _parseTime(String timeStr, DateTime now) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (e) {
      return null;
    }
  }
}

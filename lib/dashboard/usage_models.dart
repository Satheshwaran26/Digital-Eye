// lib/models/usage_models.dart

/// Represents the total usage for a specific day of the week.
class WeeklyUsage {
  final int dayOfWeek; // Use DateTime.monday (1) through DateTime.sunday (7)
  final double totalHours;

  WeeklyUsage({required this.dayOfWeek, required this.totalHours});
}

/// Represents the total usage for a single application over a period.
class AppUsage {
  final String appName;
  final int totalSeconds;

  AppUsage({required this.appName, required this.totalSeconds});
}
// lib/dashboard/database_helper.dart

import 'package:my_app/dashboard/usage_models.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  final String _tableName = 'app_usage';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_usage.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        appName TEXT NOT NULL,
        durationInSeconds INTEGER NOT NULL,
        date TEXT NOT NULL,
        UNIQUE(appName, date)
      )
    ''');
  }

  /// Inserts or updates the usage for a specific app on a specific day.
  Future<void> upsertAppUsage(String appName, int durationInSeconds) async {
    final db = await database;
    final today = DateTime.now();
    final dateString =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    print(
        'Upserting app usage: $appName - ${durationInSeconds}s on $dateString');

    await db.insert(
      _tableName,
      {
        'appName': appName,
        'durationInSeconds': durationInSeconds,
        'date': dateString,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print('Successfully upserted app usage for $appName');
  }

  /// Fetches total usage per day for the last 7 days for the bar chart.
  Future<List<WeeklyUsage>> getWeeklyReport() async {
    final db = await database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 6));
    final startDate =
        "${sevenDaysAgo.year}-${sevenDaysAgo.month.toString().padLeft(2, '0')}-${sevenDaysAgo.day.toString().padLeft(2, '0')}";

    print('Fetching weekly report from date: $startDate');

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT date, SUM(durationInSeconds) as totalDuration
      FROM $_tableName
      WHERE date >= ?
      GROUP BY date
      ORDER BY date ASC
    ''', [startDate]);

    print('Raw query result: $maps');

    if (maps.isEmpty) {
      print('No data found in weekly report');
      return [];
    }

    final result = maps.map((map) {
      final date = DateTime.parse(map['date']);
      final totalSeconds = map['totalDuration'] as int;
      return WeeklyUsage(
        dayOfWeek: date.weekday,
        totalHours: totalSeconds / 3600.0,
      );
    }).toList();

    print('Processed weekly report: ${result.length} entries');
    return result;
  }

  /// Fetches monitored apps usage per day for the last 7 days for the bar chart.
  Future<List<WeeklyUsage>> getMonitoredAppsWeeklyReport(
      List<String> monitoredAppNames) async {
    if (monitoredAppNames.isEmpty) {
      print('No monitored apps provided for weekly report');
      return [];
    }

    final db = await database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 6));
    final startDate =
        "${sevenDaysAgo.year}-${sevenDaysAgo.month.toString().padLeft(2, '0')}-${sevenDaysAgo.day.toString().padLeft(2, '0')}";

    print('Fetching monitored apps weekly report from date: $startDate');
    print('Monitored apps: $monitoredAppNames');

    // Create placeholders for the IN clause
    final placeholders = List.filled(monitoredAppNames.length, '?').join(',');

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT date, SUM(durationInSeconds) as totalDuration
      FROM $_tableName
      WHERE date >= ? AND appName IN ($placeholders)
      GROUP BY date
      ORDER BY date ASC
    ''', [startDate, ...monitoredAppNames]);

    print('Raw monitored apps weekly query result: $maps');

    if (maps.isEmpty) {
      print('No monitored apps data found in weekly report');
      return [];
    }

    final result = maps.map((map) {
      final date = DateTime.parse(map['date']);
      final totalSeconds = map['totalDuration'] as int;
      return WeeklyUsage(
        dayOfWeek: date.weekday,
        totalHours: totalSeconds / 3600.0,
      );
    }).toList();

    print('Processed monitored apps weekly report: ${result.length} entries');
    return result;
  }

  /// Fetches the top-used apps over the last 7 days for the list view.
  Future<List<AppUsage>> getTopAppsForWeek() async {
    final db = await database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 6));
    final startDate =
        "${sevenDaysAgo.year}-${sevenDaysAgo.month.toString().padLeft(2, '0')}-${sevenDaysAgo.day.toString().padLeft(2, '0')}";

    print('Fetching top apps from date: $startDate');

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT appName, SUM(durationInSeconds) as totalDuration
      FROM $_tableName
      WHERE date >= ?
      GROUP BY appName
      ORDER BY totalDuration DESC
    ''', [startDate]);

    print('Raw top apps query result: $maps');

    if (maps.isEmpty) {
      print('No top apps data found');
      return [];
    }

    final result = maps.map((map) {
      return AppUsage(
        appName: map['appName'] as String,
        totalSeconds: map['totalDuration'] as int,
      );
    }).toList();

    print('Processed top apps: ${result.length} apps');
    return result;
  }

  /// Fetches the top-used monitored apps over the last 7 days for the list view.
  Future<List<AppUsage>> getTopMonitoredAppsForWeek(
      List<String> monitoredAppNames) async {
    if (monitoredAppNames.isEmpty) {
      print('No monitored apps provided');
      return [];
    }

    final db = await database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 6));
    final startDate =
        "${sevenDaysAgo.year}-${sevenDaysAgo.month.toString().padLeft(2, '0')}-${sevenDaysAgo.day.toString().padLeft(2, '0')}";

    print('Fetching top monitored apps from date: $startDate');
    print('Monitored apps: $monitoredAppNames');

    // Create placeholders for the IN clause
    final placeholders = List.filled(monitoredAppNames.length, '?').join(',');

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT appName, SUM(durationInSeconds) as totalDuration
      FROM $_tableName
      WHERE date >= ? AND appName IN ($placeholders)
      GROUP BY appName
      ORDER BY totalDuration DESC
    ''', [startDate, ...monitoredAppNames]);

    print('Raw monitored apps query result: $maps');

    if (maps.isEmpty) {
      print('No monitored apps data found');
      return [];
    }

    final result = maps.map((map) {
      return AppUsage(
        appName: map['appName'] as String,
        totalSeconds: map['totalDuration'] as int,
      );
    }).toList();

    print('Processed monitored apps: ${result.length} apps');
    return result;
  }

  /// Deletes records older than 7 days to keep the database clean.
  Future<void> clearOldData() async {
    final db = await database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final dateString =
        "${sevenDaysAgo.year}-${sevenDaysAgo.month.toString().padLeft(2, '0')}-${sevenDaysAgo.day.toString().padLeft(2, '0')}";

    int count =
        await db.delete(_tableName, where: 'date < ?', whereArgs: [dateString]);
    print('Deleted $count old records.');
  }
}

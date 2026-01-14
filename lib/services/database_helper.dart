import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('speed_defense.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4, // [升級] 版本號 4
      onCreate: _createDB,
      onUpgrade: _onUpgrade, // [新增] 升級回調
    );
  }

  // [新增] 資料庫升級邏輯
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const realType = 'REAL NOT NULL';
    const textType = 'TEXT NOT NULL';

    if (oldVersion < 2) {
      // 升級到版本 2: 新增 missing_limits 表
      await db.execute('''
CREATE TABLE IF NOT EXISTS missing_limits ( 
  id $idType, 
  latitude $realType,
  longitude $realType,
  address $textType,
  timestamp $textType,
  suggested_limit INTEGER
  )
''');
      print("DB Upgraded: Created missing_limits table");
    }
    if (oldVersion < 3) {
      // 升級到版本 3: 新增 upload_history 表
      await db.execute('''
CREATE TABLE IF NOT EXISTS upload_history (
  id $idType,
  osm_id INTEGER,
  latitude $realType,
  longitude $realType,
  address $textType,
  description $textType,
  timestamp $textType,
  status $textType
  )
''');
      print("DB Upgraded: Created upload_history table");
    }
    if (oldVersion < 4) {
      // 升級到版本 4: trips 表新增 distance, max_speed
      await db.execute(
        'ALTER TABLE trips ADD COLUMN distance $realType DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE trips ADD COLUMN max_speed $realType DEFAULT 0',
      );
      print("DB Upgraded: Added distance and max_speed to trips table");
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const integerType = 'INTEGER NOT NULL';
    const realType = 'REAL NOT NULL';
    const textType = 'TEXT NOT NULL';

    // 1. 行程表 (Trips)
    await db.execute('''
CREATE TABLE trips ( 
  id $idType, 
  start_time $textType,
  end_time $textType,
  distance $realType,
  max_speed $realType
  )
''');

    // 2. 軌跡表 (Trajectory) - 每個點
    await db.execute('''
CREATE TABLE trajectory ( 
  id $idType, 
  trip_id $integerType,
  latitude $realType,
  longitude $realType,
  speed $realType,
  timestamp $textType
  )
''');

    // 3. 事件表 (Events) - 超速紀錄
    await db.execute('''
CREATE TABLE events ( 
  id $idType, 
  trip_id $integerType,
  type $textType,
  latitude $realType,
  longitude $realType,
  speed $realType,
  limit_speed $realType,
  timestamp $textType
  )
''');

    // 4. 缺漏標記表 (Missing Limits)
    await db.execute('''
CREATE TABLE IF NOT EXISTS missing_limits ( 
  id $idType, 
  latitude $realType,
  longitude $realType,
  address $textType,
  timestamp $textType,
  suggested_limit INTEGER
  )
''');

    // 5. 上傳紀錄表 (Upload History)
    await db.execute('''
CREATE TABLE IF NOT EXISTS upload_history ( 
  id $idType, 
  osm_id INTEGER,
  latitude $realType,
  longitude $realType,
  address $textType,
  description $textType,
  timestamp $textType,
  status $textType
  )
''');
  }

  // --- Trips Methods ---

  Future<int> createTrip(DateTime startTime) async {
    final db = await instance.database;
    return await db.insert('trips', {
      'start_time': startTime.toIso8601String(),
      'end_time': '', // 尚未結束
      'distance': 0.0,
      'max_speed': 0.0,
    });
  }

  Future<int> endTrip(int id, DateTime endTime) async {
    final db = await instance.database;
    return await db.update(
      'trips',
      {'end_time': endTime.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // [新增] 結束行程並更新數據
  Future<int> endTripWithStats(
    int id,
    DateTime endTime,
    double distance,
    double maxSpeed,
  ) async {
    final db = await instance.database;
    return await db.update(
      'trips',
      {
        'end_time': endTime.toIso8601String(),
        'distance': distance,
        'max_speed': maxSpeed,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // [新增] 取得最近 7 天的行程統計
  Future<List<Map<String, dynamic>>> getWeeklyStats() async {
    final db = await instance.database;
    // 找出最近 7 天，且已結束的行程
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    return await db.query(
      'trips',
      where: 'start_time >= ? AND end_time != ""',
      whereArgs: [sevenDaysAgo.toIso8601String()],
      orderBy: 'start_time ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllTrips() async {
    final db = await instance.database;
    return await db.query('trips', orderBy: 'start_time DESC');
  }

  Future<void> deleteTrip(int id) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('trips', where: 'id = ?', whereArgs: [id]);
      await txn.delete('trajectory', where: 'trip_id = ?', whereArgs: [id]);
      await txn.delete('events', where: 'trip_id = ?', whereArgs: [id]);
    });
  }

  Future<void> deleteAllTrips() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('trips');
      await txn.delete('trajectory');
      await txn.delete('events');
    });
  }

  // --- Trajectory Methods ---

  Future<int> insertTrajectoryPoint(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('trajectory', row);
  }

  Future<List<Map<String, dynamic>>> getTrajectory(int tripId) async {
    final db = await instance.database;
    return await db.query(
      'trajectory',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'timestamp ASC',
    );
  }

  // --- Event Methods ---

  Future<int> insertEvent(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('events', row);
  }

  Future<List<Map<String, dynamic>>> getEvents(int tripId) async {
    final db = await instance.database;
    return await db.query(
      'events',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'timestamp ASC',
    );
  }

  // --- Missing Limits Methods ---

  Future<int> insertMissingLimit(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('missing_limits', row);
  }

  Future<void> deleteMissingLimit(int id) async {
    final db = await instance.database;
    await db.delete('missing_limits', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllMissingLimits() async {
    final db = await instance.database;
    await db.delete('missing_limits');
  }

  Future<List<Map<String, dynamic>>> getMissingLimits() async {
    final db = await instance.database;
    return await db.query('missing_limits', orderBy: 'timestamp DESC');
  }

  Future<void> updateMissingLimit(int id, int limit) async {
    final db = await instance.database;
    await db.update(
      'missing_limits',
      {'suggested_limit': limit},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // [新增] 移除本地速限設定 (變回單純缺漏紀錄)
  Future<void> removeLocalLimit(int id) async {
    final db = await instance.database;
    await db.update(
      'missing_limits',
      {'suggested_limit': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Upload History Methods ---

  Future<int> insertUploadHistory(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('upload_history', row);
  }

  Future<List<Map<String, dynamic>>> getUploadHistory() async {
    final db = await instance.database;
    return await db.query('upload_history', orderBy: 'timestamp DESC');
  }

  // [新增] 取得所有已設定本地速限的紀錄
  Future<List<Map<String, dynamic>>> getLocalRecords() async {
    final db = await instance.database;
    return await db.query(
      'missing_limits',
      where: 'suggested_limit IS NOT NULL AND suggested_limit > 0',
      orderBy: 'timestamp DESC',
    );
  }

  // [新增] 取得目前缺漏紀錄總數 (包含未處理與本地紀錄，只要未上傳/刪除都算)
  Future<int> getMissingCount() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM missing_limits',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // [新增] 尋找附近的本地速限紀錄
  Future<int?> findNearbyLocalLimit(double lat, double lon) async {
    final db = await instance.database;

    // 粗略過濾: 緯度/經度 差異在 0.001 內 (約 100 公尺)
    const double range = 0.001;

    // 找出有設定建議速限的資料
    final List<Map<String, dynamic>> maps = await db.query(
      'missing_limits',
      where:
          'suggested_limit IS NOT NULL AND suggested_limit > 0 AND '
          'latitude BETWEEN ? AND ? AND '
          'longitude BETWEEN ? AND ?',
      whereArgs: [lat - range, lat + range, lon - range, lon + range],
    );

    if (maps.isEmpty) return null;

    int? bestLimit;
    double minDistance = 50.0; // 搜尋半徑 50 公尺

    for (final map in maps) {
      final double rLat = map['latitude'] as double;
      final double rLon = map['longitude'] as double;

      // 簡單歐式距離估算 (在小範圍內足夠精確且快)
      // 1 度緯度 ~= 111km -> 111000m
      // 1 度經度 ~= 111km * cos(lat) -> 假設 100000m 方便計算

      final double dLat = (lat - rLat) * 111000;
      final double dLon = (lon - rLon) * 100000; // 台灣緯度約 23度, cos(23) ~= 0.92

      final double dist = (dLat * dLat) + (dLon * dLon); // 距離平方

      if (dist < (minDistance * minDistance)) {
        // 比較平方值
        // 找到更近的
        minDistance = dist; // 這裡其實是距離平方，但邏輯不影響
        bestLimit = map['suggested_limit'] as int?;
      }
    }

    return bestLimit;
  }
}

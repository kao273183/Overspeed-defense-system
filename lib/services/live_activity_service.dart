import 'dart:io';
import 'package:live_activities/live_activities.dart';

class LiveActivityService {
  final _liveActivities = LiveActivities();
  String? _activityId;
  bool _isInitialized = false;

  // 初始化
  Future<void> init() async {
    if (!Platform.isIOS) return;
    
    await _liveActivities.init(
      appGroupId: 'group.com.example.speedDefenseSystem', 
    );
    _isInitialized = true;
  }

  // 啟動 Live Activity
  Future<void> startActivity(int speedLimit) async {
    if (!Platform.isIOS || !_isInitialized) return;

    // 如果已經有活動在跑，先更新就好，或者重啟
    if (_activityId != null) return;

    final Map<String, dynamic> initialData = {
      'speed': 0,
      'limit': speedLimit,
      'isOverSpeed': false,
    };

    try {
      // v2.4.3 createActivity 可能簽名是 (Map<String, dynamic> data) 
      // 根據錯誤訊息，它似乎又變回只接受一個參數? 
      // 之前的錯誤是 "Too few positional arguments: 2 required, 1 given"
      // 然後我給了 (Map, String) 報錯 "Map can't be assigned to String" (針對第1個參數)
      // 這表示第一個參數必須是 String (Activity ID?)
      // 所以正確順序應該是: createActivity(String activityId, Map<String, dynamic> data)
      
      String newActivityId = "speed_defense_${DateTime.now().millisecondsSinceEpoch}";
      
      // 嘗試反過來傳: (ID, Data)
      // 若這還錯，可能是 (Map data, {removeWhenAppIsKilled}) 的 named param 誤解
      // 但根據 "2 positional arguments required"，這幾乎只能是兩個必填參數。
      // 而第一個參數被要求是 String，第二個參數報錯是 "String can't be assigned to Map"
      // 所以順序是 (String activityId, Map data)。
      
      await _liveActivities.createActivity(
        // newActivityId, // 第一個參數 ID ? (但它回傳值是 Future<String?> activityId)
        // 讓我們再仔細看錯誤訊息
        // "argument type 'Map' can't be assigned to 'String'" -> 第一個參數位置我放了 Map, 它要 String.
        // "argument type 'String' can't be assigned to 'Map'" -> 第二個參數位置我放了 String, 它要 Map.
        // 所以: createActivity(String activityId, Map data) 是正確推論。
        
        newActivityId,
        initialData
      );
      
      _activityId = newActivityId;
      print("Live Activity Started: $_activityId");
    } catch (e) {
      print("Error starting Live Activity: $e");
    }
  }

  // 更新數據
  Future<void> updateActivity(int currentSpeed, int speedLimit, bool isOverSpeed) async {
    if (_activityId == null) return;

    final Map<String, dynamic> data = {
      'speed': currentSpeed,
      'limit': speedLimit,
      'isOverSpeed': isOverSpeed,
    };

    try {
      await _liveActivities.updateActivity(_activityId!, data);
    } catch (e) {
      print("Error updating Live Activity: $e");
    }
  }

  // 停止
  Future<void> stopActivity() async {
    if (_activityId == null) return;
    try {
      await _liveActivities.endActivity(_activityId!);
      _activityId = null;
    } catch (e) {
      print("Error stopping Live Activity: $e");
    }
  }
}

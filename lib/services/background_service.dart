import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart'; // [New] For defaultTargetPlatform
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_service.dart';
import 'osm_service.dart';
import 'database_helper.dart';

// 這是背景服務的進入點
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // --- Android 通知的頻道設定 1: 背景服務常駐 ---
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'overspeed_alert_channel', // id
    '測速預警服務', // title
    description: '正在背景偵測車速...', // description
    importance: Importance.low, // low 才不會一直發出通知聲干擾
  );

  // --- Android 通知的頻道設定 2: 缺漏/重要警報 ---
  const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
    'missing_record_alert', // id
    '重要警報', // title
    description: '缺漏路段與其他重要通知', // description
    importance: Importance.high, // High = 跳出 + 聲音
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 建立頻道 1
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  // 建立頻道 2
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(alertChannel);

  // --- 設定服務 ---
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // 核心邏輯在這裡
      autoStart: false, // 我們要手動按按鈕才開始
      isForegroundMode: true, // 前台服務 (保活關鍵)
      notificationChannelId: 'overspeed_alert_channel',
      initialNotificationTitle: '測速預警服務',
      initialNotificationContent: '初始化中...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground, // 需在 Info.plist 開啟 Background fetch
    ),
  );
}

// iOS 專用的背景回調 (保持簡單，回傳 true 讓系統知道我們還活著)
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

// --- 🚀 背景服務的核心邏輯 (Android & iOS 共用) ---
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Ensure Dart bindings are initialized
  DartPluginRegistrant.ensureInitialized();

  try {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    // [新增] 狀態變數定義
    Position? lastPosition;
    DateTime? lastSpeakTime;
    int alertInterval = 3;
    bool isOsmEnabled = true;

    // [新增] 缺漏標記追蹤
    double? lastMissingLat;
    double? lastMissingLng;
    DateTime? lastMissingTime;

    // Singleton might be re-initialized in this isolate
    final audioService = AudioService();
    try {
      await audioService.init();
      print("Background Service: AudioService initialized");
    } catch (e) {
      print("Background Service: AudioService init failed: $e");
    }

    int speedLimit = 50;

    // [新增] 從設定讀取語音
    // SharedPreferences sometimes has issues in background on Android if not handled carefully,
    // but usually works if await is used.
    final prefs = await SharedPreferences.getInstance();
    String customVoiceMessage = prefs.getString('voice_message') ?? "嚴重超速！請煞車";
    isOsmEnabled = prefs.getBool('osm_enabled_v2') ?? true;
    print("背景服務啟動，載入語音: $customVoiceMessage, OSM: $isOsmEnabled");

    service.on('setLimit').listen((event) {
      if (event != null) {
        speedLimit = event['limit'] as int;
      }
    });

    // [Added] Custom Sound Path
    String? customSoundPath = prefs.getString('custom_alert_sound');

    // [新增] 監聽語音更新事件
    service.on('updateVoiceMessage').listen((event) {
      if (event != null) {
        customVoiceMessage = event['message'] as String;
        print("背景服務：語音已更新為 -> $customVoiceMessage");
      }
    });

    // [Added] Listen for Custom Sound Update
    service.on('setCustomAlertSound').listen((event) {
      if (event != null) {
        customSoundPath = event['path'] as String?;
        print("背景服務：自訂警示音已更新為 -> $customSoundPath");
      }
    });

    // [新增] 監聽 OSM 開關
    service.on('setOsmEnabled').listen((event) {
      if (event != null) {
        isOsmEnabled = event['enabled'] as bool;
        print("背景服務：OSM 自動速限已設定為: $isOsmEnabled");
      }
    });

    // [新增] 監聽提示間隔
    service.on('setAlertInterval').listen((event) {
      if (event != null) {
        try {
          alertInterval = (event['interval'] as num).toInt();
          print("背景服務：提示間隔已更新為 -> $alertInterval 秒");
        } catch (e) {
          print("背景服務錯誤：更新間隔失敗 $e");
        }
      }
    });

    // [New] Tolarance Listeners
    int dangerTolerance = 38;
    int warningBuffer = 5;

    service.on('setDangerTolerance').listen((event) {
      if (event != null) {
        dangerTolerance = (event['tolerance'] as num).toInt();
        print("背景服務：嚴重超速容許值已更新為 -> +$dangerTolerance km/h");
      }
    });

    service.on('setWarningBuffer').listen((event) {
      if (event != null) {
        warningBuffer = (event['buffer'] as num).toInt();
        print("背景服務：警示音緩衝區已更新為 -> -$warningBuffer km/h");
      }
    });

    // [新增] 資料庫連接
    final dbHelper = DatabaseHelper.instance;
    int? currentTripId;

    // 服務啟動時，建立一筆新的 Trip
    try {
      currentTripId = await dbHelper.createTrip(DateTime.now());
      print("背景服務：開始新行程 Trip ID: $currentTripId");
    } catch (e) {
      print("背景服務資料庫錯誤: $e");
    }

    Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        if (!isOsmEnabled || lastPosition == null) return;

        // 通知 UI 開始更新
        service.invoke('updateOsmStatus', {'isLoading': true});

        try {
          // 1. Try OSM API
          int? limit = await OsmService().getMaxSpeed(
            lastPosition!.latitude,
            lastPosition!.longitude,
          );

          // 2. [Fallback] Try Local Database if OSM failed
          if (limit == null || limit == 0) {
            final localLimit = await dbHelper.findNearbyLocalLimit(
              lastPosition!.latitude,
              lastPosition!.longitude,
            );

            if (localLimit != null && localLimit > 0) {
              limit = localLimit;
              print("背景服務: 使用本地端速限紀錄 -> $limit km/h");
            }
          }

          if (limit != null && limit > 0) {
            if (limit != speedLimit) {
              speedLimit = limit;
              print("速限更新為: $speedLimit");

              // 1. 通知 UI 更新顯示
              service.invoke('updateLimit', {'limit': limit});
            }
          }
        } catch (e) {
          print("OSM Check Error: $e");
        } finally {
          // 通知 UI 更新結束
          service.invoke('updateOsmStatus', {'isLoading': false});
        }

        // [新增] 缺漏標記邏輯
        try {
          if (lastPosition != null && isOsmEnabled) {
            final limit = await OsmService().getMaxSpeed(
              lastPosition!.latitude,
              lastPosition!.longitude,
            );

            if (limit == null || limit == 0) {
              // [New] Check if we already have a local fix
              final localFix = await dbHelper.findNearbyLocalLimit(
                lastPosition!.latitude,
                lastPosition!.longitude,
              );

              if (localFix != null && localFix > 0) {
                // We have a local override, so it's not "missing" for the user anymore
                return;
              }

              bool isDuplicate = false;
              if (lastMissingLat != null && lastMissingLng != null) {
                final distance = Geolocator.distanceBetween(
                  lastPosition!.latitude,
                  lastPosition!.longitude,
                  lastMissingLat!,
                  lastMissingLng!,
                );
                if (distance < 100) {
                  isDuplicate = true;
                }
              }

              if (lastMissingTime != null) {
                final diff = DateTime.now().difference(lastMissingTime!);
                if (diff.inMinutes < 3) {
                  isDuplicate = true;
                }
              }

              if (!isDuplicate) {
                print("背景服務: 發現缺漏路段，準備記錄...");
                final address = await OsmService().getAddress(
                  lastPosition!.latitude,
                  lastPosition!.longitude,
                );

                if (address != null) {
                  await dbHelper.insertMissingLimit({
                    'latitude': lastPosition!.latitude,
                    'longitude': lastPosition!.longitude,
                    'address': address,
                    'timestamp': DateTime.now().toIso8601String(),
                    'suggested_limit': null,
                  });

                  print("背景服務: 已記錄缺漏路段 [$address]");

                  // [New] Real-time Notification
                  final count = await dbHelper.getMissingCount();
                  final flutterLocalNotificationsPlugin =
                      FlutterLocalNotificationsPlugin();
                  await flutterLocalNotificationsPlugin.show(
                    DateTime.now().millisecond, // Unique ID
                    '發現缺漏路段',
                    '已自動紀錄：$address',
                    NotificationDetails(
                      android: AndroidNotificationDetails(
                        'missing_record_alert',
                        '重要警報',
                        importance: Importance.high,
                        priority: Priority.high,
                        number:
                            count, // [New] Set Badge Number for supported launchers (Samsung, etc.)
                        channelShowBadge: true,
                      ),
                      iOS: DarwinNotificationDetails(
                        badgeNumber: count, // Sync Badge
                        sound: 'default',
                      ),
                    ),
                  );

                  lastMissingLat = lastPosition!.latitude;
                  lastMissingLng = lastPosition!.longitude;
                  lastMissingTime = DateTime.now();
                }
              }
            }
          }
        } catch (e) {
          print("Missing Limit Record Error: $e");
        }
      } catch (e) {
        print("Background Timer Loop Error: $e");
      }
    });

    // [新增] 總里程紀錄與最高速
    double totalDistance = 0.0;
    double maxSpeed = 0.0;

    // [Fix] Platform-specific Location Settings for Background Stability
    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 1),
        // foregroundNotificationConfig: ... (Managed by Background Service plugin)
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }

    Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) async {
        try {
          // [新增] 累積里程
          if (lastPosition != null) {
            final dist = Geolocator.distanceBetween(
              lastPosition!.latitude,
              lastPosition!.longitude,
              position.latitude,
              position.longitude,
            );
            totalDistance += dist;
          }

          lastPosition = position; // 更新最後位置 for Timer

          double speedKmh = position.speed * 3.6;
          if (speedKmh < 0) speedKmh = 0;

          // [新增] 更新最高速
          if (speedKmh > maxSpeed) {
            maxSpeed = speedKmh;
          }

          // [新增] 寫入軌跡點到資料庫 (Black Box)
          if (currentTripId != null) {
            try {
              await dbHelper.insertTrajectoryPoint({
                'trip_id': currentTripId,
                'latitude': position.latitude,
                'longitude': position.longitude,
                'speed': speedKmh,
                'timestamp': DateTime.now().toIso8601String(),
              });
            } catch (e) {
              // print("寫入軌跡失敗: $e"); // Too noisy
            }
          }

          if (service is AndroidServiceInstance) {
            if (await service.isForegroundService()) {
              flutterLocalNotificationsPlugin.show(
                888,
                '別扣我 - 測速系統',
                '目前時速: ${speedKmh.toStringAsFixed(0)} km/h (限速: $speedLimit)',
                const NotificationDetails(
                  android: AndroidNotificationDetails(
                    'overspeed_alert_channel',
                    '測速預警服務',
                    icon: 'ic_bg_service_small',
                    ongoing: true,
                  ),
                ),
              );
            }
          }

          // 發送速度更新給 UI
          service.invoke('updateSpeed', {
            'speed': speedKmh,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'heading': position.heading,
            'altitude': position.altitude,
          });

          // [新增] 判斷超速邏輯
          double speed = speedKmh;

          // [Updated] Use configurable variables
          double dangerThreshold = (speedLimit + dangerTolerance).toDouble();
          double warningThreshold = dangerThreshold - warningBuffer;

          // [修改] 加入時間間隔判斷
          bool canSpeak = true;
          if (lastSpeakTime != null) {
            final difference = DateTime.now().difference(lastSpeakTime!);
            if (difference.inSeconds < alertInterval) {
              canSpeak = false; // 還沒到冷卻時間
            }
          }

          if (speed >= dangerThreshold) {
            // 嚴重超速
            if (canSpeak) {
              print("背景偵測：嚴重超速！播放 -> $customVoiceMessage");
              await audioService.speak(customVoiceMessage);
              lastSpeakTime = DateTime.now(); // 更新最後播報時間

              // [新增] 記錄嚴重超速事件
              if (currentTripId != null) {
                dbHelper.insertEvent({
                  'trip_id': currentTripId,
                  'type': 'DANGER',
                  'latitude': position.latitude,
                  'longitude': position.longitude,
                  'speed': speedKmh,
                  'limit_speed': speedLimit,
                  'timestamp': DateTime.now().toIso8601String(),
                });
              }
            }
          } else if (speed >= warningThreshold) {
            // 接近嚴重超速
            if (canSpeak) {
              await audioService.playBeep(customSoundPath);
              lastSpeakTime = DateTime.now(); // 更新最後播報時間
            }
          }
        } catch (e) {
          print("Background Location Stream Error: $e");
        }
      },
      onError: (e) {
        print("Location Stream Error (Fatal): $e");
      },
    );

    service.on('stopService').listen((event) async {
      try {
        // [新增] 結束 Trip
        if (currentTripId != null) {
          // 檢查總里程是否過短 (< 50公尺)
          if (totalDistance < 50) {
            print("背景服務：行程距離過短 ($totalDistance m)，捨棄紀錄。");
            await dbHelper.deleteTrip(currentTripId!);
          } else {
            await dbHelper.endTripWithStats(
              currentTripId!,
              DateTime.now(),
              totalDistance,
              maxSpeed,
            );
            print(
              "背景服務：結束行程 Trip ID: $currentTripId (距離: ${totalDistance.toStringAsFixed(1)} m, 最高速: ${maxSpeed.toStringAsFixed(1)})",
            );
          }
        }
        service.stopSelf();
      } catch (e) {
        print("Stop Service Error: $e");
      }
    });
  } catch (e) {
    print("Background Service CRITICAL FAILURE: $e");
  }
}

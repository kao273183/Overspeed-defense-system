import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // [New]
import '../services/database_helper.dart'; // [New]
import 'package:latlong2/latlong.dart'; // [新增]
import '../services/osm_service.dart';

enum AlertStatus { safe, warning, danger }

class SpeedProvider with ChangeNotifier {
  double _currentSpeedKmh = 0.0;
  int _speedLimit = 50;
  bool _isMonitoring = false;
  AlertStatus _alertStatus = AlertStatus.safe;

  // [新增] 自定義語音訊息 (預設值)
  String _voiceMessage = "嚴重超速！請煞車";

  // [新增] 語音提醒間隔 (秒)，預設 3 秒
  int _alertInterval = 3;

  // [新增] HUD 模式開關
  bool _isHudMode = false;

  // [新增] Gauge Theme
  String _gaugeTheme = 'default';

  // [新增] Map Visibility
  bool _isMapVisible = false;

  // [新增] Location & Path
  LatLng? _currentLocation;
  List<LatLng> _pathHistory = [];
  StreamSubscription<Position>? _positionStream;

  // [新增] 當前位置地址
  String _currentAddress = "定位中...";

  // [新增] 當前方位 (Heading)
  double _currentHeading = 0.0;

  // [新增] 當前海拔
  double _currentAltitude = 0.0;

  // [新增] 區間測速相關
  bool _isAvgSpeedActive = false;
  DateTime? _avgStartTime;
  LatLng? _avgStartLocation; // 保留起始點，雖然我們主要靠累計每一段距離
  double _avgSpeedKmh = 0.0;
  double _avgDistanceMetres = 0.0;

  // [Added] Custom Alert Sound Path
  // [Added] Custom Alert Sound Path
  String? _customAlertSoundPath;

  // [New] Configurable Tolerance
  int _dangerTolerance = 38; // Default: Limit + 38 triggers voice
  int _warningBuffer = 5; // Default: Danger - 5 triggers beep

  double get currentSpeedKmh => _currentSpeedKmh;
  int get speedLimit => _speedLimit;
  bool get isMonitoring => _isMonitoring;
  AlertStatus get alertStatus => _alertStatus;
  String get voiceMessage => _voiceMessage;
  int get alertInterval => _alertInterval;
  bool get isHudMode => _isHudMode;
  String get currentAddress => _currentAddress;
  String get gaugeTheme => _gaugeTheme;
  bool get isMapVisible => _isMapVisible;
  double get currentHeading => _currentHeading;
  double get currentAltitude => _currentAltitude;
  LatLng? get currentLocation => _currentLocation;
  List<LatLng> get pathHistory => _pathHistory;

  // [新增] 區間測速 Getters
  bool get isAvgSpeedActive => _isAvgSpeedActive;
  double get avgSpeedKmh => _avgSpeedKmh;
  double get avgDistanceMetres => _avgDistanceMetres;
  String? get customAlertSoundPath => _customAlertSoundPath;
  int get dangerTolerance => _dangerTolerance;
  int get warningBuffer => _warningBuffer;

  int get avgDurationSeconds {
    if (_avgStartTime == null) return 0;
    return DateTime.now().difference(_avgStartTime!).inSeconds;
  }

  // 建構子：啟動時讀取存檔
  SpeedProvider() {
    _loadSettings();
    _initLocation(); // [新增] 啟動時先抓一次位置
  }

  // --- [新增] 初始化位置 ---
  Future<void> _initLocation() async {
    try {
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        _currentAddress = "無定位權限";
        notifyListeners();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 更新地址
      // 這裡順便更新初始座標
      _currentLocation = LatLng(position.latitude, position.longitude);

      final address = await OsmService().getAddress(
        position.latitude,
        position.longitude,
      );
      if (address != null) {
        _currentAddress = address;
      } else {
        _currentAddress = "未知位置";
      }

      _startLocationStream();
      _checkServiceStatus();

      notifyListeners();
    } catch (e) {
      print("Location Init Error: $e");
      _currentAddress = "定位失敗";
      notifyListeners();
    }
  }

  void _startLocationStream() {
    _stopLocationStream(); // Avoid duplicate streams

    // Passive location updates (foreground only)
    final locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            _currentLocation = LatLng(position.latitude, position.longitude);
            // [Fix] When not monitoring (passive stream), speed should be 0
            _currentSpeedKmh = 0.0;

            // Update path history
            if (_pathHistory.isEmpty) {
              _pathHistory.add(_currentLocation!);
            } else {
              const Distance distance = Distance();
              final double dist = distance.as(
                LengthUnit.Meter,
                _pathHistory.last,
                _currentLocation!,
              );
              if (dist > 10) {
                _pathHistory.add(_currentLocation!);
                if (_pathHistory.length > 500) {
                  _pathHistory.removeAt(0);
                }
              }
            }
            notifyListeners();
          },
        );
  }

  void _stopLocationStream() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  Future<void> _checkServiceStatus() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      // Service is already running (e.g. from background), restore UI state
      startMonitoring();
    }
  }

  Future<bool> _checkPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      return false; // Don't auto request here
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  // [New] Explicitly request permission
  Future<bool> requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    // If granted, retry initialization
    _initLocation();
    return true;
  }

  // --- 讀取設定 ---
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _voiceMessage = prefs.getString('voice_message') ?? "嚴重超速！請煞車";
    _isOsmEnabled = prefs.getBool('osm_enabled_v2') ?? true;
    _alertInterval = prefs.getInt('alert_interval') ?? 3;
    _isHudMode = prefs.getBool('hud_mode') ?? false;
    _gaugeTheme = prefs.getString('gauge_theme') ?? 'default'; // 讀取 Theme
    _customAlertSoundPath = prefs.getString('custom_alert_sound'); // [Added]

    // [New] Tolerances
    _dangerTolerance = prefs.getInt('danger_tolerance') ?? 38;
    _warningBuffer = prefs.getInt('warning_buffer') ?? 5;

    notifyListeners();
  }

  Future<void> setGaugeTheme(String theme) async {
    _gaugeTheme = theme;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gauge_theme', theme);
  }

  void toggleMapVisibility() {
    _isMapVisible = !_isMapVisible;
    notifyListeners();
  }

  // --- [新增] 切換 HUD 模式 ---
  Future<void> setHudMode(bool enabled) async {
    _isHudMode = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hud_mode', enabled);
  }

  // --- [新增] 設定語音提醒間隔 ---
  Future<void> setAlertInterval(int interval) async {
    _alertInterval = interval;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('alert_interval', interval);

    if (_isMonitoring) {
      FlutterBackgroundService().invoke("setAlertInterval", {
        "interval": interval,
      });
    }
  }

  // --- [新增] 設定自定義語音 ---
  Future<void> setVoiceMessage(String message) async {
    _voiceMessage = message;
    notifyListeners();

    // 1. 存檔 (下次打開還在)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_message', message);

    // 2. 如果正在監控，立刻通知背景服務更新
    if (_isMonitoring) {
      FlutterBackgroundService().invoke("updateVoiceMessage", {
        "message": message,
      });
    }
  }

  // [Added] Set Custom Alert Sound
  Future<void> setCustomAlertSound(String? path) async {
    _customAlertSoundPath = path;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('custom_alert_sound');
    } else {
      await prefs.setString('custom_alert_sound', path);
    }

    // Notify Background Service
    if (_isMonitoring) {
      FlutterBackgroundService().invoke("setCustomAlertSound", {"path": path});
    }
  }

  // [New] Set Danger Tolerance
  Future<void> setDangerTolerance(int tolerance) async {
    _dangerTolerance = tolerance;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('danger_tolerance', tolerance);

    if (_isMonitoring) {
      FlutterBackgroundService().invoke("setDangerTolerance", {
        "tolerance": tolerance,
      });
    }
  }

  // [New] Set Warning Buffer
  Future<void> setWarningBuffer(int buffer) async {
    _warningBuffer = buffer;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('warning_buffer', buffer);

    if (_isMonitoring) {
      FlutterBackgroundService().invoke("setWarningBuffer", {"buffer": buffer});
    }
  }

  // [新增] 標記目前速限來源
  bool _isLimitFromOsm = false;
  bool get isLimitFromOsm => _isLimitFromOsm;

  void setLimit(int limit) {
    _speedLimit = limit;
    _isLimitFromOsm = false; // 手動設定
    if (_isMonitoring) {
      FlutterBackgroundService().invoke("setLimit", {"limit": limit});
    }
    _checkSpeed(_currentSpeedKmh);
    notifyListeners();
  }

  void adjustLimit(int amount) {
    int newLimit = (_speedLimit + amount).clamp(0, 300);
    setLimit(newLimit);
  }

  Future<void> startMonitoring() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    _isMonitoring = true;
    _stopLocationStream(); // Stop passive stream, let Service handle updates
    notifyListeners();

    final service = FlutterBackgroundService();

    // [Fix] Ensure service is running. If not, start it.
    if (!await service.isRunning()) {
      await service.startService();
      // Give it a moment to initialize isolate
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // [Fix] Always sync settings (whether validly running or just started)
    service.invoke("setLimit", {"limit": _speedLimit});
    service.invoke("updateVoiceMessage", {"message": _voiceMessage});
    service.invoke("setOsmEnabled", {"enabled": _isOsmEnabled});
    service.invoke("setAlertInterval", {"interval": _alertInterval});
    service.invoke("setDangerTolerance", {
      "tolerance": _dangerTolerance,
    }); // [New]
    service.invoke("setWarningBuffer", {"buffer": _warningBuffer}); // [New]

    // [新增] 監聽背景傳來的「OSM 速限更新」
    service.on('updateLimit').listen((event) {
      if (event != null) {
        int newLimit = event['limit'] as int;
        _speedLimit = newLimit;
        _isLimitFromOsm = true; // 來自 OSM 自動更新
        _checkSpeed(_currentSpeedKmh);
        notifyListeners();
      }
    });

    service.on('updateSpeed').listen((event) {
      if (event != null) {
        double speed = (event['speed'] as num).toDouble();
        _currentSpeedKmh = speed;

        // [New] Update Location from Background Service
        if (event.containsKey('latitude') && event.containsKey('longitude')) {
          double lat = (event['latitude'] as num).toDouble();
          double lon = (event['longitude'] as num).toDouble();

          if (event.containsKey('heading')) {
            _currentHeading = (event['heading'] as num).toDouble();
          }

          if (event.containsKey('altitude')) {
            _currentAltitude = (event['altitude'] as num).toDouble();
          }

          final newLoc = LatLng(lat, lon);

          _currentLocation = newLoc;

          // Path History Logic
          if (_pathHistory.isEmpty) {
            _pathHistory.add(newLoc);
          } else {
            // Calculate distance to avoid too many points
            const Distance distance = Distance();
            final double dist = distance.as(
              LengthUnit.Meter,
              _pathHistory.last,
              newLoc,
            );
            if (dist > 10) {
              // Only add point if moved > 10m
              _pathHistory.add(newLoc);
              if (_pathHistory.length > 500) {
                _pathHistory.removeAt(0);
              }
            }
          }
        }

        // [New] Update Average Speed Logic
        if (_isAvgSpeedActive &&
            _avgStartTime != null &&
            _currentLocation != null) {
          final now = DateTime.now();
          final durationSeconds = now.difference(_avgStartTime!).inSeconds;

          if (_lastAvgCalcLocation != null) {
            final dist = const Distance().as(
              LengthUnit.Meter,
              _lastAvgCalcLocation!,
              _currentLocation!,
            );
            _avgDistanceMetres += dist;
          }
          _lastAvgCalcLocation = _currentLocation; // 更新以此點為下次計算基準

          if (durationSeconds > 0) {
            // Speed (km/h) = (Distance (m) / Time (s)) * 3.6
            _avgSpeedKmh = (_avgDistanceMetres / durationSeconds) * 3.6;
          }
        }

        _checkSpeed(speed);
        notifyListeners();
      }
    });
    // [新增] 監聽 OSM 更新狀態 (Loading)
    service.on('updateOsmStatus').listen((event) {
      if (event != null) {
        _isOsmFetching = event['isLoading'] as bool;
        notifyListeners();
      }
    });
  }

  // --- OSM 開關 ---
  bool _isOsmEnabled = true;
  bool get isOsmEnabled => _isOsmEnabled;

  // [新增] OSM 讀取狀態
  bool _isOsmFetching = false;
  bool get isOsmFetching => _isOsmFetching;

  Future<void> setOsmEnabled(bool enabled) async {
    _isOsmEnabled = enabled;
    if (!enabled) {
      _isLimitFromOsm = false; // 關閉時候回到手動模式標示
    }
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('osm_enabled_v2', enabled);

    if (_isMonitoring) {
      FlutterBackgroundService().invoke("setOsmEnabled", {"enabled": enabled});
    }
  }

  Future<void> stopMonitoring() async {
    final service = FlutterBackgroundService();
    service.invoke("stopService");

    _isMonitoring = false;
    _currentSpeedKmh = 0;
    _alertStatus = AlertStatus.safe;
    _startLocationStream(); // Resume passive stream

    // [New] Check Missing Records & Trip Summary Notification
    final missingCount = await DatabaseHelper.instance.getMissingCount();
    if (missingCount > 0) {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      await flutterLocalNotificationsPlugin.show(
        889, // Trip Summary ID
        '行程已結束',
        '還有 $missingCount 筆缺漏紀錄尚未回報',
        NotificationDetails(
          android: const AndroidNotificationDetails(
            'missing_record_alert',
            '重要警報',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            badgeNumber: missingCount,
            sound: 'default',
          ),
        ),
      );
    }

    notifyListeners();
  }

  void _checkSpeed(double speed) {
    // [Updated] Use configurable tolerances
    double dangerThreshold = (_speedLimit + _dangerTolerance).toDouble();
    double warningThreshold = dangerThreshold - _warningBuffer;

    if (speed >= dangerThreshold) {
      _alertStatus = AlertStatus.danger;
    } else if (speed >= warningThreshold) {
      _alertStatus = AlertStatus.warning;
    } else {
      _alertStatus = AlertStatus.safe;
    }
  }

  // [新增] 區間測速控制
  LatLng? _lastAvgCalcLocation;

  void startAvgZone() {
    _isAvgSpeedActive = true;
    _avgStartTime = DateTime.now();
    _avgStartLocation = _currentLocation;
    _lastAvgCalcLocation = _currentLocation; // 設定初始點
    _avgDistanceMetres = 0.0;
    _avgSpeedKmh = 0.0;
    notifyListeners();
  }

  void stopAvgZone() {
    _isAvgSpeedActive = false;
    _avgStartTime = null;
    _avgStartLocation = null;
    _lastAvgCalcLocation = null;
    _avgDistanceMetres = 0.0;
    _avgSpeedKmh = 0.0;
    notifyListeners();
  }
}

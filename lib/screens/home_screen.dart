import 'package:geolocator/geolocator.dart'; // [New]
import 'dart:async'; // [Restored]
import 'package:file_picker/file_picker.dart'; // [New]
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; // [New]
import 'package:path_provider/path_provider.dart'; // [New]
import 'dart:io'; // [New]
import 'stats_screen.dart'; // [New]
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/speed_provider.dart';
import '../providers/appearance_provider.dart'; // [New]
import '../services/audio_service.dart';
import 'history_screen.dart';
import '../services/database_helper.dart'; // [New]
import '../widgets/analog_gauge.dart'; // [新增]
import '../widgets/mini_map.dart'; // [新增]
import 'missing_records_screen.dart';
import 'local_records_screen.dart'; // [New]
import 'upload_history_screen.dart'; // [新增]

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- 時鐘邏輯 ---
  late Timer _timer;
  String _timeString = "--:--";

  // --- 缺漏紀錄通知邏輯 ---
  int _missingCount = 0;
  Timer? _missingRecordsTimer;

  @override
  void initState() {
    super.initState();
    _timeString = _formatTime(DateTime.now());
    // 每秒更新一次時間
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) => _updateTime(),
    );

    // [New] 定期檢查缺漏紀錄數量
    _checkMissingRecords();
    _missingRecordsTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) => _checkMissingRecords(),
    );

    // [New] Check Permission with Rationale
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialPermission();
    });
  }

  Future<void> _checkInitialPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (mounted) {
        _showPermissionDialog();
      }
    } else if (permission == LocationPermission.deniedForever) {
      // Handle denied forever if needed
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must accept or deny
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('位置權限說明', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          '「別扣我」需要存取您的位置資訊，以便：\n\n'
          '1. 即時偵測行駛速度\n'
          '2. 比對目前路段速限\n'
          '3. 在背景執行時發出超速警報\n\n'
          '請在接下來的視窗中選擇「允許」，建議選擇「使用 App 期間允許」或「永遠允許」以獲得完整保護。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              // Then request permission via Provider
              Provider.of<SpeedProvider>(
                context,
                listen: false,
              ).requestLocationPermission();
            },
            child: const Text('我知道了', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _missingRecordsTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkMissingRecords() async {
    final count = await DatabaseHelper.instance.getMissingCount();
    if (mounted && count != _missingCount) {
      setState(() {
        _missingCount = count;
      });
    }
  }

  void _updateTime() {
    final String formatted = _formatTime(DateTime.now());
    if (mounted && _timeString != formatted) {
      setState(() {
        _timeString = formatted;
      });
    }
  }

  String _formatTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Consumer2 監聽 SpeedProvider 和 AppearanceProvider
    return Consumer2<SpeedProvider, AppearanceProvider>(
      builder: (context, provider, appearance, child) {
        // 1. 決定背景與文字顏色
        Color bgColor = appearance.bgColor; // 使用自訂背景
        Color textColor = appearance.textColor; // 使用自訂文字

        // [New] Determine orientation for conditional layout
        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;

        if (provider.alertStatus == AlertStatus.danger) {
          bgColor = const Color(0xFFB71C1C); // 紅色背景 (危險強制覆蓋)
          textColor = Colors.white;
        } else if (provider.alertStatus == AlertStatus.warning) {
          bgColor = const Color(0xFFFBC02D); // 黃色背景 (警告強制覆蓋)
          textColor = Colors.black; // 黃底黑字比較清楚
        }

        return Scaffold(
          backgroundColor: bgColor,

          // 側邊欄 (設定選單)
          drawer: _buildSettingsDrawer(context),

          body: SafeArea(
            child: Stack(
              children: [
                // --- 全域手勢：雙擊退出 HUD 模式 ---
                Positioned.fill(
                  child: GestureDetector(
                    onDoubleTap: () {
                      if (provider.isHudMode) {
                        provider.setHudMode(false);
                      }
                    },
                    behavior: HitTestBehavior.translucent, // 確保點擊穿透
                  ),
                ),

                // --- 左上角：漢堡選單按鈕 (HUD 模式隱藏) ---
                if (!provider.isHudMode)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Builder(
                      builder: (context) => IconButton(
                        icon: Icon(
                          Icons.menu,
                          color: textColor.withOpacity(0.7),
                          size: 32,
                        ),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                  ),

                // [New] Average Speed Zone Toggle (Next to Menu)
                if (!provider.isHudMode)
                  Positioned(
                    top: 10,
                    left: 60,
                    child: IconButton(
                      icon: Icon(
                        Icons.speed,
                        color: provider.isAvgSpeedActive
                            ? Colors.cyanAccent
                            : textColor.withOpacity(0.7),
                        size: 32,
                      ),
                      tooltip: "區間測速",
                      onPressed: () {
                        if (provider.isAvgSpeedActive) {
                          provider.stopAvgZone();
                        } else {
                          provider.startAvgZone();
                        }
                      },
                    ),
                  ),

                // [Fixed] Map Mode Button (Conditional Layout)
                if (!provider.isHudMode)
                  Positioned(
                    top: isPortrait
                        ? 60
                        : 10, // Portrait: Original (60), Landscape: Top Row (10)
                    left: isPortrait
                        ? 16
                        : 110, // Portrait: Left Col (16), Landscape: Row (110)
                    child: IconButton(
                      icon: Icon(
                        Icons.map,
                        color: provider.isMapVisible
                            ? Colors.greenAccent
                            : Colors.white.withOpacity(0.5),
                        size: isPortrait
                            ? 28
                            : 32, // Portrait: 28, Landscape: 32
                      ),
                      onPressed: () => provider.toggleMapVisibility(),
                    ),
                  ),

                // --- Right Top: Time & Info (Row Layout) ---
                // --- Right Top: Time & Info (Conditional Layout) ---
                Positioned(
                  top: 15,
                  right: 15,
                  child: isPortrait
                      ? Column(
                          // Portrait: Vertical Stack (Original)
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Time
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _timeString,
                                style: TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: textColor.withOpacity(0.9),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            // Info (Bearing / Altitude)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "方位: ${_getHeadingString(provider.currentHeading)}",
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "海拔: ${provider.currentAltitude.toStringAsFixed(0)} m",
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Row(
                          // Landscape: Horizontal Row (New)
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Time
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _timeString,
                                style: TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: textColor.withOpacity(0.9),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8), // Gap
                            // Info (Bearing / Altitude)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "方位: ${_getHeadingString(provider.currentHeading)}",
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "海拔: ${provider.currentAltitude.toStringAsFixed(0)} m",
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),

                // [Fixed] Top Center Area: HUD Toggle + Address
                if (!provider.isHudMode)
                  Positioned(
                    top: 15,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // HUD Button
                          IconButton(
                            icon: Icon(
                              provider.isHudMode
                                  ? Icons.flip_camera_android
                                  : Icons.branding_watermark,
                              color: textColor.withOpacity(0.5),
                            ),
                            tooltip: "切換 HUD 模式",
                            onPressed: () {
                              if (!provider.isMonitoring) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("請先點擊「開始偵測」才能使用 HUD 模式"),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              provider.setHudMode(!provider.isHudMode);
                              if (provider.isHudMode) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("已進入 HUD 模式，雙擊螢幕即可退出"),
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                          ),
                          // Address Display (Landscape ONLY - in Top Bar)
                          if (!isPortrait &&
                              provider.currentAddress.isNotEmpty &&
                              provider.currentAddress != "定位中...") ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              constraints: const BoxConstraints(maxWidth: 200),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.orangeAccent,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      provider.currentAddress,
                                      style: TextStyle(
                                        color: textColor.withOpacity(0.9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // 內容區：依據方向改變佈局 + HUD 鏡像翻轉
                Positioned.fill(
                  top: 60, // 避開頂部的漢堡選單和時鐘
                  child: Transform(
                    alignment: Alignment.center,
                    // 如果是 HUD 模式，沿 X 軸翻轉 (垂直鏡像)
                    transform: provider.isHudMode
                        ? (Matrix4.identity()..scale(1.0, -1.0, 1.0)) // 垂直翻轉
                        : Matrix4.identity(),
                    child: Column(
                      children: [
                        // [Restored] Address Display (Portrait ONLY - in Body)
                        if (isPortrait &&
                            provider.currentAddress.isNotEmpty &&
                            provider.currentAddress != "定位中...")
                          Container(
                            margin: const EdgeInsets.only(
                              top: 5,
                              bottom: 5,
                            ), // 減少一點邊距
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Colors.orangeAccent,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                // Constrain width in portrait so long addresses can wrap
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.65,
                                  ),
                                  child: Text(
                                    provider.currentAddress,
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.9),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: true,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        Expanded(
                          child: OrientationBuilder(
                            builder: (context, orientation) {
                              final isPortrait =
                                  orientation == Orientation.portrait;

                              final bool shouldHideControls =
                                  provider.currentSpeedKmh > 10;
                              // 只有在「不是 HUD 模式」且「速度 <= 10」時才顯示 Panel
                              final bool showPanel =
                                  !provider.isHudMode && !shouldHideControls;

                              if (isPortrait) {
                                return Column(
                                  children: [
                                    Expanded(
                                      child: _buildDashboard(
                                        provider,
                                        textColor,
                                        true,
                                        bgColor,
                                        appearance
                                            .gaugeColor, // [Pass] Gauge Color
                                        shouldHideControls, // [Pass]
                                      ),
                                    ),
                                    // [Animated] Control Panel Area
                                    AnimatedSize(
                                      duration: const Duration(
                                        milliseconds: 500,
                                      ),
                                      curve: Curves.easeInOut,
                                      child: SizedBox(
                                        height: showPanel ? null : 0,
                                        child: showPanel
                                            ? _buildControlPanel(
                                                context,
                                                provider,
                                                isPortrait,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                // 橫向模式：儀表板居中，控制台在下方
                                return Stack(
                                  children: [
                                    // 儀表板 (填滿)
                                    AnimatedPositioned(
                                      duration: const Duration(
                                        milliseconds: 500,
                                      ),
                                      curve: Curves.easeInOut,
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      bottom: showPanel
                                          ? 80
                                          : 0, // 當 Panel 隱藏時，延伸到底部
                                      child: _buildDashboard(
                                        provider,
                                        textColor,
                                        false,
                                        bgColor,
                                        appearance
                                            .gaugeColor, // [Pass] Gauge Color
                                        shouldHideControls, // [Pass]
                                      ),
                                    ),
                                    // 控制台 (置底)
                                    AnimatedPositioned(
                                      duration: const Duration(
                                        milliseconds: 500,
                                      ),
                                      curve: Curves.easeInOut,
                                      bottom: showPanel ? 0 : -100, // 向下移動隱藏
                                      left: 0,
                                      right: 0,
                                      child: _buildControlPanel(
                                        context,
                                        provider,
                                        isPortrait,
                                      ),
                                    ),
                                  ],
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // [New] Average Speed Zone Display (Floating)
                if (provider.isAvgSpeedActive)
                  Positioned(
                    top: 100, // Below top bar
                    left: 20,
                    right: 20, // Center horizontally
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.cyanAccent,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyanAccent.withOpacity(0.3),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "區間平均速率",
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              provider.avgSpeedKmh.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Courier',
                              ),
                            ),
                            const Text(
                              "km/h",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer,
                                  size: 14,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "${(provider.avgDurationSeconds / 60).floor()}m ${provider.avgDurationSeconds % 60}s",
                                  style: TextStyle(color: Colors.grey[300]),
                                ),
                                const SizedBox(width: 16),
                                Icon(
                                  Icons.straighten,
                                  size: 14,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "${(provider.avgDistanceMetres / 1000).toStringAsFixed(2)} km",
                                  style: TextStyle(color: Colors.grey[300]),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper to convert degrees to cardinal direction
  String _getHeadingString(double heading) {
    const directions = ['北', '東北', '東', '東南', '南', '西南', '西', '西北'];
    final index = ((heading + 22.5) / 45.0).floor() & 7;
    return "${directions[index]} (${heading.toStringAsFixed(0)}°)";
  }

  // --- 輔助 Widget 方法 ---

  Widget _buildDashboard(
    SpeedProvider provider,
    Color textColor,
    bool isPortrait,
    Color bgColor,
    Color gaugeColor, // [新增]
    bool shouldEnlarge, // [新增]
  ) {
    // 1. 時速顯示區塊
    Widget speedSection;

    if (provider.gaugeTheme != 'digital' && provider.gaugeTheme.isNotEmpty) {
      // [新增] Analog Gauge - 放大邏輯
      double baseSize = isPortrait ? 300 : 250;
      double size = shouldEnlarge ? baseSize * 1.3 : baseSize; // 放大 1.3 倍

      speedSection = AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        width: size,
        height: size,
        child: AnalogGauge(
          currentSpeed: provider.currentSpeedKmh,
          maxSpeed: 240,
          themeName: provider.gaugeTheme,
          customColor: gaugeColor, // [Pass] Apply custom color
        ),
      );
    } else {
      // Digital Gauge
      double fontSize = isPortrait ? 180 : 150;
      if (shouldEnlarge) fontSize *= 1.3;

      speedSection = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: textColor,
              height: 0.9,
              fontFamily: 'Courier', // Ensure consistent font
              shadows: [
                Shadow(
                  blurRadius: 20.0,
                  color: textColor.withOpacity(0.5),
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Text(provider.currentSpeedKmh.toStringAsFixed(0)),
          ),
          Text(
            "km/h",
            style: TextStyle(
              color: textColor.withOpacity(0.6),
              fontSize: isPortrait ? 20 : 18,
            ),
          ),
        ],
      );
    }

    // 2. 限速顯示區塊 (圓圈 + 資訊)
    Widget limitSection = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 限速牌
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          width: (isPortrait ? 70 : 90) * (shouldEnlarge ? 1.3 : 1.0),
          height: (isPortrait ? 70 : 90) * (shouldEnlarge ? 1.3 : 1.0),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFCC0000),
              width: isPortrait ? 6 : 8,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10),
            ],
          ),
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 500),
            style: TextStyle(
              color: Colors.black,
              fontSize: (isPortrait ? 28 : 36) * (shouldEnlarge ? 1.3 : 1.0),
              fontWeight: FontWeight.bold,
            ),
            child: Text("${provider.speedLimit}"),
          ),
        ),
        const SizedBox(width: 15),

        // 扣牌門檻資訊
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.5)),
              ),
              child: Text(
                "語音提醒: ${provider.speedLimit + provider.dangerTolerance}",
                style: const TextStyle(
                  color: Color(0xFFFFEB3B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  provider.isLimitFromOsm ? "OSM 自動" : "手動設定",
                  style: TextStyle(
                    color: provider.isLimitFromOsm
                        ? const Color(0xFF00FF00)
                        : textColor.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
                if (provider.isOsmFetching) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "更新中...",
                    style: TextStyle(
                      color: textColor.withOpacity(0.6),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );

    // [修改] 3. Mini Map widget - 改為背景式風格
    Widget? mapSection;
    if (provider.isMapVisible) {
      // 依照使用者需求：中間後面，往外延伸半透明
      // 使用 ShaderMask 製作漸層透明效果
      double mapWidth = (isPortrait ? 300 : 500) * (shouldEnlarge ? 1.4 : 1.0);
      double mapHeight = (isPortrait ? 250 : 300) * (shouldEnlarge ? 1.5 : 1.0);

      mapSection = Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          width: mapWidth,
          height: mapHeight,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Map Layer
              Opacity(
                opacity: 0.6, // [調整] 稍微更透明一點，讓它退到背景
                child: const MiniMap(),
              ),
              // 2. Vignette Layer (Gradient Overlay)
              // 這是用來製造 "往外延伸消失" 效果的關鍵
              // 中心透明 (看到地圖)，邊緣是背景色 (遮擋地圖)
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.8,
                    colors: [Colors.transparent, bgColor],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isPortrait) {
      // 直向：保持原樣，但 Map 放在中間
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [speedSection, const SizedBox(height: 40), limitSection],
      );
    } else {
      // 橫向佈局邏輯
      if (mapSection != null) {
        // [有地圖模式]: Stack 層疊佈局，時速跟限速往兩邊展開
        return Stack(
          alignment: Alignment.center,
          children: [
            // 1. Map Layer (Background)
            Positioned.fill(child: Center(child: mapSection)),

            // 2. Info Layer (Foreground) - 往左右展開
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // 左右撐開
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 左側時速
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: speedSection,
                    ),
                  ),
                ),

                // 右側限速
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 40),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: limitSection,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      } else {
        // [無地圖模式]: 保持置中靠攏
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [speedSection, const SizedBox(width: 60), limitSection],
        );
      }
    }
  }

  Widget _buildControlPanel(
    BuildContext context,
    SpeedProvider provider,
    bool isPortrait,
  ) {
    return Container(
      // 直向佔滿寬度，橫向自動寬度但要置中且有最大寬度
      width: isPortrait
          ? double.infinity
          : MediaQuery.of(context).size.width * 0.95,
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: isPortrait ? 15 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.95), // 加深背景色
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: isPortrait
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 直向：調整區 + 啟動按鈕
                _buildAdjustSection(provider, isPortrait),
                const SizedBox(height: 20),
                _buildStartButton(provider, height: 60),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 橫向：全部放一整排
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [_buildAdjustSection(provider, isPortrait)],
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 2,
                  child: _buildStartButton(provider, height: 50),
                ),
              ],
            ),
    );
  }

  // 修改後的調整區塊 (包含 -10, 顯示, +10)
  Widget _buildAdjustSection(SpeedProvider provider, bool isPortrait) {
    return Row(
      children: [
        _buildAdjustBtn("-10", () => provider.adjustLimit(-10), isPortrait),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: isPortrait ? 50 : 45, // 與按鈕高度一致
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF333333), // 增加背景色
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "${provider.speedLimit}",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isPortrait ? 28 : 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _buildAdjustBtn("+10", () => provider.adjustLimit(10), isPortrait),
      ],
    );
  }

  Widget _buildStartButton(SpeedProvider provider, {double height = 60}) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: () {
          if (provider.isMonitoring) {
            provider.stopMonitoring();
          } else {
            provider.startMonitoring();
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: provider.isMonitoring
              ? const Color(0xFFD32F2F)
              : const Color(0xFF007BFF), // 改為更亮的藍色
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 5,
          padding: EdgeInsets.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!provider.isMonitoring) ...[
              const Icon(
                Icons.rocket_launch,
                color: Colors.yellowAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              provider.isMonitoring ? "停止偵測" : "啟動偵測",
              style: TextStyle(
                fontSize: height < 50 ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 微調按鈕
  Widget _buildAdjustBtn(String label, VoidCallback onTap, bool isPortrait) {
    return SizedBox(
      width: isPortrait ? 70 : 60,
      height: isPortrait ? 50 : 45,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF444444),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: isPortrait ? 20 : 18, color: Colors.white),
        ),
      ),
    );
  }

  // 側邊欄 (設定選單)
  Widget _buildSettingsDrawer(BuildContext context) {
    return const SettingsDrawer();
  }
}

class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  late TextEditingController _textController;

  // [New] 缺漏紀錄通知邏輯
  int _missingCount = 0;
  Timer? _missingRecordsTimer;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<SpeedProvider>(context, listen: false);
    _textController = TextEditingController(text: provider.voiceMessage);

    // [New] 定期檢查缺漏紀錄數量
    _checkMissingRecords();
    _missingRecordsTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) => _checkMissingRecords(),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _missingRecordsTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkMissingRecords() async {
    final count = await DatabaseHelper.instance.getMissingCount();
    if (mounted && count != _missingCount) {
      setState(() {
        _missingCount = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 這裡使用 Consumer 只重繪必要的開關部分，而不影響 TextField
    // 這裡使用 Consumer2 同時監聽
    return Consumer2<SpeedProvider, AppearanceProvider>(
      builder: (context, provider, appearance, child) {
        return Drawer(
          backgroundColor: const Color(0xFF111111),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Color(0xFF222222)),
                child: Center(
                  child: Text(
                    '別扣我 - 測速系統',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // --- 紀錄中心 ---
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  "紀錄中心 (Records)",
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // 1. 行車紀錄
              ListTile(
                leading: const Icon(Icons.history, color: Colors.cyanAccent),
                title: const Text(
                  '行車紀錄 (Black Box)',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context); // Close Drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
              ),

              // 2. 缺漏標記
              // 2. 缺漏標記
              ListTile(
                leading: const Icon(
                  Icons.report_problem,
                  color: Colors.orangeAccent,
                ),
                title: const Text(
                  '缺漏標記 (Missing Data)',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: _missingCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_missingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(context); // Close Drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MissingRecordsScreen(),
                    ),
                  );
                },
              ),

              // 3. 本地紀錄
              ListTile(
                leading: const Icon(Icons.save_as, color: Colors.greenAccent),
                title: const Text(
                  '本地紀錄 (Local Records)',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context); // Close Drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LocalRecordsScreen(),
                    ),
                  );
                },
              ),

              // 3. 上傳紀錄
              ListTile(
                leading: const Icon(
                  Icons.cloud_done,
                  color: Colors.greenAccent,
                ),
                title: const Text(
                  '上傳紀錄 (Uploads)',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context); // Close Drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UploadHistoryScreen(),
                    ),
                  );
                },
              ),

              const Divider(color: Colors.grey),

              // --- 功能設定 ---
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  "功能設定 (Settings)",
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              ListTile(
                leading: const Icon(Icons.map, color: Colors.white),
                title: const Text(
                  'OSM 偵測',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: Switch(
                  value: provider.isOsmEnabled,
                  onChanged: (val) {
                    provider.setOsmEnabled(val);
                  },
                  activeColor: const Color(0xFF00FF00),
                ),
              ),

              ListTile(
                leading: const Icon(Icons.flip, color: Colors.white),
                title: const Text(
                  'HUD 抬頭顯示模式 (鏡像)',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: Switch(
                  value: provider.isHudMode,
                  onChanged: (val) {
                    if (val && !provider.isMonitoring) {
                      // 如果要開啟 HUD 但尚未開始偵測，顯示警告
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("請先點擊「開始偵測」才能使用 HUD 模式"),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return; // 不切換
                    }
                    provider.setHudMode(val);
                    if (val) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("已進入 HUD 模式，雙擊螢幕即可退出"),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                    Navigator.pop(context); // 關閉選單，因為模式切換畫面會變，關掉比較不暈
                  },
                  activeColor: const Color(0xFF00FF00),
                ),
              ),

              const Divider(color: Colors.grey),

              // [Modified] 主題選擇按鈕 (彈窗)
              ListTile(
                leading: const Icon(Icons.palette, color: Colors.purpleAccent),
                title: const Text(
                  '儀表板風格 (Theme)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _getThemeName(provider.gaugeTheme),
                  style: const TextStyle(color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(context); // Close Drawer
                  _showThemeDialog(context, provider);
                },
              ),

              const Divider(color: Colors.grey),

              // [New] 自定義顏色 (配色)
              ListTile(
                leading: const Icon(Icons.color_lens, color: Colors.pinkAccent),
                title: const Text(
                  '儀表板配色 (Colors)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: appearance.textColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "文字",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: appearance.bgColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "背景",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                onTap: () {
                  // Capture the scaffold's context before closing the drawer
                  final scaffoldContext = Scaffold.of(context).context;
                  Navigator.pop(context);
                  // Schedule showing the dialog after the drawer has closed
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _showColorPickerDialog(scaffoldContext, appearance);
                  });
                },
              ),

              const Divider(color: Colors.grey),

              // --- 語音提醒間隔設定 ---
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "超速語音提醒頻率: 每 ${provider.alertInterval} 秒",
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    Slider(
                      value: provider.alertInterval.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: "${provider.alertInterval} 秒",
                      activeColor: const Color(0xFF00FF00),
                      inactiveColor: Colors.grey,
                      onChanged: (val) {
                        provider.setAlertInterval(val.toInt());
                      },
                    ),
                    const Text(
                      "設定當持續超速時，語音重複播報的間隔時間",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.grey),

              // --- 寬容值設定 ---
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  "警示寬容值 (Tolerance Settings)",
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                title: const Text(
                  '語音提醒門檻',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '速限 +${provider.dangerTolerance} km/h',
                  style: const TextStyle(color: Colors.grey),
                ),
                trailing: SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle,
                          color: Colors.blueGrey,
                        ),
                        onPressed: () => provider.setDangerTolerance(
                          (provider.dangerTolerance - 1).clamp(20, 60),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: Colors.blueAccent,
                        ),
                        onPressed: () => provider.setDangerTolerance(
                          (provider.dangerTolerance + 1).clamp(20, 60),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                title: const Text(
                  '警示音預警',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '語音提醒門檻 -${provider.warningBuffer} km/h',
                  style: const TextStyle(color: Colors.grey),
                ),
                trailing: SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle,
                          color: Colors.blueGrey,
                        ),
                        onPressed: () => provider.setWarningBuffer(
                          (provider.warningBuffer - 1).clamp(2, 10),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: Colors.blueAccent,
                        ),
                        onPressed: () => provider.setWarningBuffer(
                          (provider.warningBuffer + 1).clamp(2, 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(color: Colors.grey),

              // --- 自定義語音輸入區 ---
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "超速語音自訂 (TTS)",
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF333333),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: "例如：嚴重超速！請煞車",
                        hintStyle: TextStyle(
                          color: Colors.grey.withOpacity(0.5),
                        ),
                      ),
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          provider.setVoiceMessage(value);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("語音已更新為：$value")),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          provider.setVoiceMessage(_textController.text);
                          Navigator.pop(context); // 關閉選單
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("設定已儲存 ✅")),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2979FF),
                        ),
                        child: const Text(
                          "儲存設定",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.grey),

              ListTile(
                leading: const Icon(Icons.volume_up, color: Colors.white),
                title: const Text(
                  '測試語音',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  final audioService = AudioService();
                  await audioService.init();
                  await audioService.speak(_textController.text);
                },
              ),

              ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.yellow),
                title: const Text(
                  '測試警示音 (嗶嗶聲)',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  final audioService = AudioService();
                  await audioService.init();
                  await audioService.playBeep(provider.customAlertSoundPath);
                },
              ),

              ListTile(
                leading: const Icon(Icons.music_note, color: Colors.cyanAccent),
                title: const Text(
                  '自定義警示音 (Custom Sound)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  provider.customAlertSoundPath != null
                      ? "已選: ${provider.customAlertSoundPath!.split('/').last}"
                      : "預設 (Default)",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                trailing: provider.customAlertSoundPath != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red),
                        onPressed: () {
                          provider.setCustomAlertSound(null);
                        },
                      )
                    : null,
                onTap: () async {
                  FilePickerResult? result = await FilePicker.platform
                      .pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['wav'],
                      );

                  if (result != null) {
                    File file = File(result.files.single.path!);
                    int sizeInBytes = file.lengthSync();
                    double sizeInMb = sizeInBytes / (1024 * 1024);

                    if (sizeInMb > 1.0) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('檔案過大！請選擇小於 1MB 的 .wav 檔案'),
                          ),
                        );
                      }
                      return;
                    }

                    // Copy to App Dir
                    final appDir = await getApplicationDocumentsDirectory();
                    final fileName = "custom_alert.wav";
                    final newPath = "${appDir.path}/$fileName";
                    await file.copy(newPath);

                    provider.setCustomAlertSound(newPath);

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('警示音已更新！請點擊上方「測試警示音」試聽。')),
                      );
                    }
                  }
                },
              ),

              const Divider(color: Colors.grey),

              // [新增] 行程統計儀表板
              ListTile(
                leading: const Icon(Icons.bar_chart, color: Colors.greenAccent),
                title: const Text(
                  '行程儀表板 (Stats Dashboard)',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StatsScreen(),
                    ),
                  );
                },
              ),

              const Divider(color: Colors.grey),

              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.white),
                title: const Text(
                  '關於我 (AboutMe)',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF222222),
                      title: const Text(
                        "關於別扣我 - 測速系統",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "版本: v1.0.0",
                            style: TextStyle(color: Colors.white70),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "這是一套專為台灣駕駛設計的測速照相預警系統，整合 OSM 圖資與即時 GPS 偵測。",
                            style: TextStyle(color: Colors.white70),
                          ),
                          SizedBox(height: 16),
                          Text(
                            "開發者: MiniKao",
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            "關閉",
                            style: TextStyle(color: Colors.cyanAccent),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const Divider(color: Colors.white24),

              // --- 關於我 (About) ---
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.blue),
                title: const Text(
                  '關於本 App',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF222222),
                      title: const Row(
                        children: [
                          Icon(Icons.shield, color: Colors.amber),
                          SizedBox(width: 8),
                          Text(
                            '別扣我 (Don\'t Suspend Me)',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '版本 v1.0.0',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '這是一款專為駕駛人設計的「主動防禦系統」。\n\n'
                            '不同於傳統測速 App 只報相機，我們整合 OpenStreetMap (OSM) 社群地圖資料，'
                            '即時監控路段速限，並在您可能因嚴重超速而面臨「扣牌」風險時，'
                            '主動發出語音警報。\n\n'
                            '特色功能：\n'
                            '• 自由設定警示寬容值\n'
                            '• OSM 社群圖資 + 本地修正\n'
                            '• 區間測速輔助\n'
                            '• 背景運作與缺漏回報',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.grey),
                          const SizedBox(height: 8),
                          const Text(
                            '聲明 (Disclaimer)：\n'
                            '本應用程式僅供輔助參考，圖資可能與實際路況有出入。'
                            '請務必遵守實際道路交通規則與速限標誌。'
                            '開發者不對因使用本軟體而產生的任何罰單或事故負責。',
                            style: TextStyle(color: Colors.grey, fontSize: 10),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            '了解',
                            style: TextStyle(color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  String _getThemeName(String key) {
    switch (key) {
      case 'digital':
        return '數位 (Digital)';
      case 'default':
        return '經典綠 (Classic)';
      case 'sport':
        return '熱血紅 (Sport)';
      case 'cyber':
        return '未來藍 (Cyber)';
      case 'luxury':
        return '奢華金 (Luxury)';
      default:
        return '預設';
    }
  }

  void _showThemeDialog(BuildContext context, SpeedProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('選擇儀表板風格'),
          backgroundColor: const Color(0xFF333333),
          titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20),
          children: [
            _buildThemeOption(
              ctx,
              provider,
              'digital',
              '數位 (Digital)',
              Colors.grey,
            ),
            _buildThemeOption(
              ctx,
              provider,
              'default',
              '指針 (Pointer)',
              Colors.cyanAccent,
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    SpeedProvider provider,
    String key,
    String label,
    Color color,
  ) {
    final isSelected = provider.gaugeTheme == key;
    return SimpleDialogOption(
      onPressed: () {
        provider.setGaugeTheme(key);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: isSelected
              ? Border(left: BorderSide(color: color, width: 4))
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? color : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  void _showColorPickerDialog(
    BuildContext context,
    AppearanceProvider appearance,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        // [Fix] Wrap in Consumer to ensure real-time sync between left (HSV) and right (Hue) pickers
        return Consumer<AppearanceProvider>(
          builder: (context, provider, child) {
            return DefaultTabController(
              length: 3, // [Fix] Increase count
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isLandscape =
                      MediaQuery.of(context).orientation ==
                      Orientation.landscape;
                  // [Fix] Increase dimensions slightly to prevent overflow
                  double width = isLandscape ? 800 : 500;
                  double height = isLandscape ? 450 : 700;

                  return AlertDialog(
                    backgroundColor: const Color(0xFF222222),
                    title: const Text(
                      '自訂配色',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: SizedBox(
                      width: width,
                      height: height,
                      child: Column(
                        children: [
                          const TabBar(
                            labelColor: Colors.amber,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: Colors.amber,
                            tabs: [
                              Tab(text: "文字顏色"),
                              Tab(text: "背景顏色"),
                              Tab(text: "指針顏色"), // [New]
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: TabBarView(
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _buildColorPickerTab(
                                  context,
                                  color:
                                      provider.textColor, // Use provider.color
                                  onColorChanged: (c) =>
                                      provider.setTextColor(c),
                                  isLandscape: isLandscape,
                                ),
                                _buildColorPickerTab(
                                  context,
                                  color: provider.bgColor, // Use provider.color
                                  onColorChanged: (c) => provider.setBgColor(c),
                                  isLandscape: isLandscape,
                                ),
                                _buildColorPickerTab(
                                  context,
                                  color: provider.gaugeColor, // [New]
                                  onColorChanged: (c) =>
                                      provider.setGaugeColor(c),
                                  isLandscape: isLandscape,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          provider.resetToDefaults();
                        },
                        child: const Text(
                          "恢復預設",
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          "完成",
                          style: TextStyle(color: Colors.cyanAccent),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildColorPickerTab(
    BuildContext dialogContext, {
    required Color color,
    required ValueChanged<Color> onColorChanged,
    required bool isLandscape,
  }) {
    // Left side: HSV Picker
    Widget picker = ColorPicker(
      pickerColor: color,
      onColorChanged: onColorChanged,
      labelTypes: const [],
      pickerAreaHeightPercent: 0.7,
      enableAlpha: false,
      portraitOnly: true,
      displayThumbColor: true,
    );

    // Right side: Hue Slider (Rainbow)
    Widget sliders = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isLandscape) ...[
          const Text(
            "RGB 微調",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 10),
        ],
        // [Fix] Removed restrictive SizedBox height to allow thumb to render without overflow
        // Added generous width for landscape
        SizedBox(
          width: isLandscape ? 300 : 260,
          child: ColorPicker(
            pickerColor: color,
            onColorChanged: onColorChanged,
            enableAlpha: false,
            displayThumbColor: true,
            pickerAreaHeightPercent: 0.0, // Shows only Hue slider
            portraitOnly: true,
            labelTypes: const [],
          ),
        ),
      ],
    );

    if (isLandscape) {
      final screenW = MediaQuery.of(dialogContext).size.width;
      // Allocate ~35% of width to right panel but clamp to reasonable min/max
      final panelWidth = screenW * 0.35;
      final clampedWidth = panelWidth.clamp(320.0, 520.0);
      // Make inner slider width adapt to panel width
      final sliderInnerWidth = (clampedWidth - 40).clamp(220.0, 480.0);

      // update sliders to use adaptive width when in landscape
      Widget adaptiveSliders = SizedBox(
        width: sliderInnerWidth,
        child: ColorPicker(
          pickerColor: color,
          onColorChanged: onColorChanged,
          enableAlpha: false,
          displayThumbColor: true,
          pickerAreaHeightPercent: 0.0,
          portraitOnly: true,
          labelTypes: const [],
        ),
      );

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: SingleChildScrollView(child: picker)),
          const SizedBox(width: 20),
          // Right side (adaptive width panel in landscape)
          SizedBox(
            width: clampedWidth,
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "RGB 微調",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  adaptiveSliders,
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      return SingleChildScrollView(
        child: Column(
          children: [
            ColorPicker(
              pickerColor: color,
              onColorChanged: onColorChanged,
              labelTypes: const [],
              pickerAreaHeightPercent: 0.4,
              enableAlpha: false,
              portraitOnly: true,
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    }
  }
}

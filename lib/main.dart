import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/speed_provider.dart';
import 'providers/appearance_provider.dart';
import 'screens/home_screen.dart';

// [修復] 引入背景服務檔案
import 'package:firebase_core/firebase_core.dart'; // [New]
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // [New]
import 'firebase_options.dart'; // [New]
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // [New] 初始化 Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // [New] 設定 Crashlytics 捕捉錯誤
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // [修復] 初始化背景服務 (這樣才能呼叫 initializeBackgroundService)
  await initializeBackgroundService();

  // Initialize Google Mobile Ads SDK
  // Google Mobile Ads removed in this build.

  // 允許直屏與橫屏
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const OverspeedDefenseApp());
}

class OverspeedDefenseApp extends StatelessWidget {
  const OverspeedDefenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SpeedProvider()),
        ChangeNotifierProvider(create: (_) => AppearanceProvider()),
      ],
      child: MaterialApp(
        title: '別扣我 - 測速系統',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          primaryColor: const Color(0xFF00FF00),
          textTheme: const TextTheme(
            displayLarge: TextStyle(
              fontSize: 120,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00FF00),
              height: 1.0,
            ),
            bodyMedium: TextStyle(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF222222),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

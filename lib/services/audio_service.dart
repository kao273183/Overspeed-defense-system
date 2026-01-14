import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'dart:io';

class AudioService {
  // 單例模式 (Singleton)
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
    bool _playerListenersAttached = false;
    bool _beepReleasedFocus = false;
  // [Changed] Make TTS non-final to allow re-instantiation
  late FlutterTts _tts;

  bool _isSessionConfigured = false;

  // [Changed] Promote session to member for manual activation
  late audio_session.AudioSession _session;

  /// 初始化：設定音訊 Session (這是讓 iOS 背景播放的關鍵)
  Future<void> init() async {
    if (_isSessionConfigured) return;

    // 1. Config Session
    _session = await audio_session.AudioSession.instance;
    await _session.configure(
      const audio_session.AudioSessionConfiguration(
        avAudioSessionCategory:
            audio_session.AVAudioSessionCategory.playback, // 背景播放模式
        avAudioSessionCategoryOptions: audio_session
            .AVAudioSessionCategoryOptions
            .duckOthers, // 壓低其他聲音 (Ducking)
        avAudioSessionMode: audio_session.AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            audio_session.AVAudioSessionRouteSharingPolicy.defaultPolicy,
        androidAudioAttributes: audio_session.AndroidAudioAttributes(
          contentType: audio_session.AndroidAudioContentType.speech,
          usage: audio_session
              .AndroidAudioUsage
              .assistanceNavigationGuidance, // [Restored] Correct for navigation
        ),
        androidAudioFocusGainType: audio_session
            .AndroidAudioFocusGainType
            .gainTransientMayDuck, // 讓其他聲音變小聲 (Ducking)
      ),
    );

    // 2. Init TTS
    await _initTts();

    _isSessionConfigured = true;
  }

  /// 初始化 TTS 實例與監聽器
  Future<void> _initTts() async {
    int retries = 3;
    while (retries > 0) {
      try {
        print("初始化 TTS 引擎 (剩餘嘗試: $retries)...");
        _tts = FlutterTts();

        // === Diagnostic: print platform and available TTS internals (safe runtime calls) ===
        try {
          print('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
        } catch (e) {
          print('無法取得 Platform 資訊: $e');
        }

        try {
          final dynamic t = _tts;
          final engines = await t.getEngines();
          print('TTS engines: $engines');
        } catch (e) {
          print('無法取得 TTS 引擎列表: $e');
        }

        try {
          final dynamic t = _tts;
          final voices = await t.getVoices();
          print('TTS voices: $voices');
        } catch (e) {
          print('無法取得 TTS voices: $e');
        }

        try {
          final dynamic t = _tts;
          final defaultEngine = await t.getDefaultEngine();
          print('TTS default engine: $defaultEngine');
        } catch (e) {
          print('無法取得 default engine (可能 Android-only): $e');
        }

        // 設定語言與語速
        await _tts.setLanguage("zh-TW");
        await _tts.setSpeechRate(0.5);
        // [Verified] Volume is handled by AudioPlayer in this new strategy,
        // but setting it here doesn't hurt for synthesis.
        await _tts.setVolume(1.0); // [New] Force max volume

        // [Crucial] Use non-blocking mode to prevent Binder deadlocks
        await _tts.awaitSpeakCompletion(false);

        // 設定監聽器 (確保播放結束能釋放焦點)
        _tts.setCompletionHandler(() {
          print("TTS 播放完成，釋放焦點");
          _session.setActive(false);
        });

        _tts.setCancelHandler(() {
          print("TTS 播放取消，釋放焦點");
          _session.setActive(false);
        });

        _tts.setErrorHandler((msg) {
          print("TTS Error Handler: $msg");
          _session.setActive(false);
        });

        print("TTS 引擎初始化成功");
        return; // Success
      } catch (e) {
        print("TTS 初始化失敗: $e");
        retries--;
        if (retries > 0) {
          print("等待 2 秒後重試...");
          await Future.delayed(const Duration(seconds: 2));
        } else {
          print("TTS 初始化最終失敗，放棄。");
        }
      }
    }
  }

  /// 播放警示音 (嗶嗶聲)
  Future<void> playBeep([String? customSoundPath]) async {
    try {
      // [New] Request Focus (Ducking)

      // Attach debug listeners once
      if (!_playerListenersAttached) {
        _player.onPlayerComplete.listen((_) {
          print('AudioPlayer: onPlayerComplete');
        });
        _player.onPlayerStateChanged.listen((state) {
          print('AudioPlayer: state -> $state');
        });
        _playerListenersAttached = true;
      }

      print('playBeep: starting (customPath=${customSoundPath ?? 'null'})');
      // Configure player for low-latency short sounds and request ducking
      try {
        await _player.setPlayerMode(PlayerMode.lowLatency);
        await _player.setAudioContext(AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ));
      } catch (e) {
        // ignore if platform doesn't support setAudioContext
        print('設定 AudioContext 失敗（可忽略）: $e');
      }

      // Also activate the audio session to align with audio_session package
      await _session.setActive(true);

      // 設定音量 1.0 (最大)
      await _player.setVolume(1.0);
      // Ensure player is stopped/reset before starting a new short sound
      try {
        await _player.stop();
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        print('playBeep: stop/reset warning: $e');
      }

      if (customSoundPath != null && customSoundPath.isNotEmpty) {
        // Play custom file from device storage
        await _player.play(DeviceFileSource(customSoundPath));
      } else {
        // Default beep
        await _player.play(AssetSource('sounds/beep.mp3'));
      }

      // [New] Wait for completion to restore volume (with timeout)
      try {
        await _player.onPlayerComplete.first.timeout(const Duration(seconds: 3));
        print('playBeep: completed');

        // Give the system a short moment to settle, then abandon audio focus
        try {
          await Future.delayed(const Duration(milliseconds: 200));
          await _session.setActive(false);
          _beepReleasedFocus = true;
          print('playBeep: released audio focus (duck restore)');
        } catch (e) {
          print('playBeep: failed releasing focus: $e');
        }
      } catch (e) {
        print('playBeep: completion timeout or error: $e');
      }
    } catch (e) {
      print("播放音效失敗: $e");
    } finally {
      // [New] Abandon Focus (Restore Music)
      try {
        if (!_beepReleasedFocus) {
          await _session.setActive(false);
          print('playBeep: released audio focus in finally');
        }
      } catch (e) {
        // ignore
      }
    }
  }

  /// 播放語音 (TTS) - Direct Speak with Safety Delay
  Future<void> speak(String text) async {
    try {
      print("TTS: 準備播放 -> $text");

      // 0. Safety Stop (Clear Buffer)
      await _tts.stop();

      // 1. Request Focus
      await _session.setActive(true);

      // 2. Safety Delay (Prevent Binder Deadlock)
      // Allow time for audio focus to switch and duck volume before pushing TTS data
      await Future.delayed(const Duration(milliseconds: 300));

      print("TTS: Audio Session 已啟用 (Duck) -> 執行說話");

      // 3. Direct Speak (Non-blocking)
      await _tts.speak(text);
      print("TTS: 指令已送出");

      // Focus released by setCompletionHandler or setErrorHandler
    } catch (e) {
      print("TTS 失敗: $e");

      // [Retry Logic via Re-init]
      try {
        print("偵測到 TTS 異常，嘗試重建引擎...");
        await Future.delayed(const Duration(seconds: 1));
        await _initTts();

        // Retry
        await _session.setActive(true);
        // Minimal delay on retry too
        await Future.delayed(const Duration(milliseconds: 200));
        await _tts.speak(text);
      } catch (retryError) {
        print("TTS 重試仍然失敗: $retryError");
      }
    }
  }
}

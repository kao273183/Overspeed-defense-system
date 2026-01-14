import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppearanceProvider with ChangeNotifier {
  // 預設顏色
  static const Color defaultTextColor = Color(0xFF00FF00); // 亮綠色
  static const Color defaultBgColor = Colors.black;
  static const Color defaultGaugeColor =
      Colors.cyanAccent; // Default gauge color

  Color _textColor = defaultTextColor;
  Color _bgColor = defaultBgColor;
  Color _gaugeColor = defaultGaugeColor;

  Color get textColor => _textColor;
  Color get bgColor => _bgColor;
  Color get gaugeColor => _gaugeColor;

  AppearanceProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final int? textColorValue = prefs.getInt('dashboard_text_color');
    final int? bgColorValue = prefs.getInt('dashboard_bg_color');
    final int? gaugeColorValue = prefs.getInt('dashboard_gauge_color');

    if (textColorValue != null) {
      _textColor = Color(textColorValue);
    }
    if (bgColorValue != null) {
      _bgColor = Color(bgColorValue);
    }
    if (gaugeColorValue != null) {
      _gaugeColor = Color(gaugeColorValue);
    }
    notifyListeners();
  }

  Future<void> setTextColor(Color color) async {
    _textColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dashboard_text_color', color.value);
  }

  Future<void> setBgColor(Color color) async {
    _bgColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dashboard_bg_color', color.value);
  }

  Future<void> setGaugeColor(Color color) async {
    _gaugeColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dashboard_gauge_color', color.value);
  }

  Future<void> resetToDefaults() async {
    _textColor = defaultTextColor;
    _bgColor = defaultBgColor;
    _gaugeColor = defaultGaugeColor;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dashboard_text_color');
    await prefs.remove('dashboard_bg_color');
    await prefs.remove('dashboard_gauge_color');
  }
}

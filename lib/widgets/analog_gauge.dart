import 'dart:math';
import 'package:flutter/material.dart';

class GaugeTheme {
  final String name;
  final Color mainColor;
  final Color tickColor;
  final Color faceColor;
  final Color needleColor;
  final Color textColor;

  const GaugeTheme({
    required this.name,
    required this.mainColor,
    required this.tickColor,
    required this.faceColor,
    required this.needleColor,
    required this.textColor,
  });

  static const defaultTheme = GaugeTheme(
    name: '經典綠',
    mainColor: Color(0xFF00FF00),
    tickColor: Colors.white,
    faceColor: Colors.transparent,
    needleColor: Color(0xFF00FF00),
    textColor: Color(0xFF00FF00),
  );

  static const sportTheme = GaugeTheme(
    name: '熱血紅',
    mainColor: Color(0xFFF44336),
    tickColor: Color(0xFFEEEEEE),
    faceColor: Color(0xFF2B0000),
    needleColor: Color(0xFFF44336),
    textColor: Color(0xFFFFCDD2),
  );

  static const cyberTheme = GaugeTheme(
    name: '未來藍',
    mainColor: Color(0xFF00E5FF),
    tickColor: Color(0xFF00E5FF),
    faceColor: Color(0xFF001014),
    needleColor: Colors.white,
    textColor: Color(0xFF00E5FF),
  );

  static const luxuryTheme = GaugeTheme(
    name: '奢華金',
    mainColor: Color(0xFFFFD700),
    tickColor: Color(0xFFFFECB3),
    faceColor: Color(0xFF1A1200),
    needleColor: Color(0xFFFFD700),
    textColor: Color(0xFFFFD700),
  );

  static const Map<String, GaugeTheme> themes = {
    'default': defaultTheme,
    'sport': sportTheme,
    'cyber': cyberTheme,
    'luxury': luxuryTheme,
  };
}

class AnalogGauge extends StatelessWidget {
  final double currentSpeed;
  final double maxSpeed;
  final String themeName;
  final Color? customColor; // [New] Custom override color

  const AnalogGauge({
    super.key,
    required this.currentSpeed,
    this.maxSpeed = 240,
    this.themeName = 'default',
    this.customColor, // [New]
  });

  @override
  Widget build(BuildContext context) {
    // [Fix] Construct theme if custom color is provided
    GaugeTheme effectiveTheme;
    if (customColor != null) {
      effectiveTheme = GaugeTheme(
        name: 'custom',
        mainColor: customColor!,
        tickColor: Colors.white,
        faceColor: Colors.transparent,
        needleColor: customColor!,
        textColor: customColor!,
      );
    } else {
      effectiveTheme = GaugeTheme.themes[themeName] ?? GaugeTheme.defaultTheme;
    }

    return CustomPaint(
      size: const Size(300, 300),
      painter: GaugePainter(
        speed: currentSpeed,
        maxSpeed: maxSpeed,
        theme: effectiveTheme, // Use determined theme
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final GaugeTheme theme;

  GaugePainter({
    required this.speed,
    required this.maxSpeed,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) - 10;

    // Background Face
    if (theme.faceColor != Colors.transparent) {
      final facePaint = Paint()
        ..color = theme.faceColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius + 5, facePaint);
    }

    // Outer Arc
    final arcPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15;

    // 0.75 PI to 2.25 PI (Start at 135 degrees, sweep 270 degrees)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.75 * pi,
      1.5 * pi,
      false,
      arcPaint,
    );

    // Ticks and Numbers
    final tickPaint = Paint()
      ..color = theme.tickColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    const int totalTicks = 12; // 0 to 240, step 20
    const double stepValue = 20;

    for (int i = 0; i <= totalTicks; i++) {
      double value = i * stepValue;
      double ratio =
          value / maxSpeed; // Assuming maxSpeed matches the scale end
      double angle = 0.75 * pi + ratio * 1.5 * pi;

      // Draw Ticks
      double x1 = center.dx + (radius - 10) * cos(angle);
      double y1 = center.dy + (radius - 10) * sin(angle);
      double x2 = center.dx + radius * cos(angle);
      double y2 = center.dy + radius * sin(angle);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), tickPaint);

      // Draw Text
      // [Fix] Move text closer to edge (radius - 30) to reduce crowding
      double tx = center.dx + (radius - 30) * cos(angle);
      double ty = center.dy + (radius - 30) * sin(angle);

      textPainter.text = TextSpan(
        text: value.toInt().toString(),
        style: const TextStyle(
          color: Color(0xFFAAAAAA),
          fontSize: 12, // [Fix] Slightly smaller font
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(tx - textPainter.width / 2, ty - textPainter.height / 2),
      );
    }

    // Needle
    double displaySpeed = speed.clamp(0, maxSpeed);
    double needleAngle = 0.75 * pi + (displaySpeed / maxSpeed) * 1.5 * pi;

    final needlePaint = Paint()
      ..color = theme.needleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Add shadow
    final shadowPath = Path();
    shadowPath.moveTo(center.dx, center.dy);
    shadowPath.lineTo(
      center.dx + (radius - 20) * cos(needleAngle),
      center.dy + (radius - 20) * sin(needleAngle),
    );
    canvas.drawShadow(
      shadowPath,
      theme.needleColor.withOpacity(0.5),
      4.0,
      true,
    );

    canvas.drawLine(
      center,
      Offset(
        center.dx + (radius - 20) * cos(needleAngle),
        center.dy + (radius - 20) * sin(needleAngle),
      ),
      needlePaint,
    );

    // Center Cap
    final capPaint = Paint()..color = const Color(0xFF555555);
    canvas.drawCircle(center, 10, capPaint);

    // Speed Text in Center
    final speedTextPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    speedTextPainter.text = TextSpan(
      text: speed.round().toString(),
      style: TextStyle(
        color: theme.mainColor,
        fontSize: 40,
        fontWeight: FontWeight.bold,
      ),
    );
    speedTextPainter.layout();
    speedTextPainter.paint(
      canvas,
      Offset(center.dx - speedTextPainter.width / 2, center.dy + 30),
    );

    final unitTextPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    unitTextPainter.text = TextSpan(
      text: 'km/h',
      style: TextStyle(color: theme.textColor, fontSize: 16),
    );
    unitTextPainter.layout();
    unitTextPainter.paint(
      canvas,
      Offset(center.dx - unitTextPainter.width / 2, center.dy + 70),
    );
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) {
    return oldDelegate.speed != speed ||
        oldDelegate.theme.name != theme.name ||
        oldDelegate.maxSpeed != maxSpeed;
  }
}

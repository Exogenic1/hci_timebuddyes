import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:math' show max;

class AnalogClockWidget extends StatefulWidget {
  final double size;

  const AnalogClockWidget({
    super.key,
    this.size =
        150.0, // Default size reduced from 180.0 to 150.0 to better fit container
  });

  @override
  State<AnalogClockWidget> createState() => _AnalogClockWidgetState();
}

class _AnalogClockWidgetState extends State<AnalogClockWidget> {
  late Timer _timer;
  DateTime _dateTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _dateTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: AnalogClockPainter(_dateTime),
      ),
    );
  }
}

class AnalogClockPainter extends CustomPainter {
  final DateTime dateTime;

  AnalogClockPainter(this.dateTime);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final center = Offset(centerX, centerY);
    final radius = size.width / 2;

    // Scale factors based on the size
    final scaleFactor = size.width / 250; // Original design was for 250px

    // Draw clock face with gradient
    final gradient = RadialGradient(
      colors: [Colors.white, Colors.grey.shade100],
      stops: const [0.8, 1.0],
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.blue.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * scaleFactor;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw hour markers - simplified for smaller sizes
    final markerPaint = Paint()..color = Colors.black87;
    for (int i = 1; i <= 12; i++) {
      final angle = (i * 30) * (math.pi / 180);
      // Smaller markers overall and only draw larger ones at key positions
      final markerRadius =
          (i % 3 == 0 ? 6.0 : 3.0) * scaleFactor; // Reduced marker size
      final markerPos = Offset(
        centerX +
            (radius - 15 * scaleFactor) *
                math.cos(angle - math.pi / 2), // Moved markers inward
        centerY + (radius - 15 * scaleFactor) * math.sin(angle - math.pi / 2),
      );
      canvas.drawCircle(markerPos, markerRadius, markerPaint);
    }

    // Draw numbers
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    // Scale text size based on clock size, but ensure it doesn't get too small
    final textStyle = TextStyle(
        color: Colors.black87,
        fontSize: max(
            8.0,
            16 *
                scaleFactor), // Ensure minimum readable size with slightly reduced base size
        fontWeight: FontWeight.bold);

    for (int i = 3; i <= 12; i += 3) {
      // Only draw 3, 6, 9, 12
      final angle = (i * 30) * (math.pi / 180);
      final x =
          centerX + (radius - 45 * scaleFactor) * math.cos(angle - math.pi / 2);
      final y =
          centerY + (radius - 45 * scaleFactor) * math.sin(angle - math.pi / 2);
      textPainter.text = TextSpan(text: '$i', style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas,
          Offset(x - textPainter.width / 2, y - textPainter.height / 2));
    }

    // Draw center circle
    final centerDotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4 * scaleFactor, centerDotPaint);

    // Draw hour hand
    final hourHandPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 6 * scaleFactor
      ..strokeCap = StrokeCap.round;
    final hourAngle =
        (dateTime.hour % 12 + dateTime.minute / 60) * 30 * (math.pi / 180);
    canvas.drawLine(
        center,
        Offset(centerX + radius * 0.5 * math.cos(hourAngle - math.pi / 2),
            centerY + radius * 0.5 * math.sin(hourAngle - math.pi / 2)),
        hourHandPaint);

    // Draw minute hand
    final minuteHandPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 4 * scaleFactor
      ..strokeCap = StrokeCap.round;
    final minuteAngle = dateTime.minute * 6 * (math.pi / 180);
    canvas.drawLine(
        center,
        Offset(centerX + radius * 0.7 * math.cos(minuteAngle - math.pi / 2),
            centerY + radius * 0.7 * math.sin(minuteAngle - math.pi / 2)),
        minuteHandPaint);

    // Draw second hand
    final secondHandPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2 * scaleFactor
      ..strokeCap = StrokeCap.round;
    final secondAngle = dateTime.second * 6 * (math.pi / 180);
    canvas.drawLine(
        center,
        Offset(centerX + radius * 0.8 * math.cos(secondAngle - math.pi / 2),
            centerY + radius * 0.8 * math.sin(secondAngle - math.pi / 2)),
        secondHandPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

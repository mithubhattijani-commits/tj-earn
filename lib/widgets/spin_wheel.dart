import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';

/// Daily spin wheel (Roz Dhan-style).
///
/// One free spin per day. The server picks a weighted-random reward.
/// The wheel animates and lands on the winning segment.
class SpinWheel extends StatefulWidget {
  const SpinWheel({super.key});

  @override
  State<SpinWheel> createState() => _SpinWheelState();
}

class _SpinWheelState extends State<SpinWheel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _spinning = false;
  String? _message;
  bool _isError = false;

  // Segment rewards (must match server config spin_rewards)
  final List<int> _segments = [1, 2, 3, 5, 10, 20];
  final List<Color> _colors = [
    Colors.red.shade400,
    Colors.blue.shade400,
    Colors.green.shade400,
    Colors.orange.shade400,
    Colors.purple.shade400,
    Colors.teal.shade400,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_spinning) return;
    final t = AppLocalizations.of(context)!;
    setState(() {
      _spinning = true;
      _message = t.spinSpinning;
      _isError = false;
    });

    try {
      final result = await SupabaseService.claimSpin();
      final coins = result['reward_coins'] as int? ?? 0;

      if (!mounted) return;

      // Find the segment index for the won amount
      var winIndex = _segments.indexOf(coins);
      if (winIndex < 0) winIndex = 0;

      // Animate to land on the winning segment
      // Each segment is 360/6 = 60 degrees
      final segmentAngle = 2 * math.pi / _segments.length;
      // Target: rotate so winning segment is at top (with 5 full rotations)
      final targetRotations = 5 * 2 * math.pi;
      final targetAngle = targetRotations +
          (2 * math.pi - (winIndex * segmentAngle + segmentAngle / 2));

      _animation = Tween<double>(
        begin: _animation.value,
        end: _animation.value + targetAngle,
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      );

      _controller.reset();
      await _controller.forward();

      if (!mounted) return;
      setState(() {
        _message = t.spinWon(coins.toString());
        _spinning = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _message = msg.contains('limit_reached') ||
                msg.contains('409')
            ? t.spinUsed
            : (msg.isEmpty ? t.genericError : msg);
        _isError = true;
        _spinning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              t.spinTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              t.spinSubtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            // Wheel
            SizedBox(
              width: 200,
              height: 200,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _animation.value,
                    child: CustomPaint(
                      painter: _WheelPainter(
                        segments: _segments,
                        colors: _colors,
                      ),
                      size: const Size(200, 200),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _spinning ? null : _spin,
              icon: _spinning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.casino),
              label: Text(_spinning ? t.spinSpinning : t.spinButton),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isError
                      ? Theme.of(context).colorScheme.error
                      : Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Paints the spin wheel segments.
class _WheelPainter extends CustomPainter {
  final List<int> segments;
  final List<Color> colors;

  _WheelPainter({required this.segments, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segmentAngle = 2 * math.pi / segments.length;

    for (var i = 0; i < segments.length; i++) {
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * segmentAngle - math.pi / 2,
        segmentAngle,
        true,
        paint,
      );

      // Draw the coin value
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${segments[i]}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final angle = i * segmentAngle + segmentAngle / 2 - math.pi / 2;
      final textOffset = Offset(
        center.dx + (radius * 0.65) * math.cos(angle) - textPainter.width / 2,
        center.dy + (radius * 0.65) * math.sin(angle) - textPainter.height / 2,
      );
      textPainter.paint(canvas, textOffset);
    }

    // Center hub
    final hubPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 20, hubPaint);

    // Pointer at top
    final pointerPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    final pointerPath = Path()
      ..moveTo(center.dx - 10, 0)
      ..lineTo(center.dx + 10, 0)
      ..lineTo(center.dx, 20)
      ..close();
    canvas.drawPath(pointerPath, pointerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

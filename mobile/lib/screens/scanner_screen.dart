import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/app_theme.dart';

class ScannerScreen extends StatefulWidget {
  final String title;

  const ScannerScreen({super.key, this.title = 'Scan Barcode'});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  bool _isScanned = false;
  bool _torchOn = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final MobileScannerController _scannerController = MobileScannerController();
  late final AnimationController _laserController;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _laserController.dispose();
    _scannerController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.45),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Toggle Flashlight',
            onPressed: () async {
              await _scannerController.toggleTorch();
              if (mounted) {
                setState(() => _torchOn = !_torchOn);
              }
            },
            icon: Icon(
              _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torchOn ? AppTheme.accentAmber : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Switch Camera',
            onPressed: () => _scannerController.switchCamera(),
            icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) async {
              if (_isScanned) return;

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? code = barcodes.first.rawValue;
                if (code != null) {
                  setState(() => _isScanned = true);
                  HapticFeedback.mediumImpact();

                  final navigator = Navigator.of(context);

                  try {
                    await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
                  } catch (e) {
                    debugPrint('Error playing scan sound: $e');
                  }

                  await Future.delayed(const Duration(milliseconds: 220));

                  if (mounted) {
                    navigator.pop(code);
                  }
                }
              }
            },
          ),

          // Darkened Scrim + Corner Bracket Viewfinder
          CustomPaint(
            painter: _ScannerOverlayPainter(
              frameSize: 260,
              accentColor:
                  _isScanned ? AppTheme.accentTeal : AppTheme.accentOrange,
            ),
          ),

          // Animated Scan Line
          Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: AnimatedBuilder(
                animation: _laserController,
                builder: (context, _) {
                  return Align(
                    alignment: Alignment(0, (_laserController.value * 2) - 1),
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppTheme.accentOrange.withValues(alpha: 0.9),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentOrange.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Instruction Pill
          Positioned(
            bottom: 56,
            left: 24,
            right: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isScanned
                          ? Icons.check_circle_rounded
                          : Icons.center_focus_strong_rounded,
                      size: 18,
                      color: _isScanned
                          ? AppTheme.accentTeal
                          : AppTheme.accentOrange,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isScanned
                          ? 'Barcode captured!'
                          : 'Center barcode inside the frame',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final double frameSize;
  final Color accentColor;

  _ScannerOverlayPainter({
    required this.frameSize,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final cutoutRect = Rect.fromCenter(
      center: center,
      width: frameSize,
      height: frameSize,
    );
    final cutoutRRect = RRect.fromRectAndRadius(
      cutoutRect,
      const Radius.circular(22),
    );

    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRRect(cutoutRRect);
    final scrimPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(
      scrimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    // Subtle full border
    canvas.drawRRect(
      cutoutRRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Glowing corner brackets
    final bracketPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerLen = 28.0;
    const r = 22.0;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(cutoutRect.left, cutoutRect.top + cornerLen)
        ..lineTo(cutoutRect.left, cutoutRect.top + r)
        ..arcToPoint(
          Offset(cutoutRect.left + r, cutoutRect.top),
          radius: const Radius.circular(r),
        )
        ..lineTo(cutoutRect.left + cornerLen, cutoutRect.top),
      bracketPaint,
    );

    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(cutoutRect.right - cornerLen, cutoutRect.top)
        ..lineTo(cutoutRect.right - r, cutoutRect.top)
        ..arcToPoint(
          Offset(cutoutRect.right, cutoutRect.top + r),
          radius: const Radius.circular(r),
        )
        ..lineTo(cutoutRect.right, cutoutRect.top + cornerLen),
      bracketPaint,
    );

    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(cutoutRect.left, cutoutRect.bottom - cornerLen)
        ..lineTo(cutoutRect.left, cutoutRect.bottom - r)
        ..arcToPoint(
          Offset(cutoutRect.left + r, cutoutRect.bottom),
          radius: const Radius.circular(r),
          clockwise: false,
        )
        ..lineTo(cutoutRect.left + cornerLen, cutoutRect.bottom),
      bracketPaint,
    );

    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(cutoutRect.right - cornerLen, cutoutRect.bottom)
        ..lineTo(cutoutRect.right - r, cutoutRect.bottom)
        ..arcToPoint(
          Offset(cutoutRect.right, cutoutRect.bottom - r),
          radius: const Radius.circular(r),
          clockwise: false,
        )
        ..lineTo(cutoutRect.right, cutoutRect.bottom - cornerLen),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.frameSize != frameSize;
}

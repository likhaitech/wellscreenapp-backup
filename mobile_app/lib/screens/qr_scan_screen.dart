import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';

/// Full-screen camera scanner used by the child-side pairing flow as a
/// faster alternative to typing the parent's 6-digit pairing code by hand.
///
/// This does not talk to Firestore itself - it only reads whatever text is
/// encoded in the QR image (the parent side encodes the raw pairing code,
/// nothing else) and pops back with that string via [Navigator.pop]. The
/// caller (child_home_screen.dart's pairing card) is what actually
/// validates and submits the code through the existing manual-entry
/// `pairWithParent()` flow - scanning is purely a data-entry shortcut, not
/// a second, separate pairing path with its own trust decisions.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      // The parent side encodes the plain 6-digit code (see
      // device_pairing_screen.dart's _generatedCodeCard), so this just
      // strips anything that isn't a digit rather than assuming the QR
      // payload arrives pre-cleaned.
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 6) continue;

      _handled = true;
      Navigator.of(context).pop(digits);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Scan Pairing QR Code',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Toggle flash',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on_rounded),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Text(
              'Point the camera at the QR code shown on the parent\'s screen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

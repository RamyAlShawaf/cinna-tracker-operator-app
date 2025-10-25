import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/theme_controller.dart';
import '../widgets/theme_mode_button.dart';

class QrScannerScreen extends StatefulWidget {
  final ThemeController themeController;
  const QrScannerScreen({super.key, required this.themeController});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR'),
        actions: [ThemeModeButton(controller: widget.themeController)],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) async {
                if (_handled) return;
                final barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final value = barcodes.first.rawValue;
                  if (value != null) {
                    _handled = true;
                    try {
                      await _controller.stop();
                    } catch (_) {}
                    if (!mounted) return;
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop(value);
                    }
                  }
                }
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          _torchOn = !_torchOn;
                          await _controller.toggleTorch();
                          if (mounted) setState(() {});
                        } catch (_) {}
                      },
                      icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                      label: const Text('Torch'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          await _controller.switchCamera();
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.cameraswitch),
                      label: const Text('Camera'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Subtle frame overlay
          IgnorePointer(
            child: Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.primary.withOpacity(0.6), width: 3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}



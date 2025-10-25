import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';
import '../widgets/theme_mode_button.dart';
import 'qr_scanner_screen.dart';
import 'tracking_screen.dart';

class HomeScreen extends StatefulWidget {
  final ThemeController themeController;
  const HomeScreen({super.key, required this.themeController});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void dispose() {
    super.dispose();
  }

  String _extractCode(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final idx = uri.pathSegments.indexOf('v');
      if (idx != -1 && uri.pathSegments.length > idx + 1) {
        return uri.pathSegments[idx + 1];
      }
    }
    return raw.trim();
  }

  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => QrScannerScreen(themeController: widget.themeController)),
    );
    if (!mounted) return;
    if (code != null && code.isNotEmpty) {
      final publicCode = _extractCode(code);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TrackingScreen(publicCode: publicCode, themeController: widget.themeController)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cinna Operator'),
        actions: [ThemeModeButton(controller: widget.themeController)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text('Get rolling', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Scan the bus QR to start a session.',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(backgroundColor: cs.primaryContainer, child: Icon(Icons.qr_code_scanner, color: cs.onPrimaryContainer)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Scan QR', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Fastest way to begin tracking', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    ElevatedButton(onPressed: _scanQr, child: const Text('Scan')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



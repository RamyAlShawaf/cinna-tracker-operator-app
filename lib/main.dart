import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const OperatorApp());
}

class OperatorApp extends StatelessWidget {
  const OperatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cinna Operator',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? publicCode;
  String? sessionId;
  String? publishToken;
  StreamSubscription<Position>? positionSub;
  bool tracking = false;
  String status = '';
  String serverUrl = const String.fromEnvironment('BACKEND_URL', defaultValue: 'http://10.0.2.2:3000');

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('server_url');
    if (saved != null && saved.isNotEmpty) {
      setState(() => serverUrl = saved);
    }
  }

  Future<void> _editServerUrl() async {
    final controller = TextEditingController(text: serverUrl);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'http://192.168.x.x:3000'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', v);
      setState(() => serverUrl = v);
    }
  }

  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (code != null && code.isNotEmpty) {
      setState(() => publicCode = _extractCode(code));
    }
  }

  String _extractCode(String raw) {
    // Accept full URL like https://track.site/v/ONX-102 or just ONX-102
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final idx = uri.pathSegments.indexOf('v');
      if (idx != -1 && uri.pathSegments.length > idx + 1) {
        return uri.pathSegments[idx + 1];
      }
    }
    return raw.trim();
  }

  Future<void> _startSession() async {
    if (publicCode == null) return;
    setState(() => status = 'Starting session...');
    final url = serverUrl;
    try {
      final r = await http
          .post(
            Uri.parse('$url/api/operator/session/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'public_code': publicCode}),
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        sessionId = data['session_id'] as String?;
        publishToken = data['publish_token'] as String?;
        setState(() => status = 'Session started');
      } else {
        setState(() => status = 'Failed: ${r.statusCode} ${r.body}');
      }
    } catch (e) {
      setState(() => status = 'Network error: $e');
    }
  }

  Future<void> _beginTracking() async {
    if (publishToken == null) return;
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => status = 'Location permission denied');
      return;
    }
    setState(() => tracking = true);
    final url = serverUrl;
    positionSub?.cancel();
    positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 10),
    ).listen((pos) async {
      final payload = {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'speed': pos.speed,
        'heading': pos.heading,
        'accuracy': pos.accuracy,
        'ts': DateTime.now().toIso8601String(),
      };
      try {
        await http.post(
          Uri.parse('$url/api/operator/ping?token=$publishToken'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (_) {}
    });
  }

  Future<void> _endSession() async {
    final sid = sessionId;
    if (sid == null) return;
    positionSub?.cancel();
    setState(() => tracking = false);
    final url = serverUrl;
    await http.post(
      Uri.parse('$url/api/operator/session/end'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'session_id': sid}),
    );
    setState(() => status = 'Session ended');
  }

  @override
  void dispose() {
    positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operator'),
        actions: [
          IconButton(onPressed: _editServerUrl, icon: const Icon(Icons.settings)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    publicCode == null ? 'Scan a vehicle QR to begin' : 'Code: $publicCode',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                ElevatedButton(onPressed: _scanQr, child: const Text('Scan QR')),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(onPressed: publicCode == null ? null : _startSession, child: const Text('Start Session')),
                ElevatedButton(
                  onPressed: publicCode == null || tracking ? null : _beginTracking,
                  child: const Text('Begin Tracking'),
                ),
                ElevatedButton(onPressed: publicCode == null ? null : _endSession, child: const Text('End Trip')),
              ],
            ),
            const SizedBox(height: 16),
            Text('Server: $serverUrl'),
            const SizedBox(height: 8),
            Text('Status: $status'),
          ],
        ),
      ),
    );
  }
}

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: MobileScanner(
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
    );
  }
}

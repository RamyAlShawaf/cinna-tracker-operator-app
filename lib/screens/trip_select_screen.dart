import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/theme_controller.dart';
import '../widgets/theme_mode_button.dart';

class TripSelectScreen extends StatefulWidget {
  final String publicCode;
  final ThemeController themeController;
  const TripSelectScreen({super.key, required this.publicCode, required this.themeController});

  @override
  State<TripSelectScreen> createState() => _TripSelectScreenState();
}

class _TripSelectScreenState extends State<TripSelectScreen> {
  final String serverUrl = const String.fromEnvironment('BACKEND_URL', defaultValue: 'https://www.cinna.app');
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> trips = const [];
  String? sessionId;
  String? publishToken;
  String? selectedTripId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() { loading = true; error = null; });
    try {
      // 1) Start session (as before)
      final r = await http.post(
        Uri.parse('$serverUrl/api/operator/session/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'public_code': widget.publicCode}),
      );
      if (r.statusCode != 200) {
        setState(() { error = 'Failed to start session (${r.statusCode})'; loading = false; });
        return;
      }
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      sessionId = data['session_id'] as String?;
      publishToken = data['publish_token'] as String?;
      if (sessionId == null || publishToken == null) {
        setState(() { error = 'Invalid session response'; loading = false; });
        return;
      }

      // 2) Fetch trips for this vehicle/company
      final r2 = await http.get(
        Uri.parse('$serverUrl/api/operator/trips?code=${Uri.encodeQueryComponent(widget.publicCode)}'),
      );
      if (r2.statusCode != 200) {
        setState(() { error = 'Failed to load trips (${r2.statusCode})'; loading = false; });
        return;
      }
      final j2 = jsonDecode(r2.body) as Map<String, dynamic>;
      final list = (j2['trips'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        trips = list;
        loading = false;
      });
    } catch (e) {
      setState(() { error = 'Network error: $e'; loading = false; });
    }
  }

  Future<void> _assignAndContinue() async {
    final tid = selectedTripId;
    final sid = sessionId;
    if (tid == null || sid == null) return;
    setState(() { loading = true; error = null; });
    try {
      final r = await http.post(
        Uri.parse('$serverUrl/api/operator/session/assign'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': sid, 'trip_id': tid}),
      );
      if (r.statusCode != 200) {
        setState(() { error = 'Failed to assign trip (${r.statusCode})'; loading = false; });
        return;
      }
      if (!mounted) return;
      Navigator.pop(context, {
        'session_id': sessionId,
        'publish_token': publishToken,
      });
    } catch (e) {
      setState(() { error = 'Network error: $e'; loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Trip'),
        actions: [ThemeModeButton(controller: widget.themeController)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text(error!))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bus code: ${widget.publicCode}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      if (trips.isEmpty)
                        const Text('No trips found for this vehicle/company.'),
                      if (trips.isNotEmpty)
                        Expanded(
                          child: ListView.builder(
                            itemCount: trips.length,
                            itemBuilder: (context, i) {
                              final t = trips[i];
                              final id = t['id'] as String;
                              final name = t['name'] as String? ?? 'Trip';
                              final code = t['code'] as String?;
                              final selected = selectedTripId == id;
                              return ListTile(
                                title: Text(name),
                                subtitle: code != null ? Text(code) : null,
                                trailing: selected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                                onTap: () => setState(() { selectedTripId = id; }),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context); // back to home
                              },
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: selectedTripId != null ? _assignAndContinue : null,
                              child: const Text('Continue'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}

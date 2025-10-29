import 'dart:async';
import 'dart:convert';
// import 'dart:math' as math; // no longer needed after removing raindrop pin
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../theme/theme_controller.dart';
import '../widgets/pulsing_dot.dart';
import '../widgets/theme_mode_button.dart';

class TrackingScreen extends StatefulWidget {
  final String publicCode;
  final ThemeController themeController;
  final Map<String, dynamic>? sessionInfo;
  const TrackingScreen({super.key, required this.publicCode, required this.themeController, this.sessionInfo});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> with TickerProviderStateMixin {
  String? sessionId;
  String? publishToken;
  bool tracking = false;
  bool sessionStarted = false;
  bool paused = false;
  String status = '';
  final String serverUrl = const String.fromEnvironment('BACKEND_URL', defaultValue: 'https://www.cinna.app');
  final MapController _mapController = MapController();
  StreamSubscription<Position>? positionSub;
  LatLng? _current;
  bool _followOnUpdate = false;

  bool get _usingMapTiler => const String.fromEnvironment('MAPTILER_KEY', defaultValue: '').isNotEmpty;

  List<Map<String, dynamic>> _stops = const [];
  String? _selectedStopId;
  List<LatLng> _route = const [];
  bool _loadingStops = false;
  bool _loadingRoute = false;

  @override
  void initState() {
    super.initState();
    final info = widget.sessionInfo;
    if (info != null) {
      sessionId = info['session_id'] as String?;
      publishToken = info['publish_token'] as String?;
      if (sessionId != null && publishToken != null) {
        sessionStarted = true;
        status = 'Session ready';
        // Fetch stops when session is ready
        unawaited(_fetchStops());
      }
    }
  }

  String _tileUrl({required bool isDark}) {
    final key = const String.fromEnvironment('MAPTILER_KEY', defaultValue: '');
    final dark = const String.fromEnvironment('MAP_STYLE_DARK', defaultValue: 'basic-v2-dark');
    final light = const String.fromEnvironment('MAP_STYLE_LIGHT', defaultValue: 'basic-v2');
    if (key.isNotEmpty) {
      final style = isDark ? dark : light;
      return 'https://api.maptiler.com/maps/$style/{z}/{x}/{y}@2x.png?key=$key';
    }
    return 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  Future<void> _fetchStops() async {
    final sid = sessionId;
    if (sid == null) return;
    setState(() { _loadingStops = true; });
    try {
      final r = await http.get(Uri.parse('$serverUrl/api/operator/session/stops?session_id=$sid'));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (j['stops'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        setState(() { _stops = list; });
      }
    } catch (_) {}
    setState(() { _loadingStops = false; });
  }

  Future<void> _fetchRouteToStop(String stopId) async {
    final sid = sessionId;
    if (sid == null || _current == null) return;
    final stop = _stops.firstWhere((s) => s['id'] == stopId, orElse: () => {});
    if (stop.isEmpty) return;
    final toLat = stop['lat'] as num?;
    final toLng = stop['lng'] as num?;
    if (toLat == null || toLng == null) return;
    setState(() { _loadingRoute = true; _route = const []; });
    try {
      final url = Uri.parse('$serverUrl/api/operator/route?from_lat=${_current!.latitude}&from_lng=${_current!.longitude}&to_lat=$toLat&to_lng=$toLng');
      final r = await http.get(url);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final coords = (j['coordinates'] as List<dynamic>? ?? []);
        final poly = <LatLng>[];
        for (final c in coords) {
          final m = c as Map<String, dynamic>;
          final lat = (m['lat'] as num?)?.toDouble();
          final lng = (m['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) poly.add(LatLng(lat, lng));
        }
        // Only store/display the route when not paused
        if (!paused) {
          setState(() { _route = poly; });
        } else {
          setState(() {});
        }
        // Immediately publish route so backend reflects it without waiting for next GPS tick
        if (tracking && !paused) {
          unawaited(_publishRouteUpdate());
        }
      }
    } catch (_) {}
    setState(() { _loadingRoute = false; });
  }

  Map<String, dynamic>? _routeJson() {
    if (_route.isEmpty) return null;
    return {
      'coordinates': _route.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    };
  }

  Future<void> _startSession() async {
    setState(() => status = 'Starting session...');
    try {
      final r = await http
          .post(
            Uri.parse('$serverUrl/api/operator/session/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'public_code': widget.publicCode}),
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        sessionId = data['session_id'] as String?;
        publishToken = data['publish_token'] as String?;
        sessionStarted = true;
        status = 'Session started';
        unawaited(_fetchStops());
      } else {
        status = 'Failed: ${r.statusCode} ${r.body}';
      }
    } catch (e) {
      status = 'Network error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensureSessionThenBeginTracking({required bool follow}) async {
    if (!sessionStarted || publishToken == null) {
      await _startSession();
    }
    if (!sessionStarted || publishToken == null) {
      return; // start failed; status already set
    }
    await _beginTracking(follow: follow);
  }

  Future<void> _beginTracking({required bool follow}) async {
    if (publishToken == null) return;
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => status = 'Location permission denied');
      return;
    }
    setState(() {
      tracking = true;
      paused = false;
      status = 'Online';
    });
    _followOnUpdate = follow;
    await _setRemoteStatus('online');
    positionSub?.cancel();
    positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 10),
    ).listen((pos) async {
      _current = LatLng(pos.latitude, pos.longitude);
      if (_followOnUpdate) {
        try {
          _mapController.move(_current!, 15);
        } catch (_) {}
      }
      final payload = {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'speed': pos.speed,
        'heading': pos.heading,
        'accuracy': pos.accuracy,
        'ts': DateTime.now().toIso8601String(),
        'route': _routeJson(),
      };
      try {
        await http.post(
          Uri.parse('$serverUrl/api/operator/ping?token=$publishToken'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (_) {}
      if (_selectedStopId != null) {
        // refresh route occasionally or first time when current updates
        unawaited(_fetchRouteToStop(_selectedStopId!));
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _pauseTracking() async {
    if (publishToken == null) return;
    await positionSub?.cancel();
    setState(() {
      tracking = false;
      paused = true;
      status = 'Paused';
    });
    await _setRemoteStatus('paused');
    // Clear the published route immediately so consumers stop rendering guidance
    setState(() { _route = const []; });
    await _publishRouteUpdate();
  }

  Future<void> _resumeTracking() async {
    await _beginTracking(follow: false);
    // On resume, publish route for the currently selected destination
    final dest = _selectedStopId;
    if (dest != null) {
      unawaited(_fetchRouteToStop(dest));
    }
  }

  Future<void> _setRemoteStatus(String s) async {
    final token = publishToken;
    if (token == null) return;
    try {
      await http.post(
        Uri.parse('$serverUrl/api/operator/status?token=$token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': s}),
      );
    } catch (_) {}
  }

  Future<void> _endTrip() async {
    final sid = sessionId;
    if (sid != null) {
      try {
        await http.post(
          Uri.parse('$serverUrl/api/operator/session/end'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'session_id': sid}),
        );
      } catch (_) {}
    }
    await positionSub?.cancel();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _setRemoteDestination(String stopId) async {
    final token = publishToken;
    if (token == null) return;
    try {
      await http.post(
        Uri.parse('$serverUrl/api/operator/destination?token=$token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'stop_id': stopId}),
      );
    } catch (_) {}
  }

  Future<void> _publishRouteUpdate() async {
    final token = publishToken;
    final pos = _current;
    if (token == null || pos == null) return;
    final payload = {
      'lat': pos.latitude,
      'lng': pos.longitude,
      'route': _routeJson(),
    };
    try {
      await http.post(
        Uri.parse('$serverUrl/api/operator/ping?token=$token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  Future<void> _confirmEndTrip() async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('End trip?'),
          content: const Text('Are you sure you want to end the trip?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: cs.onPrimary),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('End trip'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await _endTrip();
    }
  }

  @override
  void dispose() {
    positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Code: ${widget.publicCode}'),
        actions: [ThemeModeButton(controller: widget.themeController)],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: (tracking || paused)
                      ? FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _current ?? const LatLng(0, 0),
                            initialZoom: 3,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: _tileUrl(isDark: isDark),
                              userAgentPackageName: 'cinna_tracker_operator_app',
                            ),
                            if (_route.isNotEmpty && !paused)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: _route,
                                    strokeWidth: 4,
                                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.9),
                                  ),
                                ],
                              ),
                            if (_route.isNotEmpty && !paused)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _route.last,
                                    width: 20,
                                    height: 20,
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.black : Colors.white,
                                        border: Border.all(color: isDark ? Colors.white : Colors.black, width: 3),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (_current != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _current!,
                                    width: 80,
                                    height: 80,
                                    alignment: Alignment.center,
                                    child: const PulsingDot(),
                                  ),
                                ],
                              ),
                          ],
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.map_outlined, size: 48),
                              const SizedBox(height: 8),
                              Text('Session not started', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text('Tracking is offline', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                ),
                // Status chip
                if (status.isNotEmpty)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Chip(
                          label: Text(status),
                          avatar: Icon(
                            status == 'Online'
                                ? Icons.wifi_tethering
                                : (status == 'Paused' ? Icons.pause_circle : Icons.hourglass_top),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Controls bar
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.background.withOpacity(0.92),
                      border: Border(
                        top: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.6)),
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      12 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Stop selector
                        if (sessionStarted)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: _selectedStopId,
                                    items: _stops.map((s) {
                                      return DropdownMenuItem<String>(
                                        value: s['id'] as String,
                                        child: Text('#${s['sequence']} · ${s['name']}', overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() { _selectedStopId = val; });
                                      if (val != null) {
                                        unawaited(_fetchRouteToStop(val));
                                        unawaited(_setRemoteDestination(val));
                                      }
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'Destination stop',
                                    ),
                                  ),
                                ),
                                if (_loadingStops) const SizedBox(width: 10),
                                if (_loadingStops) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  if (!tracking && !paused) {
                                    return FilledButton(
                                      onPressed: () => _ensureSessionThenBeginTracking(follow: true),
                                      child: const Text('Begin Tracking'),
                                    );
                                  } else if (tracking && !paused) {
                                    return FilledButton.tonal(
                                      onPressed: _pauseTracking,
                                      child: const Text('Pause'),
                                    );
                                  } else {
                                    return FilledButton(
                                      onPressed: _resumeTracking,
                                      child: const Text('Resume'),
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                                onPressed: _confirmEndTrip,
                                child: const Text('End Trip'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (tracking && _current == null)
                  const Center(child: Text('Waiting for first location…')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }
}



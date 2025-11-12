import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
  // Smoothed/snapped current position for display
  LatLng? _displayCurrent;
  double? _lastAccuracyMeters;
  bool _followOnUpdate = false;

  bool get _usingMapTiler => const String.fromEnvironment('MAPTILER_KEY', defaultValue: '').isNotEmpty;

  List<Map<String, dynamic>> _stops = const [];
  String? _selectedStopId;
  List<LatLng> _route = const [];
  // Route rendered on the map, trimmed to start at the current pulsing dot
  List<LatLng> _displayRoute = const [];
  bool _loadingStops = false;
  bool _loadingRoute = false;
  bool _routeFetchInFlight = false;
  DateTime? _lastRouteFetchAt;

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
    if (_routeFetchInFlight) return;
    final stop = _stops.firstWhere((s) => s['id'] == stopId, orElse: () => {});
    if (stop.isEmpty) return;
    final toLat = stop['lat'] as num?;
    final toLng = stop['lng'] as num?;
    if (toLat == null || toLng == null) return;
    _routeFetchInFlight = true;
    setState(() { _loadingRoute = true; _route = const []; _displayRoute = const []; });
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
          setState(() {
            _route = poly;
          });
          // Recompute the display route so that the polyline head attaches to the pulsing dot
          _recomputeDisplayRoute();
        } else {
          setState(() {});
        }
        _lastRouteFetchAt = DateTime.now();
        // Ensure backend route is populated immediately (even before next GPS tick)
        if (tracking && !paused) {
          unawaited(_setRemoteRoute(_routeJson()));
        }
      }
    } catch (_) {}
    _routeFetchInFlight = false;
    setState(() { _loadingRoute = false; });
  }

  Map<String, dynamic>? _routeJson() {
    if (_route.isEmpty) return null;
    return {
      'coordinates': _route.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    };
  }

  void _recomputeDisplayRoute() {
    if (paused) {
      if (_displayRoute.isNotEmpty) setState(() { _displayRoute = const []; });
      return;
    }
    final cur = _current;
    if (cur == null || _route.isEmpty) {
      if (_displayRoute.isNotEmpty) setState(() { _displayRoute = const []; });
      return;
    }
    // Find nearest point on the route to the current position
    final distance = const Distance();
    var nearestIdx = 0;
    var nearestMeters = double.infinity;
    for (var i = 0; i < _route.length; i++) {
      final d = distance(cur, _route[i]);
      if (d < nearestMeters) {
        nearestMeters = d;
        nearestIdx = i;
      }
    }
    // Trim all points up to nearestIdx so we don't render a tail behind the marker
    final trimmed = <LatLng>[];
    trimmed.add(cur);
    for (var i = nearestIdx + 1; i < _route.length; i++) {
      trimmed.add(_route[i]);
    }
    // Update only if changed to avoid unnecessary rebuild churn
    _displayRoute = trimmed;
    if (mounted) setState(() {});
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
      status = 'Active';
    });
    _followOnUpdate = follow;
    await _setRemoteStatus('online');
    positionSub?.cancel();
    positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 10),
    ).listen((pos) async {
      _current = LatLng(pos.latitude, pos.longitude);
      _lastAccuracyMeters = pos.accuracy;
      // Apply a small forward prediction to compensate latency, then snap to route if close
      final predicted = _predictAhead(_current!, pos.speed, pos.heading, 0.9);
      _displayCurrent = _maybeSnapToRoute(predicted);
      if (_followOnUpdate) {
        try {
          _mapController.move(_displayCurrent ?? _current!, 15);
        } catch (_) {}
      }
      // Keep the displayed polyline attached to the current pulsing dot
      _recomputeDisplayRoute();
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
        // Refresh route occasionally after resume or on movement
        final shouldRefresh = _route.isEmpty ||
            (_lastRouteFetchAt == null) ||
            DateTime.now().difference(_lastRouteFetchAt!) > const Duration(seconds: 30);
        if (shouldRefresh && !_routeFetchInFlight) {
          unawaited(_fetchRouteToStop(_selectedStopId!));
        }
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
    // Locally clear the route so the UI reflects paused state immediately
    setState(() { _route = const []; _displayRoute = const []; });
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

  // Removed immediate route publish; route will be included on the next ping

  Future<void> _setRemoteRoute(Map<String, dynamic>? route) async {
    final token = publishToken;
    if (token == null) return;
    try {
      await http.patch(
        Uri.parse('$serverUrl/api/operator/route/update?token=$token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'route': route}),
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
                            if (_displayRoute.isNotEmpty && !paused)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: _displayRoute,
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
                                    point: (_displayCurrent ?? _current!) ,
                                    width: 80,
                                    height: 80,
                                    alignment: Alignment.center,
                                    child: PulsingDot(paused: paused),
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
                            status == 'Active'
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

// Helpers for snapping current position to the closest point on the route polyline
extension _SnapHelpers on _TrackingScreenState {
  static const double _snapThresholdMeters = 25; // snap when within 25m of the route

  LatLng _predictAhead(LatLng p, double speedMs, double headingDeg, double seconds) {
    final s = speedMs.isFinite ? speedMs.clamp(0, 40) : 0.0; // m/s clamp
    final d = s * seconds;
    if (d <= 0) return p;
    final brad = headingDeg * (3.141592653589793 / 180.0);
    const R = 6378137.0;
    final lat1 = p.latitude * (3.141592653589793 / 180.0);
    final lng1 = p.longitude * (3.141592653589793 / 180.0);
    final lat2 = math.asin(math.sin(lat1) * math.cos(d / R) + math.cos(lat1) * math.sin(d / R) * math.cos(brad));
    final lng2 = lng1 + math.atan2(math.sin(brad) * math.sin(d / R) * math.cos(lat1), math.cos(d / R) - math.sin(lat1) * math.sin(lat2));
    return LatLng(lat2 * (180.0 / 3.141592653589793), lng2 * (180.0 / 3.141592653589793));
  }

  LatLng? _maybeSnapToRoute(LatLng p) {
    if (_route.isEmpty) return p;
    // Find nearest segment and projection
    var bestPoint = p;
    var bestDist = double.infinity;
    for (var i = 0; i < _route.length - 1; i++) {
      final a = _route[i];
      final b = _route[i + 1];
      final snapped = _projectOntoSegment(p, a, b);
      final d = const Distance().as(LengthUnit.Meter, p, snapped);
      if (d < bestDist) {
        bestDist = d;
        bestPoint = snapped;
      }
    }
    if (bestDist <= _snapThresholdMeters) return bestPoint;
    return p;
  }

  // Project geographic point p onto segment ab using a local equirectangular projection
  LatLng _projectOntoSegment(LatLng p, LatLng a, LatLng b) {
    // Convert to local XY meters around reference latitude
    final refLat = (a.latitude + b.latitude) / 2.0;
    double mPerDegLat = 111132.0;
    double mPerDegLng = 111320.0 * (math.cos(refLat * (3.141592653589793 / 180.0)));
    final ax = (a.longitude - 0.0) * mPerDegLng;
    final ay = (a.latitude - 0.0) * mPerDegLat;
    final bx = (b.longitude - 0.0) * mPerDegLng;
    final by = (b.latitude - 0.0) * mPerDegLat;
    final px = (p.longitude - 0.0) * mPerDegLng;
    final py = (p.latitude - 0.0) * mPerDegLat;
    final vx = bx - ax;
    final vy = by - ay;
    final wx = px - ax;
    final wy = py - ay;
    final vLen2 = vx * vx + vy * vy;
    if (vLen2 == 0) {
      // a==b
      return a;
    }
    var t = (wx * vx + wy * vy) / vLen2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final sx = ax + t * vx;
    final sy = ay + t * vy;
    // Back to lat/lng
    final snappedLng = sx / mPerDegLng + 0.0;
    final snappedLat = sy / mPerDegLat + 0.0;
    return LatLng(snappedLat, snappedLng);
  }
}



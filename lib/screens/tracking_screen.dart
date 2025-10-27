import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:background_locator_2/background_locator.dart' as bl;
import 'package:background_locator_2/settings/android_settings.dart' as bl_settings;
import 'package:background_locator_2/settings/ios_settings.dart' as bl_settings;
import 'package:background_locator_2/settings/locator_settings.dart' as bl_loc;
import '../background/location_callbacks.dart' as bg;
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
  // Smooth marker animation state
  LatLng? _displayed;
  AnimationController? _markerAnimController;
  CurvedAnimation? _markerCurve;
  LatLng? _fromLatLng;
  LatLng? _toLatLng;
  bool _followOnUpdate = false;
  bool _bgTrackingActive = false;
  bool _sentInitialPing = false;

  bool get _usingMapTiler => const String.fromEnvironment('MAPTILER_KEY', defaultValue: '').isNotEmpty;

  List<Map<String, dynamic>> _stops = const [];
  String? _selectedStopId;
  List<LatLng> _route = const [];
  bool _loadingStops = false;
  bool _loadingRoute = false;

  @override
  void initState() {
    super.initState();
    _markerAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _markerCurve = CurvedAnimation(parent: _markerAnimController!, curve: Curves.easeInOut);
    _markerAnimController!.addListener(() {
      if (_fromLatLng != null && _toLatLng != null) {
        final t = _markerCurve!.value;
        final lat = _fromLatLng!.latitude + (_toLatLng!.latitude - _fromLatLng!.latitude) * t;
        final lng = _fromLatLng!.longitude + (_toLatLng!.longitude - _fromLatLng!.longitude) * t;
        _displayed = LatLng(lat, lng);
        if (_followOnUpdate) {
          try { _mapController.move(_displayed!, 15); } catch (_) {}
        }
        if (mounted) setState(() {});
      }
    });
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

  void _startMarkerAnimation(LatLng target) {
    // Initialize displayed position if this is the first point
    if (_displayed == null) {
      _displayed = target;
      if (mounted) setState(() {});
      return;
    }
    _fromLatLng = _displayed;
    _toLatLng = target;
    // If controller isn't available, snap
    final controller = _markerAnimController;
    if (controller == null) {
      _displayed = target;
      if (mounted) setState(() {});
      return;
    }
    controller.reset();
    controller.forward();
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

  Future<void> _fetchRouteToStop(String stopId, {bool postAfter = false}) async {
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
        setState(() { _route = poly; });
        if (postAfter) {
          await _postRoutePing();
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

  Future<void> _postRoutePing() async {
    final token = publishToken;
    final cur = _current;
    if (token == null || cur == null) return;
    try {
      await http.post(
        Uri.parse('$serverUrl/api/operator/ping?token=$token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'lat': cur.latitude,
          'lng': cur.longitude,
          'route': _routeJson(),
        }),
      );
    } catch (_) {}
  }

  Future<void> _postLivePing({
    required double lat,
    required double lng,
    double? speed,
    double? heading,
    double? accuracy,
    Map<String, dynamic>? route,
  }) async {
    final token = publishToken;
    if (token == null) return;
    try {
      await http.post(
        Uri.parse('$serverUrl/api/operator/ping?token=$token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'lat': lat,
          'lng': lng,
          if (speed != null) 'speed': speed,
          if (heading != null) 'heading': heading,
          if (accuracy != null) 'accuracy': accuracy,
          if (route != null) 'route': route,
        }),
      );
    } catch (_) {}
  }

  Future<void> _sendImmediatePing() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      Position? pos = last;
      if (pos == null) {
        pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      }
      await _postLivePing(
        lat: pos.latitude,
        lng: pos.longitude,
        speed: pos.speed,
        heading: pos.heading,
        accuracy: pos.accuracy,
        route: _routeJson(),
      );
    } catch (_) {}
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
    _sentInitialPing = false;
    await _setRemoteStatus('online');
    positionSub?.cancel();
    positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 10),
    ).listen((pos) async {
      final next = LatLng(pos.latitude, pos.longitude);
      _current = next;
      _startMarkerAnimation(next);
      if (!_sentInitialPing) {
        _sentInitialPing = true;
        unawaited(_postLivePing(
          lat: pos.latitude,
          lng: pos.longitude,
          speed: pos.speed,
          heading: pos.heading,
          accuracy: pos.accuracy,
          route: _routeJson(),
        ));
      }
      if (_selectedStopId != null) {
        unawaited(_fetchRouteToStop(_selectedStopId!));
      }
      if (mounted) setState(() {});
    });

    await _startBackgroundLocator();
    unawaited(_sendImmediatePing());
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
    await _stopBackgroundLocator();
  }

  Future<void> _resumeTracking() async {
    await _beginTracking(follow: false);
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
    await _stopBackgroundLocator();
    if (!mounted) return;
    Navigator.pop(context);
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
    _markerAnimController?.dispose();
    unawaited(_stopBackgroundLocator());
    super.dispose();
  }

  Future<void> _startBackgroundLocator() async {
    if (_bgTrackingActive) return;
    final token = publishToken;
    if (token == null) return;
    try {
      await bl.BackgroundLocator.initialize();
      await bl.BackgroundLocator.registerLocationUpdate(
        bg.bgLocationCallback,
        initCallback: bg.bgInitCallback,
        disposeCallback: bg.bgDisposeCallback,
        initDataCallback: {
          'server_url': serverUrl,
          'publish_token': token,
        },
        iosSettings: bl_settings.IOSSettings(
          accuracy: bl_loc.LocationAccuracy.NAVIGATION,
          distanceFilter: 10,
          stopWithTerminate: false,
        ),
        androidSettings: bl_settings.AndroidSettings(
          accuracy: bl_loc.LocationAccuracy.NAVIGATION,
          interval: 5,
          distanceFilter: 10,
        ),
        autoStop: false,
      );
      _bgTrackingActive = true;
    } catch (_) {}
  }

  Future<void> _stopBackgroundLocator() async {
    if (!_bgTrackingActive) return;
    try {
      await bl.BackgroundLocator.unRegisterLocationUpdate();
    } catch (_) {}
    _bgTrackingActive = false;
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
                            initialCenter: _displayed ?? _current ?? const LatLng(0, 0),
                            initialZoom: 3,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: _tileUrl(isDark: isDark),
                              userAgentPackageName: 'cinna_tracker_operator_app',
                            ),
                            if (_route.isNotEmpty)
                              PolylineLayer(
                                polylines: [
                                  Polyline(points: _route, strokeWidth: 4, color: Colors.blueAccent.withOpacity(0.8)),
                                ],
                              ),
                            if (_current != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _displayed ?? _current!,
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
                                    onChanged: (val) async {
                                      setState(() { _selectedStopId = val; });
                                      if (val != null) { await _fetchRouteToStop(val, postAfter: true); }
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



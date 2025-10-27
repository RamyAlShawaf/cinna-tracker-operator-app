import 'dart:convert';
import 'package:background_locator_2/location_dto.dart';
import 'package:http/http.dart' as http;

// Values set in initCallback and used by the background isolate
String? _bgServerUrl;
String? _bgPublishToken;

@pragma('vm:entry-point')
void bgInitCallback(Map<dynamic, dynamic> params) {
  _bgServerUrl = params['server_url'] as String?;
  _bgPublishToken = params['publish_token'] as String?;
}

@pragma('vm:entry-point')
void bgDisposeCallback() {
  _bgServerUrl = null;
  _bgPublishToken = null;
}

@pragma('vm:entry-point')
Future<void> bgLocationCallback(LocationDto dto) async {
  final server = _bgServerUrl;
  final token = _bgPublishToken;
  if (server == null || token == null) return;
  final payload = {
    'lat': dto.latitude,
    'lng': dto.longitude,
    'speed': dto.speed,
    'heading': dto.heading,
    'accuracy': dto.accuracy,
    'ts': DateTime.now().toIso8601String(),
    'route': null,
  };
  try {
    await http.post(
      Uri.parse('$server/api/operator/ping?token=$token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
  } catch (_) {}
}

@pragma('vm:entry-point')
void bgNotificationCallback() {
  // No-op; could route to open app
}



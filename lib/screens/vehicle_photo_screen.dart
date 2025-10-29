import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../theme/theme_controller.dart';
import '../widgets/theme_mode_button.dart';

class VehiclePhotoScreen extends StatefulWidget {
  final String publicCode;
  final ThemeController themeController;
  const VehiclePhotoScreen({super.key, required this.publicCode, required this.themeController});

  @override
  State<VehiclePhotoScreen> createState() => _VehiclePhotoScreenState();
}

class _VehiclePhotoScreenState extends State<VehiclePhotoScreen> {
  final String serverUrl = const String.fromEnvironment('BACKEND_URL', defaultValue: 'https://www.cinna.app');
  final ImagePicker _picker = ImagePicker();
  XFile? _photo;
  bool _uploading = false;
  String? _error;

  Future<void> _takePhoto() async {
    setState(() { _error = null; });
    try {
      final shot = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1920);
      if (shot == null) return; // user cancelled
      setState(() { _photo = shot; });
    } catch (e) {
      setState(() { _error = 'Failed to open camera: $e'; });
    }
  }

  Future<void> _uploadAndContinue() async {
    final p = _photo;
    if (p == null) return;
    setState(() { _uploading = true; _error = null; });
    try {
      final uri = Uri.parse('$serverUrl/api/operator/vehicle/photo');
      final req = http.MultipartRequest('POST', uri)
        ..fields['public_code'] = widget.publicCode
        ..files.add(await http.MultipartFile.fromPath('image', p.path, filename: 'vehicle.jpg', contentType: MediaType('image', 'jpeg')));

      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
      try {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() { _error = j['error'] as String? ?? 'Upload failed (${resp.statusCode})'; });
      } catch (_) {
        setState(() { _error = 'Upload failed (${resp.statusCode})'; });
      }
    } catch (e) {
      setState(() { _error = 'Network error: $e'; });
    } finally {
      setState(() { _uploading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Photo'),
        actions: [ThemeModeButton(controller: widget.themeController)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bus code: ${widget.publicCode}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Text('Take a clear photo of the vehicle before starting.', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_photo != null)
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(_photo!.path), fit: BoxFit.cover, width: double.infinity),
                ),
              )
            else
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outline.withOpacity(0.5)),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_camera_outlined, size: 48, color: cs.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text('No photo captured', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red.shade600)),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _uploading ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                if (_photo == null)
                  Expanded(
                    child: FilledButton(
                      onPressed: _uploading ? null : _takePhoto,
                      child: const Text('Open Camera'),
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton(
                      onPressed: _uploading ? null : _uploadAndContinue,
                      child: _uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Use Photo'),
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



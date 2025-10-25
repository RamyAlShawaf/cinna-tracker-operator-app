import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';

class ThemeModeButton extends StatelessWidget {
  final ThemeController controller;
  const ThemeModeButton({super.key, required this.controller});

  IconData _iconFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
      default:
        return Icons.brightness_auto;
    }
  }

  String _labelFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
      default:
        return 'System';
    }
  }

  ThemeMode _next(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return ThemeMode.dark;
      case ThemeMode.dark:
        return ThemeMode.system;
      case ThemeMode.system:
      default:
        return ThemeMode.light;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Theme: ${_labelFor(controller.themeMode)}',
      child: IconButton(
        onPressed: () => controller.setThemeMode(_next(controller.themeMode)),
        icon: Icon(_iconFor(controller.themeMode)),
      ),
    );
  }
}



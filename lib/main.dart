import 'package:flutter/material.dart';
import 'theme/theme_controller.dart';
import 'theme/themes.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const OperatorApp());
}

class OperatorApp extends StatefulWidget {
  const OperatorApp({super.key});

  @override
  State<OperatorApp> createState() => _OperatorAppState();
}

class _OperatorAppState extends State<OperatorApp> {
  final ThemeController _themeController = ThemeController();
  late final VoidCallback _themeListener;

  @override
  void initState() {
    super.initState();
    _themeListener = () => setState(() {});
    _themeController.addListener(_themeListener);
    _themeController.load();
  }

  @override
  void dispose() {
    _themeController.removeListener(_themeListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CinnaOp',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeController.themeMode,
      home: HomeScreen(themeController: _themeController),
    );
  }
}

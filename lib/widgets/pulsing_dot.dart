import 'package:flutter/material.dart';

class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, this.paused = false});

  final bool paused;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Colors:
    // Active (online): emerald (#14B8A6)
    // Paused: orange/amber (#F59E0B)
    final Color baseColor = widget.paused ? const Color(0xFFF59E0B) : const Color(0xFF14B8A6);
    final Color ringColor = widget.paused ? const Color(0x59F59E0B) : const Color(0x5914B8A6);
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              final scale = 1.0 + t * 1.6;
              final opacity = 1.0 - t;
              return Opacity(
                opacity: opacity,
                child: Container(
                  width: 18 * scale,
                  height: 18 * scale,
                  decoration: BoxDecoration(
                    color: ringColor,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: baseColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(color: ringColor, blurRadius: 8, spreadRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


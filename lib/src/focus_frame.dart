import 'package:flutter/material.dart';

/// Draws a clear outline around its child while it (or a descendant) has focus,
/// so the position of a TV remote / keyboard is always visible.
class FocusFrame extends StatefulWidget {
  const FocusFrame({super.key, required this.child, this.radius = 8});

  final Widget child;
  final double radius;

  @override
  State<FocusFrame> createState() => _FocusFrameState();
}

class _FocusFrameState extends State<FocusFrame> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: _focused ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 3),
        ),
        child: widget.child,
      ),
    );
  }
}

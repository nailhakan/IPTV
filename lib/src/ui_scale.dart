import 'package:flutter/widgets.dart';

/// Zooms the whole UI: lays the app out in a (size / scale) area and scales it back to the window.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) return child;
    final mq = MediaQuery.of(context);
    final size = mq.size / scale;
    return MediaQuery(
      data: mq.copyWith(
        size: size,
        padding: mq.padding / scale,
        viewPadding: mq.viewPadding / scale,
        viewInsets: mq.viewInsets / scale,
      ),
      // OverflowBox + Transform kept the *window* size as the hit-test bounds, so the right/bottom part of the
      // screen stopped receiving clicks. A FittedBox around a real (size / scale) box scales it back correctly.
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topLeft,
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'focus_frame.dart';

/// Network poster decoded at thumbnail size (full-size posters cost ~1.5 MB each once decoded).
class PosterImage extends StatelessWidget {
  const PosterImage(this.url, {super.key, this.size = double.infinity, this.fit = BoxFit.cover});

  final String url;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final h = size == double.infinity ? null : size;
    final placeholder = Container(width: size, height: h, color: Colors.white10, child: const Icon(Icons.image_not_supported_outlined, size: 20));
    if (url.isEmpty) return placeholder;
    return Image.network(url, width: size, height: h, fit: fit, cacheWidth: 260, errorBuilder: (_, _, _) => placeholder);
  }
}

/// Poster card used in grids and home rows: hover lift, focus frame, year/language chips, progress bar.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.logo,
    required this.title,
    required this.onTap,
    this.year,
    this.tags = const [],
    this.progress,
    this.badge,
    this.topRight,
  });

  final String logo;
  final String title;
  final VoidCallback onTap;
  final String? year;
  final List<String> tags;
  final double? progress;
  final IconData? badge; // small icon, top-left (e.g. a live channel)
  final Widget? topRight; // e.g. the favorite heart

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white)),
      );

  @override
  Widget build(BuildContext context) {
    final chips = [if (widget.year != null) widget.year!, ...widget.tags.take(2)];
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: FocusFrame(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(boxShadow: _hover ? const [BoxShadow(blurRadius: 12, color: Colors.black54)] : null),
                      child: PosterImage(widget.logo),
                    ),
                  ),
                  if (chips.isNotEmpty)
                    Positioned(left: 5, bottom: widget.progress != null ? 8 : 5, child: Wrap(spacing: 3, children: [for (final c in chips) _chip(c)])),
                  if (widget.badge != null) Positioned(top: 6, left: 6, child: Icon(widget.badge, size: 16, color: Colors.white70)),
                  if (widget.topRight != null) Positioned(top: 2, right: 2, child: widget.topRight!),
                  if (widget.progress != null)
                    Positioned(left: 0, right: 0, bottom: 0, child: ClipRRect(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)), child: LinearProgressIndicator(value: widget.progress, minHeight: 3))),
                ]),
              ),
              const SizedBox(height: 6),
              // Fixed two-line slot: otherwise a long title shrinks its poster and the grid rows look uneven.
              SizedBox(
                height: (Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) * 1.45 * 2,
                child: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../theme/theme.dart';

/// Squarified treemap layout (Bruls, Huizing, van Wijk). Values must be sorted descending.
List<Rect> squarify(List<double> values, Rect bounds) {
  final total = values.fold<double>(0, (a, b) => a + b);
  if (total <= 0 || bounds.isEmpty) return List.filled(values.length, Rect.zero);
  final scale = bounds.width * bounds.height / total;
  final areas = values.map((v) => v * scale).toList();
  final out = <Rect>[];
  var rect = bounds;
  var i = 0;

  double worst(List<double> row, double side) {
    final sum = row.fold<double>(0, (a, b) => a + b);
    final hi = row.reduce(math.max), lo = row.reduce(math.min);
    if (lo <= 0) return double.infinity;
    return math.max(side * side * hi / (sum * sum), (sum * sum) / (side * side * lo));
  }

  while (i < areas.length) {
    final side = math.min(rect.width, rect.height);
    final row = <double>[areas[i]];
    var j = i + 1;
    while (j < areas.length && worst([...row, areas[j]], side) <= worst(row, side)) {
      row.add(areas[j]);
      j++;
    }
    final sum = row.fold<double>(0, (a, b) => a + b);
    if (rect.width >= rect.height) {
      final w = rect.height == 0 ? 0.0 : sum / rect.height;
      var y = rect.top;
      for (final a in row) {
        final h = w == 0 ? 0.0 : a / w;
        out.add(Rect.fromLTWH(rect.left, y, w, h));
        y += h;
      }
      rect = Rect.fromLTRB(rect.left + w, rect.top, rect.right, rect.bottom);
    } else {
      final h = rect.width == 0 ? 0.0 : sum / rect.width;
      var x = rect.left;
      for (final a in row) {
        final w = h == 0 ? 0.0 : a / h;
        out.add(Rect.fromLTWH(x, rect.top, w, h));
        x += w;
      }
      rect = Rect.fromLTRB(rect.left, rect.top + h, rect.right, rect.bottom);
    }
    i = j;
  }
  return out;
}

class Treemap extends StatelessWidget {
  const Treemap({super.key, required this.node, required this.onOpen, this.maxBlocks = 28});
  final DirNode node;
  final ValueChanged<DirNode> onOpen;
  final int maxBlocks;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final items = node.children.where((c) => c.size > 0).take(maxBlocks).toList();
    if (items.isEmpty) {
      return Center(child: Text('This folder is empty', style: Theme.of(context).textTheme.bodySmall));
    }
    return LayoutBuilder(builder: (context, box) {
      final rects = squarify(items.map((e) => e.size.toDouble()).toList(), Offset.zero & box.biggest);
      return Stack(
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned.fromRect(
              rect: rects[i].deflate(1.5),
              child: _Block(
                node: items[i],
                share: node.size == 0 ? 0 : items[i].size / node.size,
                // Biggest blocks glow brightest; the rest fade toward the surface.
                tint: Color.lerp(fx.accent, fx.surface2, (i / math.max(items.length, 6)).clamp(0.0, 0.82))!,
                onTap: items[i].files > 0 && items[i].name != 'Files in this folder' ? () => onOpen(items[i]) : null,
              ),
            ),
        ],
      );
    });
  }
}

class _Block extends StatefulWidget {
  const _Block({required this.node, required this.share, required this.tint, this.onTap});
  final DirNode node;
  final double share;
  final Color tint;
  final VoidCallback? onTap;

  @override
  State<_Block> createState() => _BlockState();
}

class _BlockState extends State<_Block> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final n = widget.node;
    final onTint = widget.tint.computeLuminance() > 0.35 ? const Color(0xFF0B0A10) : fx.text;
    return Tooltip(
      message: '${n.name}\n${fmtBytes(n.size)} · ${plural(n.files, 'file')} · ${(widget.share * 100).toStringAsFixed(1)}%',
      child: MouseRegion(
        cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: fx.motion,
            decoration: BoxDecoration(
              color: hover ? Color.lerp(widget.tint, Colors.white, 0.1) : widget.tint,
              borderRadius: BorderRadius.circular(math.min(fx.radius, 8)),
              border: Border.all(color: hover ? fx.text.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.25)),
            ),
            child: LayoutBuilder(builder: (context, box) {
              if (box.maxWidth < 54 || box.maxHeight < 34) return const SizedBox.shrink();
              return Stack(
                children: [
                  if (n.children.isNotEmpty && box.maxWidth > 90 && box.maxHeight > 70)
                    Positioned.fill(child: CustomPaint(painter: _InnerPainter(n, onTint.withValues(alpha: 0.14)))),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: onTint, fontWeight: FontWeight.w600, fontSize: 12.5)),
                        if (box.maxHeight > 48)
                          Text(fmtBytes(n.size),
                              style: TextStyle(color: onTint.withValues(alpha: 0.75), fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Faint outlines of the sub-folders inside a block.
class _InnerPainter extends CustomPainter {
  _InnerPainter(this.node, this.color);
  final DirNode node;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final kids = node.children.where((c) => c.size > 0).toList();
    if (kids.isEmpty) return;
    final total = node.size.toDouble();
    final known = kids.fold<double>(0, (a, b) => a + b.size);
    final values = [...kids.map((k) => k.size.toDouble()), if (total > known) total - known];
    values.sort((a, b) => b.compareTo(a));
    final rects = squarify(values, (Offset.zero & size).deflate(4));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final r in rects) {
      canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(3)), p);
    }
  }

  @override
  bool shouldRepaint(_InnerPainter old) => old.node != node || old.color != color;
}

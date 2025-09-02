import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

class HeatmapLayer extends StatefulWidget {
  final List<LatLng> points;
  final MapController mapController;
  final double radiusPx;
  final Gradient gradient;
  final bool enabled;
  final double opacity;

  const HeatmapLayer({
    super.key,
    required this.points,
    required this.mapController,
    this.radiusPx = 100,
    this.enabled = true,
    this.opacity = 0.85,
    this.gradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0x00000000),
        Color(0xFF3B82F6), // blue
        Color(0xFFFFFF00), // yellow
        Color(0xFFFF7A18), // orange
        Color(0xFFFF2D55), // red
      ],
      stops: [0.0, 0.35, 0.7, 0.9, 1.0],
    ),
  });

  @override
  State<HeatmapLayer> createState() => _HeatmapLayerState();
}

class _HeatmapLayerState extends State<HeatmapLayer> {
  Future<ui.Image?>? _imageFuture;
  Size? _lastSize;
  List<LatLng>? _lastPoints;
  MapController? _lastController;

  @override
  void didUpdateWidget(covariant HeatmapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.points, widget.points) || oldWidget.mapController != widget.mapController) {
      _regenerate();
    }
  }

  void _regenerate() {
    if (!mounted || !widget.enabled) return;
    final size = _lastSize;
    if (size == null) return;
    // project lat/lng -> screen pixel offsets using mapController on main thread
    final pixelPoints = <Offset>[];
    try {
      for (final p in widget.points) {
        final pt = _latLngToScreenOffset(widget.mapController, p, size);
        if (pt != null) pixelPoints.add(pt);
      }
    } catch (_) {}

    setState(() {
      _imageFuture = compute(_generateHeatmapImageFromPixels, _HeatmapJobPixels(
        width: size.width,
        height: size.height,
        points: pixelPoints,
        radiusPx: widget.radiusPx,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastSize == null || _lastSize != size || _lastPoints != widget.points || _lastController != widget.mapController) {
          _lastSize = size;
          _lastPoints = List<LatLng>.from(widget.points);
          _lastController = widget.mapController;
          final pixelPoints = <Offset>[];
          try {
            for (final p in widget.points) {
              final pt = _latLngToScreenOffset(widget.mapController, p, size);
              if (pt != null) pixelPoints.add(pt);
            }
          } catch (_) {}
          _imageFuture = compute(_generateHeatmapImageFromPixels, _HeatmapJobPixels(
            width: size.width,
            height: size.height,
            points: pixelPoints,
            radiusPx: widget.radiusPx,
          ));
        }

        return FutureBuilder<ui.Image?>(
          future: _imageFuture,
          builder: (context, snap) {
            final ui.Image? img = snap.data;
            if (img == null) return const SizedBox.shrink();
            return IgnorePointer(
              child: Opacity(
                opacity: widget.opacity.clamp(0.0, 1.0),
                child: ShaderMask(
                  shaderCallback: (rect) => widget.gradient.createShader(rect),
                  blendMode: BlendMode.srcIn,
                  child: RawImage(
                    image: img,
                    fit: BoxFit.fill,
                    width: size.width,
                    height: size.height,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Convert [latLng] to a screen [Offset] within [size] using the given [mapController].
/// This uses a Web Mercator projection approximation based on the controller's camera center and zoom.
Offset? _latLngToScreenOffset(MapController controller, LatLng latLng, Size size) {
  try {
    final cam = controller.camera;
    final center = cam.center;
    final zoom = cam.zoom;

    // World size in pixels at given zoom (tile size = 256)
    final worldPixels = 256.0 * math.pow(2, zoom);

    double lonToX(double lon) => (lon + 180.0) / 360.0 * worldPixels;
    double latToY(double lat) {
      final sinLat = math.sin(lat * math.pi / 180.0);
      final y = 0.5 - (math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi));
      return y * worldPixels;
    }

    final centerX = lonToX(center.longitude);
    final centerY = latToY(center.latitude);
    final px = lonToX(latLng.longitude);
    final py = latToY(latLng.latitude);

    // The map widget centers the center point at the center of the screen.
    final dx = (px - centerX) + (size.width / 2);
    final dy = (py - centerY) + (size.height / 2);

    return Offset(dx, dy);
  } catch (_) {
    return null;
  }
}

class _HeatmapJobPixels {
  final double width;
  final double height;
  final List<Offset> points;
  final double radiusPx;
  _HeatmapJobPixels({required this.width, required this.height, required this.points, required this.radiusPx});
}

Future<ui.Image?> _generateHeatmapImageFromPixels(_HeatmapJobPixels job) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, job.width, job.height));
  final clearPaint = Paint()..blendMode = ui.BlendMode.clear;
  canvas.drawRect(Rect.fromLTWH(0, 0, job.width, job.height), clearPaint);

  final paint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, job.radiusPx / 2);

  for (final p in job.points) {
    final px = p.dx;
    final py = p.dy;
    if (px < -job.radiusPx || px > job.width + job.radiusPx || py < -job.radiusPx || py > job.height + job.radiusPx) continue;
    canvas.drawCircle(Offset(px, py), job.radiusPx, paint);
  }

  final picture = recorder.endRecording();
  final uiImage = await picture.toImage(job.width.ceil(), job.height.ceil());
  return uiImage;
}

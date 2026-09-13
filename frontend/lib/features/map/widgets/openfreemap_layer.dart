import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../../core/theme/tokens.dart';
import 'map_chip.dart';

/// OpenFreeMap's maintained, detail-rich style: free OpenStreetMap vector
/// tiles, no API key or billing account (https://openfreemap.org).
const openFreeMapStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';
const openFreeMapLayerMode = VectorTileLayerMode.vector;
const openFreeMapTileSubstitutionLevels = 3;

typedef MapStyleLoader = Future<Style> Function();

/// Split out so the loading and retry paths can be exercised without network.
final openFreeMapStyleLoaderProvider = Provider<MapStyleLoader>(
  (ref) =>
      () => StyleReader(uri: openFreeMapStyleUrl).read(),
);

/// The style, its tile sources and sprites, fetched once per app run.
/// vector_map_tiles caches the tiles themselves on disk.
final openFreeMapStyleProvider = FutureProvider<Style>(
  (ref) => ref.watch(openFreeMapStyleLoaderProvider)(),
);

/// The base map under the route and markers. Tests override this so no
/// style or tile request leaves the machine.
final baseMapLayerProvider = Provider<Widget>(
  (ref) => const OpenFreeMapLayer(),
);

/// OpenFreeMap tiles as a flutter_map layer. A branded map skeleton remains
/// behind the tiles while they fill the viewport; if the style fails, a chip
/// offers a real provider refresh.
class OpenFreeMapLayer extends ConsumerWidget {
  const OpenFreeMapLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(openFreeMapStyleProvider)
        .when(
          skipLoadingOnRefresh: false,
          data: (style) => Stack(
            fit: StackFit.expand,
            children: [
              const MapLoadingSkeleton(),
              VectorTileLayer(
                theme: style.theme,
                sprites: style.sprites,
                tileProviders: style.providers,
                // Vector mode can retain rendered ancestor/child tiles while
                // the next zoom level arrives. Raster mode ignores this knob.
                layerMode: openFreeMapLayerMode,
                maximumTileSubstitutionDifference:
                    openFreeMapTileSubstitutionLevels,
              ),
            ],
          ),
          loading: () => const MapLoadingSkeleton(),
          error: (error, _) => Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(VoiceOpsSpacing.gutter),
              child: MapChip(
                icon: TablerIcons.map2,
                message: "The map didn't load. Your route still works.",
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(openFreeMapStyleProvider),
              ),
            ),
          ),
        );
  }
}

/// A quiet street-grid placeholder, using the app's map palette instead of a
/// blank canvas or bare spinner.
class MapLoadingSkeleton extends StatelessWidget {
  const MapLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Map loading',
      child: const ExcludeSemantics(
        child: ColoredBox(
          key: Key('map-loading-skeleton'),
          color: VoiceOpsColors.canvas,
          child: CustomPaint(painter: _StreetGridPainter()),
        ),
      ),
    );
  }
}

class _StreetGridPainter extends CustomPainter {
  const _StreetGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = VoiceOpsColors.divider
      ..strokeWidth = VoiceOpsMap.skeletonRoadWidth
      ..style = PaintingStyle.stroke;
    final major = Paint()
      ..color = VoiceOpsColors.primaryTint
      ..strokeWidth = VoiceOpsMap.skeletonMainRoadWidth
      ..style = PaintingStyle.stroke;
    final buildings = Paint()
      ..color = VoiceOpsColors.elevated
      ..style = PaintingStyle.fill;

    for (final rect in <Rect>[
      Rect.fromLTWH(
        size.width * .08,
        size.height * .12,
        size.width * .22,
        size.height * .13,
      ),
      Rect.fromLTWH(
        size.width * .62,
        size.height * .08,
        size.width * .27,
        size.height * .18,
      ),
      Rect.fromLTWH(
        size.width * .15,
        size.height * .56,
        size.width * .3,
        size.height * .16,
      ),
      Rect.fromLTWH(
        size.width * .67,
        size.height * .63,
        size.width * .2,
        size.height * .12,
      ),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(VoiceOpsRadius.control),
        ),
        buildings,
      );
    }
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), major);
    canvas.drawLine(
      Offset(0, size.height * .72),
      Offset(size.width, size.height * .3),
      minor,
    );
    canvas.drawLine(
      Offset(size.width * .45, 0),
      Offset(size.width * .2, size.height),
      minor,
    );
    canvas.drawLine(
      Offset(size.width * .82, 0),
      Offset(size.width * .55, size.height),
      minor,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

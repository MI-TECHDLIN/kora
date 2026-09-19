import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../../core/theme/tokens.dart';
import '../../../providers/map_style_provider.dart';
import 'map_chip.dart';

/// Raster mode renders each tile to an image once; a pinch then only scales
/// images. Vector mode re-renders every visible tile's geometry on every
/// zoom frame, which measured 20-40x the per-frame cost and janked zooming.
/// flutter_map keeps loaded parent/child tiles on screen until the next zoom
/// level's tiles are ready, so raster mode needs no substitution knob.
const openFreeMapLayerMode = VectorTileLayerMode.raster;

typedef MapStyleLoader = Future<Style> Function(MapStyle style);

/// Split out so the loading and retry paths can be exercised without network.
final openFreeMapStyleLoaderProvider = Provider<MapStyleLoader>(
  (ref) =>
      (style) => StyleReader(uri: style.url).read(),
);

/// Each style, with its tile sources and sprites, fetched once per app run.
/// vector_map_tiles caches the tiles themselves on disk.
final openFreeMapStyleProvider = FutureProvider.family<Style, MapStyle>((
  ref,
  mapStyle,
) async {
  final style = await ref.watch(openFreeMapStyleLoaderProvider)(mapStyle);
  return Style(
    name: style.name,
    // Every OpenFreeMap style parses with the same theme id ("default").
    // vector_map_tiles keys its rendered-tile disk cache, sprite atlas and
    // tile widgets by that id, so without a unique one a switch would show
    // the other style's cached tiles.
    theme: style.theme.copyWith(id: openFreeMapThemeId(mapStyle)),
    providers: style.providers,
    sprites: style.sprites,
    center: style.center,
    zoom: style.zoom,
  );
});

String openFreeMapThemeId(MapStyle style) =>
    'openfreemap-${style.openFreeMapName}';

/// The base map under the route and markers. Tests override this so no
/// style or tile request leaves the machine.
final baseMapLayerProvider = Provider<Widget>(
  (ref) => const OpenFreeMapLayer(),
);

/// The driver's chosen OpenFreeMap style as a flutter_map layer, over the
/// style's own ground colour. A branded skeleton in the same palette shows
/// while the style loads; if it fails, a chip offers a real provider refresh.
class OpenFreeMapLayer extends ConsumerWidget {
  const OpenFreeMapLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapStyle = ref.watch(mapStyleProvider);
    return ref
        .watch(openFreeMapStyleProvider(mapStyle))
        .when(
          skipLoadingOnRefresh: false,
          data: (style) => Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                key: const Key('map-ground'),
                color: mapStyle.ground,
              ),
              VectorTileLayer(
                // A new layer per style: nothing rendered for the previous
                // style (tiles, caches) survives a switch.
                key: ValueKey(mapStyle),
                theme: style.theme,
                sprites: style.sprites,
                tileProviders: style.providers,
                layerMode: openFreeMapLayerMode,
              ),
            ],
          ),
          loading: () => MapLoadingSkeleton(style: mapStyle),
          error: (error, _) => Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(KoraSpacing.gutter),
              child: MapChip(
                icon: TablerIcons.map2,
                message: "The map didn't load. Your route still works.",
                actionLabel: 'Retry',
                onAction: () =>
                    ref.invalidate(openFreeMapStyleProvider(mapStyle)),
              ),
            ),
          ),
        );
  }
}

/// A quiet street-grid placeholder in the chosen map style's palette, instead
/// of a blank canvas or bare spinner. Only while the style loads: under live
/// tiles, a static fake street grid would show through as a second map.
class MapLoadingSkeleton extends StatelessWidget {
  const MapLoadingSkeleton({super.key, required this.style});

  final MapStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Map loading',
      child: ExcludeSemantics(
        child: ColoredBox(
          key: const Key('map-loading-skeleton'),
          color: style.ground,
          child: CustomPaint(painter: _StreetGridPainter(dark: style.isDark)),
        ),
      ),
    );
  }
}

class _StreetGridPainter extends CustomPainter {
  const _StreetGridPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = dark
          ? KoraColors.divider
          : KoraColors.mapSkeletonLightRoad
      ..strokeWidth = KoraMap.skeletonRoadWidth
      ..style = PaintingStyle.stroke;
    final major = Paint()
      ..color = KoraColors.primaryTint
      ..strokeWidth = KoraMap.skeletonMainRoadWidth
      ..style = PaintingStyle.stroke;
    final buildings = Paint()
      ..color = dark
          ? KoraColors.elevated
          : KoraColors.mapSkeletonLightBlock
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
          const Radius.circular(KoraRadius.control),
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
  bool shouldRepaint(covariant _StreetGridPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

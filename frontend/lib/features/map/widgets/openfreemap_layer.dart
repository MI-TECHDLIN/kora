import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../../core/theme/tokens.dart';
import 'map_chip.dart';

/// OpenFreeMap's dark style: free OpenStreetMap vector tiles, no API key,
/// no billing account, no usage limits (https://openfreemap.org).
const openFreeMapStyleUrl = 'https://tiles.openfreemap.org/styles/dark';

/// The style, its tile sources and sprites, fetched once per app run.
/// vector_map_tiles caches the tiles themselves on disk.
final openFreeMapStyleProvider = FutureProvider<Style>(
  (ref) => StyleReader(uri: openFreeMapStyleUrl).read(),
);

/// The base map under the route and markers. Tests override this so no
/// style or tile request leaves the machine.
final baseMapLayerProvider = Provider<Widget>(
  (ref) => const OpenFreeMapLayer(),
);

/// OpenFreeMap tiles as a flutter_map layer. Until the style loads the map
/// shows its canvas background; if it fails, a chip offers a retry.
class OpenFreeMapLayer extends ConsumerWidget {
  const OpenFreeMapLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(openFreeMapStyleProvider)
        .when(
          data: (style) => VectorTileLayer(
            theme: style.theme,
            sprites: style.sprites,
            tileProviders: style.providers,
          ),
          loading: () => const SizedBox.shrink(),
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

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/heading_provider.dart';
import '../../../providers/location_provider.dart';
import '../../../providers/vehicle_mode_provider.dart';
import 'openfreemap_layer.dart';

/// Starts the lightweight map dependencies with the app instead of making the
/// Map tab pay their cold-start cost. This does not build an offstage map.
class MapWarmup extends ConsumerWidget {
  const MapWarmup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mapEnginePreWarmProvider);
    ref.watch(locationProvider);
    ref.watch(headingProvider);
    ref.watch(vehicleModeProvider);
    return child;
  }
}

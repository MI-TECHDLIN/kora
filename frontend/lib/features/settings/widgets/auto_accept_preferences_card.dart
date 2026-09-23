import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../providers/auto_accept_preferences_provider.dart';
import '../../../providers/location_provider.dart';

/// Settings' auto-accept editor: the on/off switch, plus the driver's own
/// max-distance, preferred/avoided areas and order-type rules. Reads and
/// writes the same `driver_preferences` keys a voice command does
/// (`auto_accept_preferences_provider.dart`), so this is the one place a
/// driver can see and override whatever they told the co-rider — the
/// captain's "remains in control" requirement. Off by default; nothing here
/// changes that.
class AutoAcceptPreferencesCard extends ConsumerWidget {
  const AutoAcceptPreferencesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(autoAcceptPreferencesProvider);
    final controller = ref.read(autoAcceptPreferencesProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: KoraSize.touchTarget),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-accept orders', style: KoraText.label),
                    const SizedBox(height: KoraSpacing.xs),
                    Text(
                      'Let your co-rider take matching orders for you — '
                      'always out loud, never silent',
                      style: KoraText.bodyMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KoraSpacing.md),
              Switch(
                key: const Key('auto-accept-toggle'),
                value: prefs.enabled,
                onChanged: controller.setEnabled,
              ),
            ],
          ),
        ),
        if (prefs.enabled) ...[
          const Divider(height: KoraSpacing.xl),
          _MaxDistanceRow(
            maxDistanceKm: prefs.maxDistanceKm,
            onChanged: controller.setMaxDistanceKm,
          ),
          const SizedBox(height: KoraSpacing.lg),
          _ZonesEditor(
            zones: prefs.zones,
            onAdd: controller.addZone,
            onRemove: controller.removeZone,
          ),
          const SizedBox(height: KoraSpacing.lg),
          _CategoriesEditor(
            categories: prefs.acceptedCategories,
            onAdd: controller.addCategory,
            onRemove: controller.removeCategory,
          ),
        ],
      ],
    );
  }
}

class _MaxDistanceRow extends StatelessWidget {
  const _MaxDistanceRow({required this.maxDistanceKm, required this.onChanged});

  final double? maxDistanceKm;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Max pickup distance', style: KoraText.label),
              const SizedBox(height: KoraSpacing.xs),
              Text('Blank means no distance limit', style: KoraText.bodyMuted),
            ],
          ),
        ),
        const SizedBox(width: KoraSpacing.md),
        SizedBox(
          width: 84,
          child: TextFormField(
            key: ValueKey('max-distance-${maxDistanceKm ?? 'none'}'),
            initialValue: maxDistanceKm == null
                ? ''
                : _trimmed(maxDistanceKm!),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.end,
            style: KoraText.body,
            decoration: const InputDecoration(suffixText: ' km', isDense: true),
            onFieldSubmitted: (value) =>
                onChanged(double.tryParse(value.trim())),
          ),
        ),
      ],
    );
  }

  static String _trimmed(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}

class _ZonesEditor extends ConsumerWidget {
  const _ZonesEditor({
    required this.zones,
    required this.onAdd,
    required this.onRemove,
  });

  final List<AutoAcceptZone> zones;
  final ValueChanged<AutoAcceptZone> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preferred & avoided areas', style: KoraText.label),
        const SizedBox(height: KoraSpacing.sm),
        Wrap(
          spacing: KoraSpacing.sm,
          runSpacing: KoraSpacing.sm,
          children: [
            for (final zone in zones)
              _RemovableChip(
                key: Key('zone-chip-${zone.name}'),
                icon: zone.avoided ? TablerIcons.mapPinOff : TablerIcons.mapPin,
                label: '${zone.name} · ${_trimmed(zone.radiusKm)} km',
                tinted: !zone.avoided,
                onRemove: () => onRemove(zone.name),
              ),
            _AddChip(
              key: const Key('add-zone-button'),
              label: 'Add area',
              onTap: () => _addZone(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  static String _trimmed(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  Future<void> _addZone(BuildContext context, WidgetRef ref) async {
    final here = ref.read(locationProvider).valueOrNull?.point;
    final controller = ref.read(autoAcceptPreferencesProvider.notifier);
    final zone = await showDialog<AutoAcceptZone>(
      context: context,
      builder: (context) => _AddZoneDialog(
        centerLat: here?.latitude,
        centerLng: here?.longitude,
      ),
    );
    if (zone != null) controller.addZone(zone);
  }
}

class _AddZoneDialog extends StatefulWidget {
  const _AddZoneDialog({this.centerLat, this.centerLng});

  final double? centerLat;
  final double? centerLng;

  @override
  State<_AddZoneDialog> createState() => _AddZoneDialogState();
}

class _AddZoneDialogState extends State<_AddZoneDialog> {
  final _name = TextEditingController();
  final _radius = TextEditingController(text: '3');
  bool _avoided = false;

  @override
  void dispose() {
    _name.dispose();
    _radius.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add an area'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('zone-name-field'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Area name'),
            autofocus: true,
          ),
          const SizedBox(height: KoraSpacing.md),
          TextField(
            key: const Key('zone-radius-field'),
            controller: _radius,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Radius (km)'),
          ),
          const SizedBox(height: KoraSpacing.md),
          Wrap(
            spacing: KoraSpacing.sm,
            children: [
              ChoiceChip(
                key: const Key('zone-type-preferred'),
                label: const Text('Preferred'),
                selected: !_avoided,
                onSelected: (_) => setState(() => _avoided = false),
              ),
              ChoiceChip(
                key: const Key('zone-type-avoided'),
                label: const Text('Avoided'),
                selected: _avoided,
                onSelected: (_) => setState(() => _avoided = true),
              ),
            ],
          ),
          if (widget.centerLat == null) ...[
            const SizedBox(height: KoraSpacing.sm),
            Text(
              "Can't read your location right now — centred at (0, 0) until it can.",
              style: KoraText.bodyMuted,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('zone-save-button'),
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(
              AutoAcceptZone(
                name: name,
                avoided: _avoided,
                radiusKm: double.tryParse(_radius.text.trim()) ?? 3,
                centerLat: widget.centerLat,
                centerLng: widget.centerLng,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CategoriesEditor extends StatelessWidget {
  const _CategoriesEditor({
    required this.categories,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> categories;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Order types', style: KoraText.label),
        const SizedBox(height: KoraSpacing.xs),
        Text('Blank accepts every order type', style: KoraText.bodyMuted),
        const SizedBox(height: KoraSpacing.sm),
        Wrap(
          spacing: KoraSpacing.sm,
          runSpacing: KoraSpacing.sm,
          children: [
            for (final category in categories)
              _RemovableChip(
                key: Key('category-chip-$category'),
                icon: TablerIcons.package,
                label: category,
                tinted: true,
                onRemove: () => onRemove(category),
              ),
            _AddChip(
              key: const Key('add-category-button'),
              label: 'Add type',
              onTap: () => _addCategory(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addCategory(BuildContext context) async {
    final controller = TextEditingController();
    final category = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add an order type'),
        content: TextField(
          key: const Key('category-name-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'e.g. Food, Documents'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('category-save-button'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (category != null) onAdd(category);
  }
}

/// A tappable pill with a trailing remove icon: one preferred/avoided area
/// or one accepted order type.
class _RemovableChip extends StatelessWidget {
  const _RemovableChip({
    super.key,
    required this.icon,
    required this.label,
    required this.tinted,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final bool tinted;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoraSpacing.md,
        vertical: KoraSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tinted ? KoraColors.primaryTint : KoraColors.elevated,
        borderRadius: BorderRadius.circular(KoraRadius.pill),
        border: Border.all(
          color: tinted ? KoraColors.primaryLight : KoraColors.divider,
          width: KoraGlass.borderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: KoraSize.iconSm, color: KoraColors.textPrimary),
          const SizedBox(width: KoraSpacing.xs),
          Text(label, style: KoraText.label),
          const SizedBox(width: KoraSpacing.xs),
          GestureDetector(
            key: Key('remove-$label'),
            onTap: onRemove,
            child: const Icon(TablerIcons.x, size: KoraSize.iconSm),
          ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(KoraRadius.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KoraSpacing.md,
          vertical: KoraSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: KoraColors.elevated,
          borderRadius: BorderRadius.circular(KoraRadius.pill),
          border: Border.all(color: KoraColors.divider, width: KoraGlass.borderWidth),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(TablerIcons.plus, size: KoraSize.iconSm, color: KoraColors.textMuted),
            const SizedBox(width: KoraSpacing.xs),
            Text(label, style: KoraText.label),
          ],
        ),
      ),
    );
  }
}

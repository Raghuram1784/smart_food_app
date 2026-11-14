import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'catalog.dart';

/// Customer food-type preference. Default: both. Changing it never touches the cart.
enum DietPreference { both, veg, nonVeg }

extension DietPreferenceApi on DietPreference {
  /// Value for the backend `diet` query parameter (null = no filter).
  String? get api => switch (this) {
    DietPreference.veg => 'veg',
    DietPreference.nonVeg => 'nonveg',
    DietPreference.both => null,
  };

  String get label => switch (this) {
    DietPreference.veg => 'Veg',
    DietPreference.nonVeg => 'Non-Veg',
    DietPreference.both => 'Both',
  };

  /// Applies to server-provided `isVegetarian` only; unknown classification is
  /// shown under Both but never claimed as veg or non-veg.
  bool allows(Dish d) => switch (this) {
    DietPreference.both => true,
    DietPreference.veg => d.isVegetarian == true,
    DietPreference.nonVeg => d.isVegetarian == false,
  };
}

class DietPreferenceNotifier extends Notifier<DietPreference> {
  static const _key = 'diet_preference';
  @override
  DietPreference build() {
    try {
      final v = ref.read(preferencesProvider).getString(_key);
      return DietPreference.values.where((d) => d.name == v).firstOrNull ?? DietPreference.both;
    } catch (_) {
      return DietPreference.both;
    }
  }

  Future<void> select(DietPreference value) async {
    state = value;
    try {
      await ref.read(preferencesProvider).setString(_key, value.name);
    } catch (_) {}
  }
}

final dietPreferenceProvider = NotifierProvider<DietPreferenceNotifier, DietPreference>(DietPreferenceNotifier.new);

/// Veg | Non-Veg | Both selector used on Home, Search and menus.
class DietSelector extends ConsumerWidget {
  const DietSelector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(dietPreferenceProvider);
    return SegmentedButton<DietPreference>(
      key: const ValueKey('diet-selector'),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: DietPreference.veg, label: Text('Veg'), icon: VegMark(veg: true)),
        ButtonSegment(value: DietPreference.nonVeg, label: Text('Non-Veg'), icon: VegMark(veg: false)),
        ButtonSegment(value: DietPreference.both, label: Text('Both')),
      ],
      selected: {value},
      onSelectionChanged: (s) => ref.read(dietPreferenceProvider.notifier).select(s.first),
    );
  }
}

/// Standard Indian veg (green) / non-veg (red) square mark.
class VegMark extends StatelessWidget {
  final bool veg;
  final double size;
  const VegMark({super.key, required this.veg, this.size = 14});
  @override
  Widget build(BuildContext context) {
    final color = veg ? const Color(0xFF1B8A3A) : const Color(0xFFB3261E);
    return Semantics(
      label: veg ? 'Vegetarian' : 'Non-vegetarian',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(border: Border.all(color: color, width: 1.5), borderRadius: BorderRadius.circular(2)),
        alignment: Alignment.center,
        child: Container(
          width: size * 0.5,
          height: size * 0.5,
          decoration: BoxDecoration(color: color, shape: veg ? BoxShape.circle : BoxShape.rectangle),
        ),
      ),
    );
  }
}

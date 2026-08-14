import 'package:flutter/material.dart';

import '../x3_profile.dart';

/// One DPI stage editor: active selector, LED color, slider + value, and a
/// few common quick-preset chips.
class DpiStageEditor extends StatelessWidget {
  const DpiStageEditor({
    super.key,
    required this.stage,
    required this.dpi,
    required this.isActive,
    required this.onSelectActive,
    required this.onChanged,
  });

  final int stage;
  final int dpi;
  final bool isActive;
  final VoidCallback onSelectActive;
  final ValueChanged<int> onChanged;

  static const List<int> _presets = [800, 1000, 1600, 2400, 3200, 5000];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final led = x3StageLed[stage];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Active selector (custom circle, no Radio deprecation risk).
              InkWell(
                onTap: onSelectActive,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: isActive
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: theme.colorScheme.onPrimary,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: led.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stage ${stage + 1}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Active · ${led.name}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Text(
                  led.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: 50,
                  max: 26000,
                  divisions: ((26000 - 50) / 50).round(),
                  value: dpi.toDouble().clamp(50, 26000),
                  label: '$dpi',
                  onChanged: (v) => onChanged(X3Profile.clampDpi(v.round())),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  '$dpi',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in _presets)
                  ChoiceChip(
                    label: Text('$p'),
                    selected: p == dpi,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onChanged(p),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

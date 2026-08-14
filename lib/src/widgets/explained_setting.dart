import 'package:flutter/material.dart';

/// A labeled setting with a plain-English explanation and a help button that
/// opens a longer explanation in a bottom sheet.
///
/// Use [control] for full-width controls (sliders, dropdowns) rendered under
/// the explanation, or [trailing] for compact controls (switches) placed on
/// the title row.
class ExplainedSetting extends StatelessWidget {
  const ExplainedSetting({
    super.key,
    required this.title,
    this.icon,
    this.explanation,
    this.detail,
    this.control,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final String? explanation;
  final String? detail;
  final Widget? control;
  final Widget? trailing;

  void _showInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  detail ?? explanation ?? '',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ?trailing,
              IconButton(
                icon: const Icon(Icons.help_outline, size: 20),
                tooltip: 'What does this do?',
                visualDensity: VisualDensity.compact,
                onPressed: () => _showInfo(context),
              ),
            ],
          ),
          if (explanation != null) ...[
            const SizedBox(height: 4),
            Text(
              explanation!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (control != null) ...[const SizedBox(height: 8), control!],
        ],
      ),
    );
  }
}

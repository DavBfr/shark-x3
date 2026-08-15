import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// The apply bar: send settings to the mouse, reset, and profile menu.
class ApplyBar extends StatelessWidget {
  const ApplyBar({
    super.key,
    required this.connected,
    required this.busy,
    required this.onApply,
    required this.onReset,
    required this.onSaveProfile,
    required this.onLoadProfile,
  });

  final bool connected;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onReset;
  final VoidCallback onSaveProfile;
  final VoidCallback onLoadProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Apply',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing is sent to the mouse until you press “Apply to mouse”. '
              'Change as much as you like first.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: connected && !busy ? onApply : null,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(busy ? 'Applying…' : 'Apply to mouse'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onReset,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset to defaults'),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  enabled: !busy,
                  onSelected: (value) {
                    if (value == 'save') onSaveProfile();
                    if (value == 'load') onLoadProfile();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'save',
                      child: ListTile(
                        leading: Icon(Icons.save_outlined),
                        title: Text('Save profile…'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'load',
                      child: ListTile(
                        leading: Icon(Icons.folder_open),
                        title: Text('Load profile…'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmarks,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text('Profiles', style: theme.textTheme.labelLarge),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

@Preview(name: 'Apply Bar')
Widget applyBarPreview() {
  return ApplyBar(
    connected: true,
    busy: false,
    onApply: () {},
    onReset: () {},
    onSaveProfile: () {},
    onLoadProfile: () {},
  );
}

@Preview(name: 'Apply Bar (Busy)')
Widget applyBarBusyPreview() {
  return ApplyBar(
    connected: true,
    busy: true,
    onApply: () {},
    onReset: () {},
    onSaveProfile: () {},
    onLoadProfile: () {},
  );
}

@Preview(name: 'Apply Bar (Disconnected)')
Widget applyBarDisconnectedPreview() {
  return ApplyBar(
    connected: false,
    busy: false,
    onApply: () {},
    onReset: () {},
    onSaveProfile: () {},
    onLoadProfile: () {},
  );
}

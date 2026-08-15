import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../x3_status.dart';

/// Live monitor card: shows the raw bytes of the status reports the mouse
/// pushes on the config interface, plus what we've decoded so far.
class StatusMonitor extends StatelessWidget {
  const StatusMonitor({
    super.key,
    required this.connected,
    required this.reports,
  });

  /// Whether the mouse is connected (reports only stream while connected).
  final bool connected;

  /// Recent reports, oldest first; the widget shows them newest-first.
  final List<X3StatusReport> reports;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.monitor_heart_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live monitor',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'The mouse sends these small reports over the config interface. '
              'The hex line is raw; the note below it is what we’ve decoded so '
              'far. In the 0x40 wireless-status report the last byte looks '
              'like battery ÷ 10 (0a = 100%, 07 = 70%) — a candidate until '
              'confirmed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (!connected)
              Text(
                'Connect the mouse to see live status.',
                style: theme.textTheme.bodyMedium,
              )
            else if (reports.isEmpty)
              Text(
                'Waiting for reports… (move the mouse or press the DPI button)',
                style: theme.textTheme.bodyMedium,
              )
            else
              ...reports.reversed.map((r) => _row(context, r)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, X3StatusReport r) {
    final theme = Theme.of(context);
    final IconData icon = switch (r.kind) {
      X3StatusKind.dpiStage => Icons.speed,
      X3StatusKind.status => Icons.battery_unknown,
      X3StatusKind.writeAck => Icons.check_circle_outline,
      X3StatusKind.unknown => Icons.help_outline,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.rawHex,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  r.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sample decoded reports used by the IDE preview.
const List<X3StatusReport> _previewReports = [
  X3StatusReport(
    raw: [0x03, 0x00, 0x10, 0x03, 0x00],
    kind: X3StatusKind.dpiStage,
    dpiStage: 3,
    description: 'DPI stage changed → 3',
  ),
  X3StatusReport(
    raw: [0x03, 0x10, 0x40, 0x01, 0x0a],
    kind: X3StatusKind.status,
    stateByte: 0x40,
    batteryPercent: 100,
    description: 'Wireless status — battery ≈ 100% (candidate) · link 0x40',
  ),
  X3StatusReport(
    raw: [0x03, 0x10, 0x50, 0x01, 0x04],
    kind: X3StatusKind.writeAck,
    description: 'Config write acknowledged',
  ),
];

/// IDE preview for the [StatusMonitor] widget.
@Preview(name: 'StatusMonitor')
Widget statusMonitorPreview() =>
    StatusMonitor(connected: true, reports: _previewReports);

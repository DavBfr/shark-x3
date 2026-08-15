import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// The connection card: status, connect/disconnect, and friendly guidance.
class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.connected,
    required this.busy,
    required this.productName,
    required this.statusMessage,
    required this.onConnect,
    required this.onDisconnect,
    this.mouseAwake,
  });

  final bool connected;
  final bool busy;
  final String productName;
  final String statusMessage;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  /// null = no wireless status seen yet; otherwise awake/sleeping.
  final bool? mouseAwake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = connected ? const Color(0xFF43A047) : theme.colorScheme.error;
    final label = connected ? 'Connected' : 'Not connected';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 12, color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (connected && mouseAwake != null) ...[
                  _awakeChip(context),
                  const SizedBox(width: 8),
                ],
                if (connected)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onDisconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                  )
                else
                  FilledButton.icon(
                    onPressed: busy ? null : onConnect,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.usb),
                    label: Text(busy ? 'Connecting…' : 'Connect mouse'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (connected)
              Text(
                productName.isEmpty ? 'Attack Shark X3' : productName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Text(
                'Plug in your mouse with a cable and press “Connect mouse”. '
                'If it doesn’t show up, try a different USB port.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (statusMessage.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(statusMessage, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  /// Small "Awake" / "Sleeping" chip, inferred from the 0x40 wireless-status
  /// heartbeat (absent for a while → sleeping).
  Widget _awakeChip(BuildContext context) {
    final theme = Theme.of(context);
    final awake = mouseAwake == true;
    final chipColor = awake ? const Color(0xFF43A047) : const Color(0xFFF9A825);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chipColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: chipColor),
          const SizedBox(width: 5),
          Text(
            awake ? 'Awake' : 'Sleeping',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}

@Preview(name: 'Connection Card')
Widget connectionCardPreview() {
  return ConnectionCard(
    connected: false,
    busy: false,
    onConnect: () {},
    onDisconnect: () {},
    productName: 'Attack Shark X3',
    statusMessage: '',
  );
}

@Preview(name: 'Connection Card (connected)')
Widget connectionCardConnectedPreview() {
  return ConnectionCard(
    connected: true,
    busy: false,
    onConnect: () {},
    onDisconnect: () {},
    productName: 'Attack Shark X3',
    statusMessage: 'ready to go',
  );
}

@Preview(name: 'Connection Card (busy)')
Widget connectionCardBusyPreview() {
  return ConnectionCard(
    connected: false,
    busy: true,
    onConnect: () {},
    onDisconnect: () {},
    productName: '',
    statusMessage: 'connecting…',
  );
}

@Preview(name: 'Connection Card (awake)')
Widget connectionCardAwakePreview() {
  return ConnectionCard(
    connected: true,
    busy: false,
    onConnect: () {},
    onDisconnect: () {},
    productName: 'Attack Shark X3',
    statusMessage: '',
    mouseAwake: true,
  );
}

@Preview(name: 'Connection Card (not awake)')
Widget connectionCardNotAwakePreview() {
  return ConnectionCard(
    connected: true,
    busy: false,
    onConnect: () {},
    onDisconnect: () {},
    productName: 'Attack Shark X3',
    statusMessage: '',
    mouseAwake: false,
  );
}

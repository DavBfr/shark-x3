import 'package:flutter/material.dart';

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
  });

  final bool connected;
  final bool busy;
  final String productName;
  final String statusMessage;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

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
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
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
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Text(
                'Plug in your mouse with a cable and press “Connect mouse”. '
                'If it doesn’t show up, try a different USB port.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
}

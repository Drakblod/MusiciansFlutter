import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/event_address_map.dart';

class OpenEventAddressButton extends StatelessWidget {
  const OpenEventAddressButton({super.key, required this.address, required this.city});

  final String address;
  final String city;

  @override
  Widget build(BuildContext context) {
    final uri = eventAddressMapUri(address, city: city);
    if (uri == null) return const SizedBox.shrink();

    return TextButton.icon(
      icon: const Icon(Icons.open_in_new, size: 16),
      label: const Text('Open in Google Maps'),
      onPressed: () async {
        try {
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
        } catch (_) {
          // The address remains visible and can still be copied manually.
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      },
    );
  }
}

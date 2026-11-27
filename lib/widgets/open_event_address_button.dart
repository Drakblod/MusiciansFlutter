import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/event_address_map.dart';

class OpenEventAddressButton extends StatelessWidget {
  const OpenEventAddressButton({
    super.key,
    required String address,
    required this.city,
  }) : address = address,
       _freeForm = false;

  const OpenEventAddressButton.forLocation({super.key, required this.address})
    : city = '',
      _freeForm = true;

  final String? address;
  final String city;
  final bool _freeForm;

  @override
  Widget build(BuildContext context) {
    final uri = _freeForm
        ? eventLocationMapUri(address)
        : eventAddressMapUri(address!, city: city);
    if (uri == null) return const SizedBox.shrink();

    return TextButton.icon(
      icon: const Icon(Icons.open_in_new, size: 16),
      label: const Text('Open in Google Maps'),
      onPressed: () async {
        try {
          if (await launchUrl(uri, mode: LaunchMode.externalApplication))
            return;
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

class EventAddressFieldLink extends StatelessWidget {
  const EventAddressFieldLink({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) => Align(
          alignment: Alignment.centerLeft,
          child: OpenEventAddressButton.forLocation(address: value.text),
        ),
      );
}

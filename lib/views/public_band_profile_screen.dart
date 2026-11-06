import 'package:flutter/material.dart';
import '../models/band.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';

/// Displays only the server-allowlisted catalogue model supplied by the caller.
class PublicBandProfileScreen extends StatelessWidget {
  const PublicBandProfileScreen({super.key, required this.band});
  final Band band;

  @override
  Widget build(BuildContext context) => GradientScaffold(
    appBar: const CustomTopBar(title: 'Band Profile', showBack: true),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(band.name ?? 'Band', style: Theme.of(context).textTheme.headlineSmall),
      if (band.ensembleType?.isNotEmpty ?? false) Text(band.ensembleType!),
      if (band.location?.isNotEmpty ?? false) Text(band.location!),
      if (band.genres.isNotEmpty) Text(band.genres.join(', ')),
      if (band.style?.isNotEmpty ?? false) Text(band.style!),
      if (band.level?.isNotEmpty ?? false) Text(band.level!),
      if (band.activeMemberCount != null) Text('${band.activeMemberCount} members'),
      if (band.description?.isNotEmpty ?? false) ...[
        const SizedBox(height: 16), Text(band.description!),
      ],
      if ((band.about?.isNotEmpty ?? false) && band.about != band.description) ...[
        const SizedBox(height: 16), Text(band.about!),
      ],
    ]),
  );
}

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme/app_theme.dart';

Map<int, DateTime> messageDateDividers(List<Message> messages) {
  final dates = <int, DateTime>{};
  DateTime? previousDate;
  for (var index = 0; index < messages.length; index++) {
    final date = messages[index].timestamp?.toLocal();
    if (date == null) continue;
    if (!DateUtils.isSameDay(previousDate, date)) dates[index] = date;
    previousDate = date;
  }
  return dates;
}

class MessageDateDivider extends StatelessWidget {
  const MessageDateDivider({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final label = MaterialLocalizations.of(context).formatFullDate(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppTheme.textSecondary),
      ),
    );
  }
}

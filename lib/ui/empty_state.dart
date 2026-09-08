import 'package:flutter/material.dart';

import 'theme.dart';

class RecordEmptyState extends StatelessWidget {
  const RecordEmptyState({
    super.key,
    required this.count,
    required this.action,
  });

  final String count;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(Dim.s4),
      padding: const EdgeInsets.all(Dim.s4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(Dim.radiusControl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(count, style: HmmmType.of(context).figure),
          const SizedBox(height: Dim.s1),
          Text(
            action,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

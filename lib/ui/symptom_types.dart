import 'package:flutter/material.dart';

import '../data/symptom_repository.dart';
import '../domain/models.dart';
import 'empty_state.dart';
import 'feedback.dart';
import 'symptom_glyph.dart';
import 'theme.dart';

class SymptomTypesScreen extends StatelessWidget {
  const SymptomTypesScreen({super.key, required this.repository});

  final SymptomRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, child) => FutureBuilder<_SymptomTypeData>(
        future: _loadData(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          final types = data?.types;
          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Symptom types'),
                  if (types != null)
                    Text(
                      '${types.length} ${types.length == 1 ? 'type' : 'types'}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            body: types == null
                ? const SizedBox.shrink()
                : types.isEmpty
                ? const RecordEmptyState(
                    count: '0 symptom types',
                    action: 'Tap Add symptom type.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: types.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final type = types[index];
                      final count = data!.entryCounts[type.id] ?? 0;
                      return ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: Dim.rowMinHeight,
                        ),
                        child: ListTile(
                          key: ValueKey('symptom-type-${type.id}'),
                          leading: SymptomGlyphMark(
                            typeId: type.id!,
                            size: Dim.glyphSizeList,
                          ),
                          title: Row(
                            children: [
                              Expanded(child: Text(type.name)),
                              if (!type.builtin)
                                Text(
                                  'custom',
                                  style: HmmmType.of(context).figureSmall,
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '$count ${count == 1 ? 'entry' : 'entries'}',
                            style: HmmmType.of(context).figureSmall.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          trailing: type.builtin
                              ? null
                              : IconButton(
                                  key: ValueKey(
                                    'delete-symptom-type-${type.id}',
                                  ),
                                  tooltip: 'Delete ${type.name}',
                                  onPressed: () =>
                                      _deleteType(context, type, count),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                        ),
                      );
                    },
                  ),
            floatingActionButton: FloatingActionButton.extended(
              key: const ValueKey('add-symptom-type'),
              tooltip: 'Add symptom type',
              onPressed: () => _addType(context),
              icon: const Icon(Icons.add),
              label: const Text('Add symptom type'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Dim.radiusControl),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<_SymptomTypeData> _loadData() async => _SymptomTypeData(
    types: await repository.listTypes(),
    entryCounts: await repository.entryCountsByType(),
  );

  Future<void> _addType(BuildContext context) async {
    var typeName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Symptom type'),
        content: TextField(
          key: const ValueKey('symptom-type-name'),
          autofocus: true,
          onChanged: (value) => typeName = value,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-add-symptom-type'),
            onPressed: () => Navigator.pop(context, typeName.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    try {
      await repository.insertType(SymptomType(name: name, builtin: false));
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }

  Future<void> _deleteType(
    BuildContext context,
    SymptomType type,
    int entryCount,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${type.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(type.name, style: HmmmType.of(context).figure),
            const SizedBox(height: Dim.s1),
            Text(
              '$entryCount recorded '
              '${entryCount == 1 ? 'entry is' : 'entries are'} removed.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-symptom-type'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await repository.deleteType(type.id!);
  }
}

class _SymptomTypeData {
  const _SymptomTypeData({required this.types, required this.entryCounts});

  final List<SymptomType> types;
  final Map<int, int> entryCounts;
}

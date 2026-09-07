import 'package:flutter/material.dart';

import '../data/symptom_repository.dart';
import '../domain/models.dart';
import 'feedback.dart';
import 'symptom_glyph.dart';

class SymptomTypesScreen extends StatelessWidget {
  const SymptomTypesScreen({super.key, required this.repository});

  final SymptomRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, child) => FutureBuilder<List<SymptomType>>(
        future: repository.listTypes(),
        builder: (context, snapshot) {
          final types = snapshot.data;
          return Scaffold(
            appBar: AppBar(title: const Text('Symptom types')),
            body: types == null
                ? const SizedBox.shrink()
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: types.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final type = types[index];
                      return ListTile(
                        key: ValueKey('symptom-type-${type.id}'),
                        leading: SymptomGlyphMark(typeId: type.id!, size: 16),
                        title: Text(type.name),
                        trailing: type.builtin
                            ? null
                            : IconButton(
                                key: ValueKey('delete-symptom-type-${type.id}'),
                                tooltip: 'Delete ${type.name}',
                                onPressed: () => _deleteType(context, type),
                                icon: const Icon(Icons.delete_outline),
                              ),
                      );
                    },
                  ),
            floatingActionButton: FloatingActionButton(
              key: const ValueKey('add-symptom-type'),
              tooltip: 'Add symptom type',
              onPressed: () => _addType(context),
              child: const Icon(Icons.add),
            ),
          );
        },
      ),
    );
  }

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

  Future<void> _deleteType(BuildContext context, SymptomType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('Delete ${type.name}? Its logged entries are removed.'),
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

import 'package:flutter/material.dart';

import 'theme.dart';

class BandColourPicker extends StatelessWidget {
  const BandColourPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
    required this.keyPrefix,
  });

  final String selectedId;
  final ValueChanged<String> onSelected;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Wrap(
      children: [
        for (final swatch in bandColourSwatches)
          Semantics(
            label:
                '${swatch.name}${swatch.id == selectedId ? ', selected' : ''}',
            button: true,
            selected: swatch.id == selectedId,
            child: ExcludeSemantics(
              child: InkResponse(
                key: ValueKey('$keyPrefix-${swatch.id}'),
                onTap: () => onSelected(swatch.id),
                radius: Dim.minTarget / 2,
                child: SizedBox(
                  width: Dim.minTarget,
                  height: Dim.minTarget,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: swatch.forBrightness(brightness),
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: swatch.id == selectedId
                            ? Icon(
                                Icons.check,
                                size: 20,
                                color: Markers.of(context).inkOnBand,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// Filter chip that follows [ThemeData.chipTheme] and Material 3 tap targets.
class HuddleFilterChip extends StatelessWidget {
  const HuddleFilterChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.avatar,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      avatar: avatar,
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: true,
    );
  }
}

import 'package:flutter/material.dart';

/// YouTube filter chip: grey pill, inverted colours when selected.
class YtChip extends StatelessWidget {
  const YtChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? scheme.onSurface : scheme.surfaceContainerHighest;
    final fg = selected ? scheme.surface : scheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
              Text(
                label,
                style: TextStyle(color: fg, fontWeight: FontWeight.w500, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

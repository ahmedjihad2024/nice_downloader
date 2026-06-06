import 'package:flutter/material.dart';

import '../theme.dart';

/// URL input row: paste a link, press Enter or tap "Add".
class AddUrlField extends StatefulWidget {
  const AddUrlField({super.key, required this.onAdd});

  final void Function(String url) onAdd;

  @override
  State<AddUrlField> createState() => _AddUrlFieldState();
}

class _AddUrlFieldState extends State<AddUrlField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    widget.onAdd(url);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Paste a download link…',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              prefixIcon:
                  const Icon(Icons.link_rounded, color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          ),
        ),
      ],
    );
  }
}

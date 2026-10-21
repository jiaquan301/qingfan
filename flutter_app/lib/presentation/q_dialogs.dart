import 'package:flutter/material.dart';

import 'q_style.dart';

/// One coherent modal language for destructive, confirmation and text actions.
abstract final class QDialogs {
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String description,
    String action = '确认',
  }) async {
    final response = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .20),
      builder: (dialogContext) => _QDialogShell(
        title: title,
        content: Text(description, style: QStyle.detail.copyWith(height: 1.6)),
        actions: [
          _QDialogAction(
            text: '取消',
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          _QDialogAction(
            text: action,
            primary: true,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    return response == true;
  }

  static Future<String?> rename(
    BuildContext context, {
    required String current,
  }) async {
    final field = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .20),
      builder: (dialogContext) => _QDialogShell(
        title: '重命名任务',
        content: TextField(
          key: const Key('renameTaskInput'),
          controller: field,
          autofocus: true,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          onSubmitted: (text) {
            final name = text.trim();
            if (name.isNotEmpty) Navigator.pop(dialogContext, name);
          },
          decoration: const InputDecoration(
            hintText: '任务名称',
            counterText: '',
          ),
        ),
        actions: [
          _QDialogAction(
            text: '取消',
            onPressed: () => Navigator.pop(dialogContext),
          ),
          _QDialogAction(
            text: '保存',
            primary: true,
            onPressed: () {
              final name = field.text.trim();
              if (name.isNotEmpty) Navigator.pop(dialogContext, name);
            },
          ),
        ],
      ),
    );
    field.dispose();
    return result;
  }
}

class _QDialogShell extends StatelessWidget {
  const _QDialogShell({
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: QStyle.canvas,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 19),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: QStyle.header),
                const SizedBox(height: 14),
                content,
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions
                      .map((item) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: item,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      );
}

class _QDialogAction extends StatelessWidget {
  const _QDialogAction({
    required this.text,
    required this.onPressed,
    this.primary = false,
  });

  final String text;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: primary ? QStyle.jade : QStyle.selected,
            foregroundColor: primary ? Colors.white : QStyle.ink,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(text),
        ),
      );
}

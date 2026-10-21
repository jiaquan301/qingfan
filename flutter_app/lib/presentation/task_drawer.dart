import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/qingfan_controller.dart';
import '../domain/focus_engine.dart';
import 'q_dialogs.dart';
import 'q_style.dart';

class TaskDrawer extends StatefulWidget {
  const TaskDrawer({
    super.key, required this.controller, required this.onClose,
    required this.onStart,
  });

  final QingfanController controller;
  final VoidCallback onClose;
  final VoidCallback onStart;

  @override
  State<TaskDrawer> createState() => _TaskDrawerState();
}

class _TaskDrawerState extends State<TaskDrawer> {
  final TextEditingController _entry = TextEditingController();
  final TextEditingController _search = TextEditingController();
  bool _completedExpanded = false;
  String? _temporaryMessage;
  Timer? _messageTimer;

  @override
  void dispose() {
    _messageTimer?.cancel();
    _entry.dispose();
    _search.dispose();
    super.dispose();
  }

  void _add() {
    widget.controller.addTask(_entry.text);
    _entry.clear();
  }

  Future<bool> _confirmDiscard() async {
    return QDialogs.confirm(
      context,
      title: '放弃本轮专注？',
      description: '这轮尚未完成的时间会清零，已经完成的番茄记录不受影响。',
      action: '放弃本轮',
    );
  }

  Future<void> _select(QingfanTask task) async {
    final c = widget.controller;
    if (c.engine.isRunning && c.engine.phase == FocusPhase.focus) {
      _message('请先暂停，再切换任务');
      return;
    }
    if (c.engine.hasPartialFocus && !await _confirmDiscard()) return;
    c.selectTask(task.id, discardPartial: true);
  }

  Future<void> _toggleDone(QingfanTask task) async {
    final c = widget.controller;
    if (task.id == c.selectedTaskId &&
        c.engine.isRunning &&
        c.engine.phase == FocusPhase.focus) {
      _message('请先暂停当前专注，再标记完成');
      return;
    }
    if (task.id == c.selectedTaskId &&
        c.engine.hasPartialFocus &&
        !await _confirmDiscard()) {
      return;
    }
    c.completeTask(task.id, discardPartial: true);
  }

  // An undo operation already has one authoritative seven-second expiry in
  // QingfanController. Flutter SnackBars with an action may remain visible
  // indefinitely when accessibility navigation is enabled; their lifetime
  // must not be used as the source of truth for task undo.
  Widget _undoBanner() => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          if (!c.canUndo || c.undoMessage == null) {
            return const SizedBox.shrink(key: Key('undoBannerHidden'));
          }
          return Container(
            key: const Key('undoTaskBanner'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F3EB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.undoMessage!,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF337259),
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('undoTaskAction'),
                  onPressed: c.undoTaskChange,
                  child: const Text('撤销'),
                ),
              ],
            ),
          );
        },
      );

  void _message(String text) {
    _messageTimer?.cancel();
    setState(() => _temporaryMessage = text);
    _messageTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _temporaryMessage = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final query = _search.text.trim().toLowerCase();
    final allPending = c.pending;
    final pending = allPending
        .where((t) => t.title.toLowerCase().contains(query))
        .toList();
    final completed = c.completed
        .where((t) => t.title.toLowerCase().contains(query))
        .toList();
    return Material(
      color: QStyle.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QPanelHeader(
            title: '任务清单',
            subtitle: '${allPending.length} 项待办',
            onClose: widget.onClose,
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _entry,
            key: const Key('newTask'),
            decoration: InputDecoration(
              hintText: '接下来要完成什么？',
              prefixIcon: const Icon(Icons.add_rounded, size: 18),
              suffixIcon: IconButton(
                tooltip: '添加任务',
                icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                onPressed: _add,
              ),
              isDense: true,
            ),
            style: QStyle.section,
            onSubmitted: (_) => _add(),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('taskSearch'),
            controller: _search,
            decoration: InputDecoration(
              hintText: '搜索任务',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
            style: QStyle.section,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('taskScroll'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          query.isNotEmpty ? '没有匹配的待办任务' : '还没有待办任务',
                          style: const TextStyle(color: Color(0xFF81978B)),
                        ),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      key: ValueKey(query.isEmpty ? 'all' : 'filtered'),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: pending.length,
                      onReorderItem: (oldIndex, newIndex) {
                        if (query.isNotEmpty) {
                          _message('请清除搜索后再排序');
                          return;
                        }
                        c.reorderTask(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final task = pending[index];
                        final active = task.id == c.selectedTaskId;
                        return Container(
                          key: ValueKey(task.id),
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          decoration: BoxDecoration(
                            color: active
                                ? QStyle.selected
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: active
                                ? const Border(
                                    left: BorderSide(
                                      color: QStyle.jade, width: 2))
                                : null,
                          ),
                          child: SizedBox(
                            height: 46,
                            child: Row(children: [
                            Checkbox(
                              value: task.done,
                              semanticLabel: '标记任务完成',
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_) => _toggleDone(task),
                            ),
                            Expanded(
                              child: CallbackShortcuts(
                                bindings: <ShortcutActivator, VoidCallback>{
                                  const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
                                      () => c.moveTask(task.id, -1),
                                  const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                                      () => c.moveTask(task.id, 1),
                                },
                                child: Focus(
                                  child: InkWell(
                                    onTap: () => _select(task),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 9),
                                      child: Text(
                                        task.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: active
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            fontSize: 13,
                                            color: QStyle.ink),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (active)
                              const Text('当前', style: TextStyle(
                                  fontSize: 11, color: QStyle.jade)),
                            if (task.pomodoros > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text('🍅 ${task.pomodoros}',
                                    style: const TextStyle(fontSize: 11)),
                              ),
                            if (query.isEmpty)
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_indicator,
                                      color: Color(0x88809A8B), size: 16),
                                ),
                              ),
                            PopupMenuButton<String>(
                              tooltip: '任务操作',
                              icon: const Icon(Icons.more_horiz, size: 18, color: QStyle.secondary),
                              constraints: const BoxConstraints(minWidth: 110, maxWidth: 148),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              onSelected: (action) {
                                if (action == 'rename') _rename(task);
                                if (action == 'delete') _delete(task);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(height: 38, value: 'rename', child: Text('重命名')),
                                PopupMenuItem(height: 38, value: 'delete', child: Text('删除')),
                              ],
                            ),
                            ]),
                          ),
                        );
                      },
                    ),
                  if (completed.isNotEmpty)
                    ExpansionTile(
                      // Searching must reveal matching completed tasks even if
                      // this section was collapsed before typing. A changing
                      // key remounts ExpansionTile so initial expansion applies.
                      key: ValueKey('completedSection-${query.isEmpty ? 'all' : 'search'}'),
                      initiallyExpanded: _completedExpanded || query.isNotEmpty,
                      onExpansionChanged: (expanded) {
                        setState(() => _completedExpanded = expanded);
                      },
                      title: Text('已完成（${completed.length}）'),
                      children: completed.map((task) => CheckboxListTile(
                        dense: true,
                        value: true,
                        title: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(decoration: TextDecoration.lineThrough),
                        ),
                        onChanged: (_) => _toggleDone(task),
                      )).toList(),
                    ),
                ],
              ),
            ),
          ),
          if (_temporaryMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(_temporaryMessage!, style: QStyle.detail, maxLines: 1),
            ),
          _undoBanner(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('drawerStartFocus'),
            onPressed: widget.onStart,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF27624D),
              backgroundColor: const Color(0xFFE8F1E9),
              side: BorderSide.none,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            icon: Icon(
              c.engine.isRunning ? Icons.arrow_back_rounded : Icons.play_arrow_rounded,
              size: 19,
            ),
            label: Text(c.engine.isRunning ? '返回专注' : '开始专注'),
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _rename(QingfanTask task) async {
    final result = await QDialogs.rename(context, current: task.title);
    if (result != null) widget.controller.renameTask(task.id, result);
  }

  Future<void> _delete(QingfanTask task) async {
    final c = widget.controller;
    if (task.id == c.selectedTaskId && c.engine.isRunning) {
      _message('请先暂停当前专注，再删除任务');
      return;
    }
    if (task.id == c.selectedTaskId &&
        c.engine.hasPartialFocus &&
        !await _confirmDiscard()) {
      return;
    }
    c.deleteTask(task.id, discardPartial: true);
  }
}

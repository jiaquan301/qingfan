import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/qingfan_controller.dart';
import '../domain/focus_engine.dart';

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

  @override
  void dispose() {
    _entry.dispose();
    _search.dispose();
    super.dispose();
  }

  void _add() {
    widget.controller.addTask(_entry.text);
    _entry.clear();
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃当前未完成的专注？'),
        content: const Text('切换或完成任务会重置本轮未完成的时间，已累计番茄不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('放弃本轮')),
        ],
      ),
    );
    return result == true;
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
    if (c.completeTask(task.id, discardPartial: true)) _undoSnackbar();
  }

  void _undoSnackbar() {
    final controller = widget.controller;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 7),
      content: Text(controller.undoMessage ?? '任务已更新'),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () => controller.undoTaskChange(),
      ),
    ));
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
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
      color: const Color(0xFFF9FCFA),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('任务清单',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700,
                    color: Color(0xFF153E31))),
            const SizedBox(width: 12),
            Text('${allPending.length} 项待办',
                style: const TextStyle(color: Color(0xFF81978B))),
            const Spacer(),
            IconButton(
              tooltip: '关闭任务清单',
              icon: const Icon(Icons.close_rounded),
              onPressed: widget.onClose,
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _entry,
            key: const Key('newTask'),
            decoration: InputDecoration(
              hintText: '接下来要完成什么？',
              prefixIcon: const Icon(Icons.add_task_rounded),
              suffixIcon: IconButton(
                tooltip: '添加任务',
                icon: const Icon(Icons.add_rounded),
                onPressed: _add,
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              isDense: true,
            ),
            onSubmitted: (_) => _add(),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('taskSearch'),
            controller: _search,
            decoration: InputDecoration(
              hintText: '搜索任务',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              isDense: true,
            ),
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
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xFFE8F3EB)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                            border: active
                                ? const Border(
                                    left: BorderSide(
                                      color: Color(0xFF337259), width: 3))
                                : null,
                          ),
                          child: Row(children: [
                            Checkbox(
                              value: task.done,
                              semanticLabel: '标记任务完成',
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
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Text(
                                        task.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: active
                                                ? FontWeight.w700
                                                : FontWeight.w400),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (active)
                              const Text('当前', style: TextStyle(
                                  fontSize: 11, color: Color(0xFF337259))),
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
                                      color: Color(0xFF81978B), size: 18),
                                ),
                              ),
                            PopupMenuButton<String>(
                              tooltip: '任务操作',
                              icon: const Icon(Icons.more_horiz),
                              onSelected: (action) {
                                if (action == 'rename') _rename(task);
                                if (action == 'delete') _delete(task);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'rename', child: Text('重命名')),
                                PopupMenuItem(value: 'delete', child: Text('删除')),
                              ],
                            ),
                          ]),
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
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('drawerStartFocus'),
            onPressed: widget.onStart,
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF337259),
                minimumSize: const Size.fromHeight(48)),
            child: Text(c.engine.isRunning ? '返回专注' : '开始专注'),
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _rename(QingfanTask task) async {
    final field = TextEditingController(text: task.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名任务'),
        content: TextField(controller: field, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    field.dispose();
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
    if (c.deleteTask(task.id, discardPartial: true)) _undoSnackbar();
  }
}

"""Qingfan 1.0 — focused, task-first GTK 3 desktop Pomodoro.

All business state is in core.Model and remains compatible with 1.x data.
The GUI uses only the Python standard library and Ubuntu's Gtk/PyGObject.
"""
from __future__ import annotations

import math
import sys
import traceback
from pathlib import Path

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango

from .core import Model

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets'


def style(widget, *classes):
    context = widget.get_style_context()
    for cls in classes:
        context.add_class(cls)
    return widget


def label(text='', css=None, xalign=0.5):
    item = Gtk.Label(label=text)
    item.set_xalign(xalign)
    if css:
        style(item, css)
    return item


def icon_button(name, tooltip, callback=None, css='icon-button'):
    item = Gtk.Button()
    item.set_relief(Gtk.ReliefStyle.NONE)
    item.set_image(Gtk.Image.new_from_icon_name(name, Gtk.IconSize.BUTTON))
    item.set_tooltip_text(tooltip)
    item.get_accessible().set_name(tooltip.split("  ")[0])
    style(item, css)
    if callback:
        item.connect('clicked', callback)
    return item


class Window(Gtk.ApplicationWindow):
    WIDTH = 332
    COMPACT_HEIGHT = 310
    TASK_ROW_HEIGHT = 42

    def __init__(self, application):
        # Register/show the window only after every widget has been built.
        super().__init__(title='青番')
        self._clock_source = None
        try:
            self._initialize()
            self.set_application(application)
            self.show_all()
            self.task_panel.hide()
        except Exception:
            self.destroy()
            raise

    def _initialize(self):
        style(self, 'qingfan-window')
        self.model = Model.load()
        self.compact = True
        self.pinned = True
        self._editing = None
        self._deleted_task = None
        self._undo_source = None
        self._settings_dialog = None
        self._last_clock_text = None
        self._last_phase = None
        self._last_task_title = None
        self._last_running = None

        self.set_default_size(self.WIDTH, self.COMPACT_HEIGHT)
        self.set_size_request(306, -1)
        self.set_resizable(False)
        self.set_gravity(Gdk.Gravity.NORTH_WEST)
        self.set_keep_above(True)
        self.connect('delete-event', self.on_close)
        self.connect('key-press-event', self.on_shortcut)
        # Labels and blank panel space cannot normally take keyboard focus;
        # background clicks must still finish an active inline editor.
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect('button-press-event', self.on_background_click)
        self._build()
        self._adjust_height()
        self.refresh_tasks()
        self.refresh_clock()
        self._clock_source = GLib.timeout_add(250, self.refresh_clock)
        self.connect('destroy', self.on_destroy)

    def _build(self):
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        style(header, 'qingfan-header')
        brand = Gtk.Box(spacing=8)
        brand.set_valign(Gtk.Align.CENTER)
        logo_path = ASSETS / 'qingfan.svg'
        if logo_path.is_file():
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(logo_path), 22, 22, True)
                brand.pack_start(Gtk.Image.new_from_pixbuf(pixbuf), False, False, 0)
            except GLib.Error:
                pass
        brand.pack_start(label('青番', 'brand-name', xalign=0), False, False, 0)
        header.set_custom_title(brand)

        self.list_button = icon_button('view-list-symbolic', '展开任务清单  Ctrl+L', self.toggle_mode)
        header.pack_end(self.list_button)
        self.pin_button = icon_button('view-pin-symbolic', '取消置顶', self.toggle_pin)
        style(self.pin_button, 'selected')
        header.pack_end(self.pin_button)
        header.pack_start(icon_button('preferences-system-symbolic', '计时设置', self.open_settings))
        self.set_titlebar(header)

        base = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(base)
        hero = style(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0), 'hero')
        hero.set_margin_start(22)
        hero.set_margin_end(22)
        hero.set_margin_top(19)
        hero.set_margin_bottom(18)
        base.pack_start(hero, False, False, 0)

        self.phase_label = label('专注时间 · 第 1 / 4 轮', 'eyebrow')
        hero.pack_start(self.phase_label, False, False, 0)

        self.clock = label('25:00', 'time')
        self.clock.set_margin_top(1)
        hero.pack_start(self.clock, False, False, 0)

        self.progress = style(Gtk.ProgressBar(), 'progress')
        self.progress.set_fraction(0)
        self.progress.set_margin_start(40)
        self.progress.set_margin_end(40)
        self.progress.set_margin_top(1)
        self.progress.set_margin_bottom(13)
        hero.pack_start(self.progress, False, False, 0)

        self.task_title = label('选择任务，开始专注', 'task-title')
        self.task_title.set_ellipsize(Pango.EllipsizeMode.END)
        self.task_title.set_max_width_chars(32)
        self.task_title.set_tooltip_text('点击任务清单选择当前任务')
        hero.pack_start(self.task_title, False, False, 0)

        self.rounds = Gtk.Box(spacing=5)
        self.rounds.set_halign(Gtk.Align.CENTER)
        self.rounds.set_margin_top(11)
        self.dot_labels = []
        for _ in range(4):
            item = label('●', 'round-dot')
            self.dot_labels.append(item)
            self.rounds.pack_start(item, False, False, 0)
        hero.pack_start(self.rounds, False, False, 0)

        buttons = Gtk.Box(spacing=10)
        buttons.set_halign(Gtk.Align.CENTER)
        buttons.set_margin_top(15)
        hero.pack_start(buttons, False, False, 0)
        self.go_btn = Gtk.Button(label='开始专注')
        style(self.go_btn, 'primary')
        self.go_btn.set_tooltip_text('开始或暂停计时  空格')
        self.go_btn.connect('clicked', self.toggle_timer)
        buttons.pack_start(self.go_btn, False, False, 0)
        self.reset_button = icon_button('view-refresh-symbolic', '重置当前计时', self.confirm_reset, 'secondary')
        buttons.pack_start(self.reset_button, False, False, 0)

        self.footer_label = label('已完成 0 个番茄', 'support-text')
        self.footer_label.set_margin_top(12)
        hero.pack_start(self.footer_label, False, False, 0)

        # Task area grows to fit its content until six rows; no oversized blank panel.
        self.task_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        base.pack_start(self.task_panel, False, False, 0)
        separator = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        self.task_panel.pack_start(separator, False, False, 0)

        inside = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=11)
        inside.set_margin_start(18)
        inside.set_margin_end(18)
        inside.set_margin_top(13)
        inside.set_margin_bottom(15)
        self.task_panel.pack_start(inside, False, False, 0)

        section = Gtk.Box(spacing=8)
        inside.pack_start(section, False, False, 0)
        section.pack_start(label('任务清单', 'section-title', xalign=0), False, False, 0)
        self.count_label = label('0 项', 'task-count')
        section.pack_start(self.count_label, False, False, 0)
        section.pack_start(Gtk.Box(), True, True, 0)

        input_row = Gtk.Box(spacing=6)
        inside.pack_start(input_row, False, False, 0)
        self.entry = Gtk.Entry()
        self.entry.set_placeholder_text('接下来要完成什么？')
        self.entry.set_max_length(120)
        style(self.entry, 'new-task')
        self.entry.connect('activate', self.add_task)
        input_row.pack_start(self.entry, True, True, 0)
        add_button = icon_button('list-add-symbolic', '添加任务  Enter', self.add_task)
        input_row.pack_start(add_button, False, False, 0)

        self.scroller = style(Gtk.ScrolledWindow(), 'list-scroller')
        self.scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.scroller.set_shadow_type(Gtk.ShadowType.NONE)
        inside.pack_start(self.scroller, False, False, 0)
        self.rows_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.scroller.add(self.rows_box)

        self.undo_bar = Gtk.Box(spacing=8)
        self.undo_bar.set_no_show_all(True)
        self.undo_label = label('任务已删除', 'support-text', xalign=0)
        self.undo_bar.pack_start(self.undo_label, True, True, 0)
        undo = Gtk.Button(label='撤销')
        undo.connect('clicked', self.undo_delete)
        self.undo_bar.pack_end(undo, False, False, 0)
        inside.pack_start(self.undo_bar, False, False, 0)

    def _adjust_height(self):
        if self.compact:
            height = self.COMPACT_HEIGHT
        else:
            visible = min(4, len(self.model.tasks))
            # Add task panel header/input/spacing + task rows, cap content size.
            height = self.COMPACT_HEIGHT + 121 + (visible * self.TASK_ROW_HEIGHT if visible else 49)
            if self.undo_bar.get_visible():
                height += 49
        self.resize(self.WIDTH, height)

    def _set_mode(self, compact):
        self._finish_edit()
        self.compact = compact
        if compact:
            self.task_panel.hide()
            self.list_button.set_image(Gtk.Image.new_from_icon_name('view-list-symbolic', Gtk.IconSize.BUTTON))
            self.list_button.set_tooltip_text('展开任务清单  Ctrl+L')
            self.list_button.get_style_context().remove_class('selected')
        else:
            self.task_panel.show_all()
            self.list_button.set_image(Gtk.Image.new_from_icon_name('view-restore-symbolic', Gtk.IconSize.BUTTON))
            self.list_button.set_tooltip_text('收起任务清单  Ctrl+L')
            style(self.list_button, 'selected')
        self._adjust_height()

    def toggle_mode(self, *_):
        self._set_mode(not self.compact)

    def toggle_pin(self, *_):
        self.pinned = not self.pinned
        self.set_keep_above(self.pinned)
        context = self.pin_button.get_style_context()
        if self.pinned:
            context.add_class('selected')
        else:
            context.remove_class('selected')
        self.pin_button.set_tooltip_text('取消置顶' if self.pinned else '保持窗口置顶')

    def _save(self):
        try:
            self.model.save()
            return True
        except OSError as error:
            dialog = Gtk.MessageDialog(transient_for=self, flags=Gtk.DialogFlags.MODAL,
                                       message_type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.CLOSE,
                                       text='无法保存任务')
            dialog.format_secondary_text(f'请检查磁盘空间和数据目录权限。当前修改仍保留在窗口中。\n{error}')
            dialog.run()
            dialog.destroy()
            return False

    def toggle_timer(self, *_):
        if self.model.phase == 'focus' and not self.model.running() and self.model.current_id is None:
            if self.compact:
                self._set_mode(False)
            self.entry.grab_focus()
            return
        was_running = self.model.running()
        self.model.start_pause()
        if not was_running and self.model.running() and self.model.phase == 'focus':
            self._set_mode(True)  # Timer and one task are the entire focus UI.
        self._save()
        self.refresh_clock()

    def confirm_reset(self, *_):
        if self.model.running() or self.model.seconds() < self.model.phase_duration:
            dialog = Gtk.MessageDialog(
                transient_for=self, flags=Gtk.DialogFlags.MODAL,
                message_type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.NONE,
                text='重置当前计时？')
            dialog.format_secondary_text('正在进行的专注或休息将重新开始计时。')
            dialog.add_button('取消', Gtk.ResponseType.CANCEL)
            dialog.add_button('重置', Gtk.ResponseType.OK)
            answer = dialog.run()
            dialog.destroy()
            if answer != Gtk.ResponseType.OK:
                return
        self.model.reset()
        self._save()
        self.refresh_clock()

    def refresh_clock(self):
        transition = self.model.tick()
        if transition:
            self._save()
            if transition == 'focus':
                self.refresh_tasks()
                self.get_application().notify_user('专注完成', '完成一个番茄钟。休息一下吧。')
            else:
                self.get_application().notify_user('休息结束', '准备好后，开始下一轮专注。')
        phase = self.model.phase
        if phase != self._last_phase:
            if phase == 'focus':
                self.get_style_context().remove_class('break-mode')
            else:
                self.get_style_context().add_class('break-mode')
            self._last_phase = phase
        count = self.model.completed_rounds
        position = count % 4
        if phase == 'focus':
            self.phase_label.set_text(f'专注时间 · 第 {position + 1} / 4 轮')
            fill = position
        else:
            self.phase_label.set_text('短休息 · 放松一下' if phase == 'short' else '长休息 · 好好充电')
            fill = position or 4
        for index, dot in enumerate(self.dot_labels):
            context = dot.get_style_context()
            if index < fill:
                context.add_class('filled')
            else:
                context.remove_class('filled')

        remain = math.ceil(self.model.seconds())
        text = f'{remain // 60:02d}:{remain % 60:02d}'
        if text != self._last_clock_text:
            self.clock.set_text(text)
            self._last_clock_text = text
        length = max(1, self.model.phase_duration)
        self.progress.set_fraction(max(0.0, min(1.0, 1.0 - self.model.seconds() / length)))
        title = self.model.current_title()
        if title != self._last_task_title:
            self.task_title.set_text(title)
            self.task_title.set_tooltip_text(title)
            self._last_task_title = title
        text_count = f'已完成 {count} 个番茄'
        if self.footer_label.get_text() != text_count:
            self.footer_label.set_text(text_count)
        if self.model.running():
            action = '暂停'
        elif phase != 'focus':
            action = '开始休息' if remain == length else '继续休息'
        elif self.model.current_id is None:
            action = '选择任务'
        else:
            action = '开始专注' if remain == length else '继续专注'
        if action != self._last_running:
            self.go_btn.set_label(action)
            self._last_running = action
        return True

    def add_task(self, *_):
        title = self.entry.get_text().strip()
        if not title:
            self.entry.grab_focus()
            return
        self.model.add(title)
        if not self.model.current_id:
            self.model.current_id = self.model.tasks[-1]['id']
        self.entry.set_text('')
        self._save()
        self.refresh_tasks()
        self.refresh_clock()
        self.entry.grab_focus()

    def refresh_tasks(self):
        self._finish_edit()
        for child in self.rows_box.get_children():
            child.destroy()
        self.count_label.set_text(f'{len(self.model.tasks)} 项任务')
        if not self.model.tasks:
            empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
            empty.set_margin_top(12)
            empty.set_margin_bottom(12)
            empty.pack_start(label('把第一件要做的事写在上面', 'empty-title'), False, False, 0)
            empty.pack_start(label('一次只专注一件事', 'empty-subtitle'), False, False, 0)
            self.rows_box.pack_start(empty, False, False, 0)
        for item in self.model.tasks:
            self.rows_box.pack_start(self._task_widget(item), False, False, 0)
        count = min(4, len(self.model.tasks))
        self.scroller.set_size_request(-1, count * self.TASK_ROW_HEIGHT if count else 49)
        self.rows_box.show_all()
        self._adjust_height()

    def _task_widget(self, task):
        tid = task['id']
        active = tid == self.model.current_id
        row = style(Gtk.Box(spacing=4), 'task-row')
        if active:
            style(row, 'is-current')

        # Radio semantics in a compact checkbox: exactly one selected task;
        # checked does NOT mean deleted or completed.
        check = Gtk.CheckButton()
        check.set_valign(Gtk.Align.CENTER)
        check.set_active(active)
        check.set_tooltip_text('取消选中任务' if active else '选择此任务专注')
        check.get_accessible().set_name('取消选中任务' if active else '选择此任务专注')
        # Switching during an active interval silently discards work, so
        # selection remains locked until the user pauses the timer.
        check.set_sensitive(not (self.model.phase == 'focus' and self.model.running()))
        check.connect('toggled', lambda widget: self.select_task(tid if widget.get_active() else None))
        row.pack_start(check, False, False, 0)

        targets = [Gtk.TargetEntry.new('UTF8_STRING', Gtk.TargetFlags.SAME_APP, 0)]
        handle = icon_button('list-drag-handle-symbolic', '拖动排序；Alt+↑ / Alt+↓ 调整顺序')
        style(handle, 'drag-handle')
        handle._qingfan_task_id = tid
        handle.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, targets, Gdk.DragAction.MOVE)
        handle.connect('drag-data-get', self._drag_task, tid)
        handle.connect('key-press-event', self._reorder_key, tid)
        row.pack_start(handle, False, False, 0)
        row.drag_dest_set(Gtk.DestDefaults.ALL, targets, Gdk.DragAction.MOVE)
        row.connect('drag-data-received', self._drop_task, tid)

        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.NONE)
        stack.set_hexpand(True)
        pick = style(Gtk.Button(), 'task-pick')
        pick.set_relief(Gtk.ReliefStyle.NONE)
        pick.set_hexpand(True)
        pick.set_tooltip_text(task['title'] + '\n点击编辑任务名称')
        text = label(task['title'], xalign=0)
        text.set_hexpand(True)
        text.set_ellipsize(Pango.EllipsizeMode.END)
        text.set_max_width_chars(16)
        pick.add(text)
        field = Gtk.Entry(text=task['title'])
        field.set_width_chars(1)
        field.set_max_length(120)
        field.get_accessible().set_name('任务名称')
        field.set_tooltip_text('回车或失焦保存，Esc 取消')
        stack.add_named(pick, 'title')
        stack.add_named(field, 'edit')
        pick.connect('clicked', lambda *_: self._begin_edit(tid, field, stack, text))
        field.connect('activate', lambda *_: self._finish_edit())
        field.connect('focus-out-event', lambda *_: self._finish_edit())
        field.connect('key-press-event', self._edit_key)
        row.pack_start(stack, True, True, 0)

        count = label(f"{task.get('pomodoros', 0)} 次", 'task-pomodoros')
        count.set_tooltip_text('这项任务累计完成的专注轮数')
        row.pack_start(count, False, False, 0)
        row.pack_end(icon_button('edit-delete-symbolic', '删除任务，可撤销',
                                lambda *_: self.remove_task(tid)), False, False, 0)
        # Gtk.Button owns its own GDK event window; accept drop on its surface.
        pick.drag_dest_set(Gtk.DestDefaults.ALL, targets, Gdk.DragAction.MOVE)
        pick.connect('drag-data-received', self._drop_task, tid)
        return row

    def _begin_edit(self, tid, field, stack, text):
        self._finish_edit()
        self._editing = (tid, field, stack, text)
        stack.set_visible_child_name('edit')
        field.grab_focus()
        field.select_region(0, -1)

    def _finish_edit(self, cancel=False, save=True):
        if self._editing is None:
            return False
        tid, field, stack, text = self._editing
        self._editing = None
        if not cancel:
            self.model.rename(tid, field.get_text())
        task = next((t for t in self.model.tasks if t['id'] == tid), None)
        if task:
            text.set_text(task['title'])
            field.set_text(task['title'])
            text.get_parent().set_tooltip_text(task['title'] + '\n点击编辑任务名称')
        stack.set_visible_child_name('title')
        if not cancel and save:
            self._save()
            self.refresh_clock()
        return False

    def _edit_key(self, _field, event):
        if event.keyval == Gdk.KEY_Escape:
            self._finish_edit(cancel=True)
            return True
        return False

    def _reorder_key(self, _widget, event, tid):
        if event.state & Gdk.ModifierType.MOD1_MASK and event.keyval in (Gdk.KEY_Up, Gdk.KEY_Down):
            self.model.move(tid, -1 if event.keyval == Gdk.KEY_Up else 1)
            self._save()
            self.refresh_tasks()
            for row in self.rows_box.get_children():
                for child in row.get_children():
                    if getattr(child, '_qingfan_task_id', None) == tid:
                        child.grab_focus()
            return True
        return False

    def _drag_task(self, _handle, _context, data, _info, _time, task_id):
        data.set_text(task_id, -1)

    def _drop_task(self, widget, context, _x, y, data, _info, timestamp, target_id):
        source = Gtk.drag_get_source_widget(context)
        source_id = getattr(source, '_qingfan_task_id', None)
        if source_id is None or data.get_text() != source_id:
            Gtk.drag_finish(context, False, False, timestamp)
            return
        changed = self.model.reorder(source_id, target_id,
                                     after=y >= widget.get_allocated_height() / 2)
        Gtk.drag_finish(context, True, False, timestamp)
        if changed:
            self._save()
            # GTK drag must finish before destroying its source widget.
            GLib.idle_add(self._refresh_after_drop)

    def _refresh_after_drop(self):
        self.refresh_tasks()
        return False

    def select_task(self, tid):
        if self.model.phase == 'focus' and self.model.running():
            return  # Selection controls are also insensitive while running.
        if self.model.select(tid):
            self._finish_edit()
            self._save()
            self.refresh_tasks()
            self.refresh_clock()

    def remove_task(self, tid):
        self._finish_edit()
        index = next((i for i, t in enumerate(self.model.tasks) if t['id'] == tid), None)
        if index is None:
            return
        self._deleted_task = (self.model.tasks[index].copy(), index, self.model.current_id == tid)
        if tid == self.model.current_id and self.model.running():
            self.model.start_pause()
        self.model.delete(tid)
        self._save()
        self.refresh_tasks()
        self.refresh_clock()
        self.undo_bar.set_no_show_all(False)
        self.undo_bar.show_all()
        self._adjust_height()
        if self._undo_source is not None:
            GLib.source_remove(self._undo_source)
        self._undo_source = GLib.timeout_add_seconds(7, self._dismiss_undo)

    def _dismiss_undo(self):
        self._undo_source = None
        self._deleted_task = None
        self.undo_bar.hide()
        self.undo_bar.set_no_show_all(True)
        self._adjust_height()
        return False

    def undo_delete(self, *_):
        if self._deleted_task is None:
            return
        task, index, was_current = self._deleted_task
        self._deleted_task = None
        if self._undo_source is not None:
            GLib.source_remove(self._undo_source)
            self._undo_source = None
        self.model.tasks.insert(min(index, len(self.model.tasks)), task)
        if was_current and self.model.current_id is None and not task.get('done'):
            self.model.current_id = task['id']
        self.undo_bar.hide()
        self.undo_bar.set_no_show_all(True)
        self._adjust_height()
        self._save()
        self.refresh_tasks()
        self.refresh_clock()

    def open_settings(self, *_):
        self._finish_edit()
        if self._settings_dialog is not None:
            self._settings_dialog.present()
            return
        dialog = Gtk.Dialog(title='番茄钟设置', transient_for=self, flags=Gtk.DialogFlags.MODAL)
        self._settings_dialog = dialog
        dialog.add_button('取消', Gtk.ResponseType.CANCEL)
        dialog.add_button('保存', Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        grid = Gtk.Grid(column_spacing=22, row_spacing=14)
        grid.set_margin_top(20)
        grid.set_margin_bottom(17)
        grid.set_margin_start(22)
        grid.set_margin_end(22)
        fields = {}
        for index, (key, name) in enumerate((('focus', '专注时间'), ('short', '短休息'), ('long', '长休息'))):
            item = label(name, xalign=0)
            grid.attach(item, 0, index, 1, 1)
            spin = Gtk.SpinButton.new_with_range(1, 180, 1)
            spin.set_value(self.model.settings[key])
            fields[key] = spin
            grid.attach(spin, 1, index, 1, 1)
            grid.attach(label('分钟', 'support-text'), 2, index, 1, 1)
        note = label('正在进行的计时不受影响；下次重置使用新时长。', 'support-text', xalign=0)
        note.set_line_wrap(True)
        grid.attach(note, 0, 3, 3, 1)
        dialog.get_content_area().add(grid)
        dialog.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            for item in fields.values():
                item.update()
            self.model.update_settings({key: item.get_value_as_int() for key, item in fields.items()})
            self._save()
            self.refresh_clock()
        dialog.destroy()
        self._settings_dialog = None

    def on_background_click(self, _widget, event):
        source = Gtk.get_event_widget(event)
        while source is not None:
            if isinstance(source, (Gtk.Entry, Gtk.SpinButton)):
                return False
            source = source.get_parent()
        if self._editing is not None:
            self._finish_edit()
            self.set_focus(None)
        return False  # Preserve the original click on its actual control.

    def on_shortcut(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape and self._editing is not None:
            self._finish_edit(cancel=True)
            return True
        ctrl = bool(event.state & Gdk.ModifierType.CONTROL_MASK)
        if ctrl and event.keyval in (Gdk.KEY_n, Gdk.KEY_N):
            if self.compact:
                self._set_mode(False)
            self.entry.grab_focus()
            return True
        if ctrl and event.keyval in (Gdk.KEY_l, Gdk.KEY_L):
            self.toggle_mode()
            return True
        if event.keyval == Gdk.KEY_Escape and not self.compact:
            self._set_mode(True)
            return True
        focus = self.get_focus()
        interactive = isinstance(focus, (Gtk.Entry, Gtk.SpinButton, Gtk.Button, Gtk.CheckButton))
        if event.keyval == Gdk.KEY_space and not ctrl and not interactive:
            self.toggle_timer()
            return True
        return False

    def on_close(self, *_):
        self._finish_edit(save=False)
        if not self._save():
            return True
        return False

    def on_destroy(self, *_):
        if self._undo_source is not None:
            GLib.source_remove(self._undo_source)
            self._undo_source = None
        if self._clock_source is not None:
            GLib.source_remove(self._clock_source)
            self._clock_source = None



class Application(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='app.qingfan.Pomodoro', flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.startup_failed = False

    def do_startup(self):
        Gtk.Application.do_startup(self)
        provider = Gtk.CssProvider()
        provider.load_from_path(str(ASSETS / 'style.css'))
        screen = Gdk.Screen.get_default()
        if screen:
            Gtk.StyleContext.add_provider_for_screen(screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        icon = ASSETS / 'qingfan.svg'
        if icon.is_file():
            try:
                Gtk.Window.set_default_icon_from_file(str(icon))
            except GLib.Error:
                pass

    def do_activate(self):
        window = self.get_active_window()
        if window is None:
            try:
                window = Window(self)
            except Exception as error:
                self.startup_failed = True
                traceback.print_exc()
                dialog = Gtk.MessageDialog(message_type=Gtk.MessageType.ERROR,
                                           buttons=Gtk.ButtonsType.CLOSE,
                                           text='青番启动失败')
                dialog.format_secondary_text(f'界面未能完成初始化，请从终端运行以查看完整错误。\n{error}')
                dialog.run()
                dialog.destroy()
                self.quit()
                return
        window.present()

    def notify_user(self, title, body):
        notification = Gio.Notification.new(title)
        notification.set_body(body)
        self.send_notification(None, notification)


def main():
    application = Application()
    result = application.run(sys.argv)
    return 1 if application.startup_failed else result

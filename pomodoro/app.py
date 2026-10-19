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
from .floating import FocusOrb

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
    TASK_ROW_HEIGHT = 48
    TASK_WINDOW_WIDTH = 400
    TASK_WINDOW_MIN_WIDTH = 360
    TASK_WINDOW_MIN_HEIGHT = 360
    TASK_WINDOW_MAX_HEIGHT = 620

    def __init__(self, application):
        # Register/show the window only after every widget has been built.
        super().__init__(title='青番')
        self._clock_source = None
        try:
            self._initialize()
            self.set_application(application)
            self.show_all()
            self.task_panel.hide()
            self.orb_window = FocusOrb(application, self)
            self._set_mode(True)
        except Exception:
            self.destroy()
            raise

    def _initialize(self):
        style(self, 'qingfan-window')
        self.model = Model.load()
        self.compact = True
        self.pinned = self.model.display["pinned"]
        self._editing = None
        self._refreshing_tasks = False
        self._task_row_by_id = {}
        self._completed_expanded = False
        self._manager_size = None
        self._search_visible = False
        self._undo_state = None
        self._deleted_task = None
        self._undo_source = None
        self._status_source = None
        self._settings_dialog = None
        self._last_clock_text = None
        self._last_phase = None
        self._last_task_title = None
        self._last_running = None

        self.set_default_size(self.WIDTH, self.COMPACT_HEIGHT)
        self.set_size_request(306, -1)
        self.set_resizable(False)
        self.set_gravity(Gdk.Gravity.NORTH_WEST)
        self.set_keep_above(self.pinned)
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
        if self.pinned:
            style(self.pin_button, 'selected')
        header.pack_end(self.pin_button)
        header.pack_start(icon_button('preferences-system-symbolic', '计时设置', self.open_settings))
        self.set_titlebar(header)

        base = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(base)
        hero = style(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0), 'hero')
        self.hero = hero
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

        # Task management is a separate, useful workspace. Only the list scrolls;
        # the title, add field, undo feedback and primary action remain visible.
        self.task_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.task_panel.set_vexpand(True)
        base.pack_start(self.task_panel, True, True, 0)
        separator = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        self.task_panel.pack_start(separator, False, False, 0)

        inside = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        inside.set_margin_start(18)
        inside.set_margin_end(18)
        inside.set_margin_top(14)
        inside.set_margin_bottom(14)
        inside.set_vexpand(True)
        self.task_panel.pack_start(inside, True, True, 0)

        section = Gtk.Box(spacing=8)
        inside.pack_start(section, False, False, 0)
        section.pack_start(label('任务清单', 'section-title', xalign=0), False, False, 0)
        self.count_label = label('0 项待办 · 0 项已完成', 'task-count')
        section.pack_start(self.count_label, False, False, 0)
        section.pack_start(Gtk.Box(), True, True, 0)
        self.search_button = icon_button('system-search-symbolic', '搜索任务  Ctrl+F', self.toggle_search)
        section.pack_end(self.search_button, False, False, 0)

        self.search_entry = Gtk.Entry()
        self.search_entry.set_placeholder_text('搜索任务名称')
        self.search_entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, 'edit-clear-symbolic')
        self.search_entry.set_icon_activatable(Gtk.EntryIconPosition.SECONDARY, True)
        self.search_entry.set_tooltip_text('按任务名称搜索；搜索不会改变任务顺序')
        self.search_entry.set_no_show_all(True)
        self.search_entry.connect('changed', self.on_search_changed)
        self.search_entry.connect('icon-release', self._clear_search_icon)
        inside.pack_start(self.search_entry, False, False, 0)

        input_row = Gtk.Box(spacing=8)
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
        self.scroller.set_hexpand(True)
        self.scroller.set_vexpand(True)
        self.scroller.set_size_request(-1, 140)
        inside.pack_start(self.scroller, True, True, 0)

        self.list_content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.scroller.add(self.list_content)
        self.pending_empty = label('', 'empty-title', xalign=0)
        self.pending_empty.set_line_wrap(True)
        self.pending_empty.set_margin_top(10)
        self.pending_empty.set_margin_bottom(10)
        self.pending_empty.set_no_show_all(True)
        self.list_content.pack_start(self.pending_empty, False, False, 0)

        self.rows_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        self.list_content.pack_start(self.rows_box, False, False, 0)

        self.completed_toggle = Gtk.Button()
        self.completed_toggle.set_relief(Gtk.ReliefStyle.NONE)
        self.completed_toggle.set_no_show_all(True)
        style(self.completed_toggle, 'completed-toggle')
        completed_header = Gtk.Box(spacing=8)
        self.completed_toggle_icon = Gtk.Image.new_from_icon_name('pan-end-symbolic', Gtk.IconSize.MENU)
        completed_header.pack_start(self.completed_toggle_icon, False, False, 0)
        self.completed_toggle_label = label('已完成（0）', 'completed-label', xalign=0)
        completed_header.pack_start(self.completed_toggle_label, False, False, 0)
        completed_header.pack_start(Gtk.Box(), True, True, 0)
        self.completed_toggle.add(completed_header)
        self.completed_toggle.connect('clicked', self.toggle_completed)
        self.list_content.pack_start(self.completed_toggle, False, False, 0)

        self.completed_rows_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        self.completed_rows_box.set_no_show_all(True)
        self.list_content.pack_start(self.completed_rows_box, False, False, 0)

        self.status_label = label('', 'task-status', xalign=0)
        self.status_label.set_line_wrap(True)
        self.status_label.set_no_show_all(True)
        inside.pack_start(self.status_label, False, False, 0)

        self.undo_bar = Gtk.Box(spacing=8)
        self.undo_bar.set_no_show_all(True)
        self.undo_label = label('任务已删除', 'support-text', xalign=0)
        self.undo_bar.pack_start(self.undo_label, True, True, 0)
        undo = Gtk.Button(label='撤销')
        undo.connect('clicked', self.undo_delete)
        self.undo_bar.pack_end(undo, False, False, 0)
        inside.pack_start(self.undo_bar, False, False, 0)

        footer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.footer_hint = label('Ctrl+F 搜索 · Esc 收起清单', 'footer-hint', xalign=0)
        footer.pack_start(self.footer_hint, False, False, 0)
        self.task_primary_button = Gtk.Button(label='开始专注')
        style(self.task_primary_button, 'primary', 'task-primary')
        self.task_primary_button.set_hexpand(True)
        self.task_primary_button.connect('clicked', self.task_primary_action)
        footer.pack_start(self.task_primary_button, False, False, 0)
        inside.pack_start(footer, False, False, 0)

    def _manager_default_height(self):
        screen = Gdk.Screen.get_default()
        if screen is None:
            return 560
        try:
            monitor = screen.get_primary_monitor()
            area = screen.get_monitor_workarea(monitor) if monitor >= 0 else None
            available = area.height if area is not None else screen.get_height()
        except (AttributeError, TypeError, RuntimeError):
            available = screen.get_height()
        return max(self.TASK_WINDOW_MIN_HEIGHT,
                   min(560, self.TASK_WINDOW_MAX_HEIGHT, int(available * 0.72)))

    def _adjust_height(self):
        if self.compact:
            self.set_resizable(False)
            self.set_size_request(306, -1)
            self.set_default_size(self.WIDTH, self.COMPACT_HEIGHT)
            self.resize(self.WIDTH, self.COMPACT_HEIGHT)
            return
        self.set_resizable(True)
        self.set_size_request(self.TASK_WINDOW_MIN_WIDTH, self.TASK_WINDOW_MIN_HEIGHT)
        if self._manager_size is None:
            self._manager_size = (self.TASK_WINDOW_WIDTH, self._manager_default_height())
        width, height = self._manager_size
        self.set_default_size(width, height)
        self.resize(width, height)

    def _set_mode(self, compact):
        self._finish_edit()
        if compact and not self.compact and self.get_visible():
            width, height = self.get_size()
            if width >= self.TASK_WINDOW_MIN_WIDTH and height >= self.TASK_WINDOW_MIN_HEIGHT:
                self._manager_size = (width, height)
        self.compact = compact
        if compact:
            self.task_panel.hide()
            self.hero.show()
            self.set_resizable(False)
            if hasattr(self, 'orb_window'):
                self.orb_window.set_keep_above(self.pinned)
                self.orb_window.present()
                self.hide()
            self._adjust_height()
            self.list_button.set_image(Gtk.Image.new_from_icon_name('view-list-symbolic', Gtk.IconSize.BUTTON))
            self.list_button.set_tooltip_text('展开任务清单  Ctrl+L')
            self.list_button.get_style_context().remove_class('selected')
        else:
            if hasattr(self, 'orb_window'):
                self.orb_window.hide()
            self.hero.hide()
            self._adjust_height()
            self.show()
            self.task_panel.show_all()
            self.refresh_tasks()
            self.list_button.set_image(Gtk.Image.new_from_icon_name('view-restore-symbolic', Gtk.IconSize.BUTTON))
            self.list_button.set_tooltip_text('收起任务清单  Ctrl+L')
            style(self.list_button, 'selected')
            self._update_task_primary_action()

    def toggle_mode(self, *_):
        self._set_mode(not self.compact)

    def toggle_pin(self, *_):
        self.pinned = not self.pinned
        self.model.display['pinned'] = self.pinned
        self.set_keep_above(self.pinned)
        if hasattr(self, 'orb_window'):
            self.orb_window.set_keep_above(self.pinned)
        self._save()
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
        if not was_running and self.model.running():
            self._set_mode(True)  # Return to the floating timer for focus or rest.
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
        if hasattr(self, 'task_primary_button'):
            self._update_task_primary_action()
        if hasattr(self, 'orb_window'):
            self.orb_window.update(action)
        return True

    def add_task(self, *_):
        title = self.entry.get_text().strip()
        if not title:
            self.entry.grab_focus()
            return
        if self.search_entry.get_text():
            self.search_entry.set_text('')
        previous_ids = {task['id'] for task in self.model.pending_tasks}
        self.model.add(title)
        if self.model.current_id is None:
            new_task = next((task for task in self.model.pending_tasks
                             if task['id'] not in previous_ids), None)
            if new_task is not None:
                self.model.current_id = new_task['id']
        self.entry.set_text('')
        self._save()
        self.refresh_tasks()
        self.refresh_clock()
        self.entry.grab_focus()

    def _query(self):
        return self.search_entry.get_text().strip().casefold()

    def toggle_search(self, *_):
        if self.search_entry.get_visible():
            self.search_entry.set_text('')
            self.search_entry.hide()
            self._search_visible = False
            self.search_button.set_tooltip_text('搜索任务  Ctrl+F')
            self.refresh_tasks()
            self.entry.grab_focus()
            return
        self.show_search()

    def show_search(self):
        if self.compact:
            self._set_mode(False)
        self._search_visible = True
        self.search_entry.show()
        self.search_button.set_tooltip_text('关闭搜索')
        self.search_entry.grab_focus()
        self.refresh_tasks()

    def on_search_changed(self, *_):
        self.refresh_tasks()

    def _clear_search_icon(self, entry, icon_pos, *_):
        if icon_pos == Gtk.EntryIconPosition.SECONDARY:
            entry.set_text('')
            entry.grab_focus()

    def toggle_completed(self, *_):
        self._completed_expanded = not self._completed_expanded
        self.refresh_tasks()

    def _sync_completed_visibility(self, matching_completed_count):
        query = self._query()
        if matching_completed_count == 0:
            self.completed_toggle.hide()
            self.completed_rows_box.hide()
            return
        self.completed_toggle.show()
        expanded = self._completed_expanded or bool(query)
        self.completed_toggle_icon.set_from_icon_name(
            'pan-down-symbolic' if expanded else 'pan-end-symbolic', Gtk.IconSize.MENU)
        if expanded:
            self.completed_rows_box.set_no_show_all(False)
            self.completed_rows_box.show_all()
            self.completed_rows_box.set_no_show_all(True)
        else:
            self.completed_rows_box.hide()

    def refresh_tasks(self):
        if self._refreshing_tasks:
            return
        self._refreshing_tasks = True
        try:
            self._finish_edit()
            for child in self.rows_box.get_children():
                child.destroy()
            for child in self.completed_rows_box.get_children():
                child.destroy()
            self._task_row_by_id = {}

            pending = self.model.pending_tasks
            completed = self.model.completed_tasks
            query = self._query()
            matching_pending = [task for task in pending if query in task['title'].casefold()]
            matching_completed = [task for task in completed if query in task['title'].casefold()]
            self.count_label.set_text(f'{len(pending)} 项待办 · {len(completed)} 项已完成')
            self.completed_toggle_label.set_text(f'已完成（{len(completed)}）')

            if not matching_pending:
                if query and not matching_completed:
                    empty_text = '没有找到匹配的任务'
                elif query:
                    empty_text = '没有匹配的待办任务'
                elif not pending and completed:
                    empty_text = '所有任务已完成'
                elif not pending:
                    empty_text = '还没有任务，添加第一件要做的事'
                else:
                    empty_text = '没有待办任务'
                self.pending_empty.set_text(empty_text)
                self.pending_empty.show()
            else:
                self.pending_empty.hide()

            for task in matching_pending:
                row = self._task_widget(task, completed=False)
                self.rows_box.pack_start(row, False, False, 0)
                self._task_row_by_id[task['id']] = row
            self.rows_box.show_all()

            for task in matching_completed:
                row = self._task_widget(task, completed=True)
                self.completed_rows_box.pack_start(row, False, False, 0)
                self._task_row_by_id[task['id']] = row
            self.completed_rows_box.set_no_show_all(False)
            self.completed_rows_box.show_all()
            self.completed_rows_box.set_no_show_all(True)
            self._sync_completed_visibility(len(matching_completed))
            self._update_task_primary_action()
        finally:
            self._refreshing_tasks = False
        if not self.compact:
            GLib.idle_add(self._scroll_current_into_view)

    def _scroll_current_into_view(self):
        row = self._task_row_by_id.get(self.model.current_id)
        if row is None or row.get_parent() != self.rows_box:
            return False
        adjustment = self.scroller.get_vadjustment()
        allocation = row.get_allocation()
        value = adjustment.get_value()
        page = adjustment.get_page_size()
        if allocation.y < value:
            adjustment.set_value(allocation.y)
        elif allocation.y + allocation.height > value + page:
            adjustment.set_value(max(0, allocation.y + allocation.height - page))
        return False

    def _task_widget(self, task, completed=False):
        tid = task['id']
        done = bool(task['done'])
        active = tid == self.model.current_id and not done
        row = style(Gtk.Box(spacing=5), 'task-row')
        if active:
            style(row, 'is-current')
        if done:
            style(row, 'task-completed')

        check = Gtk.CheckButton()
        check.set_valign(Gtk.Align.CENTER)
        check.set_active(done)
        check.set_tooltip_text('恢复为待办任务' if done else '标记任务完成')
        check.get_accessible().set_name('恢复为待办任务' if done else '标记任务完成')
        check.set_sensitive(not (active and self.model.phase == 'focus' and self.model.running()))
        check.connect('toggled', lambda widget: self.complete_task(tid, widget.get_active()))
        row.pack_start(check, False, False, 0)

        targets = [Gtk.TargetEntry.new('UTF8_STRING', Gtk.TargetFlags.SAME_APP, 0)]
        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.NONE)
        stack.set_hexpand(True)
        pick = style(Gtk.Button(), 'task-pick')
        pick.set_relief(Gtk.ReliefStyle.NONE)
        pick.set_hexpand(True)
        pick.set_tooltip_text('点击选择为当前任务' if not done else '已完成任务；取消勾选可恢复')
        text = label(task['title'], 'task-title-text', xalign=0)
        text.set_hexpand(True)
        text.set_ellipsize(Pango.EllipsizeMode.END)
        text.set_max_width_chars(36)
        pick.add(text)
        pick.connect('clicked', lambda *_: self.select_task(tid) if not done else None)

        field = Gtk.Entry(text=task['title'])
        field.set_width_chars(1)
        field.set_max_length(120)
        field.get_accessible().set_name('任务名称')
        field.set_tooltip_text('回车或离开输入框保存，Esc 取消')
        stack.add_named(pick, 'title')
        stack.add_named(field, 'edit')
        field.connect('activate', lambda *_: self._finish_edit())
        field.connect('focus-out-event', lambda *_: self._finish_edit())
        field.connect('key-press-event', self._edit_key)
        row.pack_start(stack, True, True, 0)

        pomodoros = task.get('pomodoros', 0)
        if pomodoros > 0:
            count = label(f'🍅 {pomodoros}', 'task-pomodoros')
            count.set_tooltip_text('这项任务累计完成的专注轮数')
            row.pack_start(count, False, False, 0)

        # Filtered rows have no unambiguous global reorder position.
        if not done and not self._query():
            handle = icon_button('list-drag-handle-symbolic', '拖动排序；Alt+↑ / Alt+↓ 调整顺序')
            style(handle, 'drag-handle')
            handle._qingfan_task_id = tid
            handle.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, targets, Gdk.DragAction.MOVE)
            handle.connect('drag-data-get', self._drag_task, tid)
            handle.connect('key-press-event', self._reorder_key, tid)
            row.pack_start(handle, False, False, 0)
            row.drag_dest_set(Gtk.DestDefaults.ALL, targets, Gdk.DragAction.MOVE)
            row.connect('drag-data-received', self._drop_task, tid)

        menu_button = Gtk.MenuButton()
        menu_button.set_relief(Gtk.ReliefStyle.NONE)
        menu_button.set_image(Gtk.Image.new_from_icon_name('view-more-symbolic', Gtk.IconSize.BUTTON))
        menu_button.set_tooltip_text('更多任务操作')
        menu_button.get_accessible().set_name('更多任务操作')
        style(menu_button, 'icon-button', 'task-menu-button')
        menu = Gtk.Menu()
        rename_item = Gtk.MenuItem(label='重命名')
        rename_item.connect('activate', lambda *_: self._begin_edit(tid, field, stack, text))
        menu.append(rename_item)
        delete_item = Gtk.MenuItem(label='删除任务')
        delete_item.connect('activate', lambda *_: self.remove_task(tid))
        menu.append(delete_item)
        menu.show_all()
        menu_button.set_popup(menu)
        row.pack_end(menu_button, False, False, 0)
        return row

    def _update_task_primary_action(self):
        if not hasattr(self, 'task_primary_button'):
            return
        if self.model.running():
            action = '返回专注' if self.model.phase == 'focus' else '返回休息'
            enabled = True
        elif self.model.phase == 'focus' and self.model.current_id is None:
            action = '先选择任务'
            enabled = False
        elif self.model.phase == 'focus':
            action = '继续专注' if self.model.seconds() < self.model.phase_duration else '开始专注'
            enabled = True
        else:
            action = '继续休息' if self.model.seconds() < self.model.phase_duration else '开始休息'
            enabled = True
        self.task_primary_button.set_label(action)
        self.task_primary_button.set_sensitive(enabled)

    def task_primary_action(self, *_):
        if self.model.running():
            self._set_mode(True)
            return
        if self.model.phase == 'focus' and self.model.current_id is None:
            self._show_status('请先选择一项待办任务。')
            return
        self.toggle_timer()

    def _show_status(self, message):
        self.status_label.set_text(message)
        self.status_label.show()
        if self._status_source is not None:
            GLib.source_remove(self._status_source)
        self._status_source = GLib.timeout_add_seconds(4, self._clear_status)

    def _clear_status(self):
        self._status_source = None
        self.status_label.hide()
        return False

    def _has_partial_focus(self):
        return (self.model.phase == 'focus' and not self.model.running()
                and self.model.seconds() < self.model.phase_duration - 0.5)

    def _confirm_action(self, title, body, affirmative='继续'):
        dialog = Gtk.MessageDialog(
            transient_for=self, flags=Gtk.DialogFlags.MODAL,
            message_type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.NONE,
            text=title)
        dialog.format_secondary_text(body)
        dialog.add_button('取消', Gtk.ResponseType.CANCEL)
        dialog.add_button(affirmative, Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.CANCEL)
        answer = dialog.run()
        dialog.destroy()
        return answer == Gtk.ResponseType.OK

    def _confirm_discard_partial(self, action):
        if not self._has_partial_focus():
            return True
        return self._confirm_action(
            f'{action}？',
            '当前专注已暂停但尚未完成。继续操作会放弃本轮计时，已完成的番茄记录不会改变。',
            '放弃本轮并继续')

    def select_task(self, tid):
        if tid == self.model.current_id:
            return
        if self.model.phase == 'focus' and self.model.running():
            self._show_status('专注进行中，请先暂停，再切换任务。')
            return
        if self._has_partial_focus() and not self._confirm_discard_partial('切换任务'):
            return
        if self.model.select(tid):
            self._finish_edit()
            self._save()
            self.refresh_tasks()
            self.refresh_clock()

    def _next_pending_after(self, ordered_before, task_id):
        remaining_ids = {task['id'] for task in self.model.pending_tasks}
        old_ids = [task['id'] for task in ordered_before]
        try:
            index = old_ids.index(task_id)
        except ValueError:
            index = -1
        for candidate in old_ids[index + 1:]:
            if candidate in remaining_ids:
                return candidate
        return next((task['id'] for task in self.model.pending_tasks), None)

    def _capture_undo_state(self, task_id=None):
        timer = None
        if task_id == self.model.current_id and self.model.phase == 'focus' and not self.model.running():
            timer = {
                'phase': self.model.phase,
                'remaining': self.model.seconds(),
                'phase_duration': self.model.phase_duration,
                'completed_rounds': self.model.completed_rounds,
            }
        return {
            'tasks': [dict(task) for task in self.model.tasks],
            'current_id': self.model.current_id,
            'timer': timer,
        }

    def _record_undo(self, snapshot, message):
        self._undo_state = snapshot
        self.undo_label.set_text(message)
        self.undo_bar.set_no_show_all(False)
        self.undo_bar.show_all()
        if self._undo_source is not None:
            GLib.source_remove(self._undo_source)
        self._undo_source = GLib.timeout_add_seconds(7, self._dismiss_undo)

    def complete_task(self, tid, done):
        task = next((item for item in self.model.tasks if item['id'] == tid), None)
        if task is None or task['done'] == bool(done):
            return
        was_current = self.model.current_id == tid
        if done and was_current and self.model.phase == 'focus' and self.model.running():
            self._show_status('当前任务正在专注，请先暂停后再标记完成。')
            self.refresh_tasks()
            return
        if done and was_current and not self._confirm_discard_partial('标记任务完成'):
            self.refresh_tasks()
            return

        pending_before = self.model.pending_tasks
        snapshot = self._capture_undo_state(tid if was_current else None)
        if done and was_current and self._has_partial_focus():
            self.model.reset()
        if not self.model.complete(tid, done):
            return
        if done and was_current:
            next_id = self._next_pending_after(pending_before, tid)
            if next_id is not None:
                self.model.select(next_id)
            elif self.model.phase == 'focus':
                self.model.reset()
        self._record_undo(snapshot, '任务已标记完成' if done else '任务已恢复到待办')
        self._deleted_task = None
        self._save()
        self.refresh_tasks()
        self.refresh_clock()

    def remove_task(self, tid):
        task = next((item for item in self.model.tasks if item['id'] == tid), None)
        if task is None:
            return
        was_current = self.model.current_id == tid
        if was_current and self.model.phase == 'focus' and self.model.running():
            self._show_status('当前任务正在专注，请先暂停后再删除。')
            return
        if was_current and not self._confirm_discard_partial('删除当前任务'):
            return
        pending_before = self.model.pending_tasks
        snapshot = self._capture_undo_state(tid if was_current else None)
        index = next(i for i, item in enumerate(self.model.tasks) if item['id'] == tid)
        self._deleted_task = (task.copy(), index, was_current)
        if was_current and self._has_partial_focus():
            self.model.reset()
        self.model.delete(tid)
        if was_current:
            next_id = self._next_pending_after(pending_before, tid)
            if next_id is not None:
                self.model.select(next_id)
            elif self.model.phase == 'focus':
                self.model.reset()
        self._record_undo(snapshot, '任务已删除')
        self._save()
        self.refresh_tasks()
        self.refresh_clock()

    def _dismiss_undo(self):
        self._undo_source = None
        self._undo_state = None
        self._deleted_task = None
        self.undo_bar.hide()
        self.undo_bar.set_no_show_all(True)
        return False

    def undo_delete(self, *_):
        if self._undo_state is None:
            return
        snapshot = self._undo_state
        self._undo_state = None
        if self._undo_source is not None:
            GLib.source_remove(self._undo_source)
            self._undo_source = None
        self.model.tasks = [dict(task) for task in snapshot['tasks']]
        self.model.current_id = snapshot['current_id']
        timer = snapshot.get('timer')
        if timer:
            self.model.phase = timer['phase']
            self.model.remaining = timer['remaining']
            self.model.phase_duration = timer['phase_duration']
            self.model.completed_rounds = timer['completed_rounds']
            self.model.deadline = None
        self._deleted_task = None
        self.undo_bar.hide()
        self.undo_bar.set_no_show_all(True)
        self._save()
        self.refresh_tasks()
        self.refresh_clock()

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
        changed = False
        if not cancel:
            before = next((t['title'] for t in self.model.tasks if t['id'] == tid), None)
            self.model.rename(tid, field.get_text())
            after = next((t['title'] for t in self.model.tasks if t['id'] == tid), None)
            changed = before != after
        task = next((t for t in self.model.tasks if t['id'] == tid), None)
        if task:
            text.set_text(task['title'])
            field.set_text(task['title'])
            text.get_parent().set_tooltip_text(task['title'] + '\n点击选择为当前任务')
        stack.set_visible_child_name('title')
        if not cancel and save and changed:
            self._save()
            self.refresh_clock()
            if not self._refreshing_tasks:
                GLib.idle_add(self.refresh_tasks)
        return False

    def _edit_key(self, _field, event):
        if event.keyval == Gdk.KEY_Escape:
            self._finish_edit(cancel=True)
            return True
        return False

    def _reorder_key(self, _widget, event, tid):
        if self._query():
            return False
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
        if self._query():
            Gtk.drag_finish(context, False, False, timestamp)
            return
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

    def open_settings(self, *_):
        self._finish_edit()
        if self._settings_dialog is not None:
            self._settings_dialog.present()
            return
        parent = self.orb_window if hasattr(self, 'orb_window') and self.orb_window.get_visible() else self
        dialog = Gtk.Dialog(title='专注与显示设置', transient_for=parent, flags=Gtk.DialogFlags.MODAL)
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
        grid.attach(label('悬浮透明度', xalign=0), 0, 3, 1, 1)
        alpha = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 70, 100, 5)
        alpha.set_size_request(170, -1)
        alpha.set_value(round(self.model.display.get('opacity', 0.9) * 100))
        alpha.set_digits(0)
        alpha.set_draw_value(True)
        alpha.set_tooltip_text('仅改变悬浮体底色；计时文字和进度环保持不透明')
        grid.attach(alpha, 1, 3, 2, 1)
        original_opacity = self.model.display.get('opacity', 0.9)

        def preview_opacity(widget):
            self.model.set_opacity(widget.get_value() / 100)
            if hasattr(self, 'orb_window'):
                self.orb_window.update()

        alpha.connect('value-changed', preview_opacity)
        note = label('新时长在下一次重置后生效。透明度可实时预览。', 'support-text', xalign=0)
        note.set_line_wrap(True)
        grid.attach(note, 0, 4, 3, 1)
        dialog.get_content_area().add(grid)
        dialog.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            for item in fields.values():
                item.update()
            self.model.update_settings({key: item.get_value_as_int() for key, item in fields.items()})
            self.model.set_opacity(alpha.get_value() / 100)
            self._save()
            self.refresh_clock()
        else:
            self.model.set_opacity(original_opacity)
            if hasattr(self, 'orb_window'):
                self.orb_window.update()
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
        if ctrl and event.keyval in (Gdk.KEY_f, Gdk.KEY_F):
            self.show_search()
            return True
        if event.keyval == Gdk.KEY_Escape and not self.compact:
            if self.search_entry.get_visible():
                if self.search_entry.get_text():
                    self.search_entry.set_text('')
                else:
                    self.search_entry.hide()
                    self._search_visible = False
                    self.entry.grab_focus()
                return True
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
        if hasattr(self, 'orb_window'):
            self.orb_window.destroy()
        if self._undo_source is not None:
            GLib.source_remove(self._undo_source)
            self._undo_source = None
        if self._status_source is not None:
            GLib.source_remove(self._status_source)
            self._status_source = None
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

"""Independent, translucent, shape-aware GTK focus surface.

The manage window keeps conventional desktop semantics; only this compact
surface requests an RGBA visual. No clicks are passed through to other apps.
"""
from __future__ import annotations

import math

import gi
# Without the Cairo foreign converter, PangoCairo callbacks fail silently on
# GTK's draw signal and the entire clock face disappears.
gi.require_version('PangoCairo', '1.0')
gi.require_foreign('cairo')
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo


def draw_text(context, value, x, y, *, size, color, weight=Pango.Weight.NORMAL, width=260):
    """Pango shapes Chinese and mixed-script glyphs correctly."""
    layout = PangoCairo.create_layout(context)
    layout.set_text(value, -1)
    description = Pango.FontDescription()
    description.set_family('Sans')
    description.set_weight(weight)
    description.set_absolute_size(size * Pango.SCALE)
    layout.set_font_description(description)
    layout.set_ellipsize(Pango.EllipsizeMode.END)
    layout.set_width(int(width * Pango.SCALE))
    pixels, _ = layout.get_pixel_size()
    context.set_source_rgba(*color)
    context.move_to(x - min(pixels, width) / 2, y)
    PangoCairo.show_layout(context, layout)


class FocusOrb(Gtk.ApplicationWindow):
    """A single additional app window with full and mini sizes.

    The timer always belongs to the host's model; the orb is presentation only.
    This keeps focus running through mode switches without duplicate timers.
    """
    FULL = (326, 356)
    MINI = (100, 100)

    def __init__(self, application, host):
        super().__init__(application=application, title='青番 · 专注')
        self.host = host
        self.get_style_context().add_class('orb-window')
        self.mini = False
        self._press_at = None
        self._click_source = None
        self.connect('destroy', self._cancel_click)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.UTILITY)
        self.set_app_paintable(True)
        self.set_keep_above(host.pinned)
        screen = self.get_screen()
        visual = screen.get_rgba_visual() if screen is not None else None
        self.has_rgba_visual = visual is not None
        if visual is not None:
            self.set_visual(visual)
        self.set_default_size(*self.FULL)
        self.set_size_request(-1, -1)
        self.connect('delete-event', self._on_close)
        self.connect('key-press-event', self._on_key)

        self.overlay = Gtk.Overlay()
        self.add(self.overlay)
        self.canvas = Gtk.DrawingArea()
        self.canvas.set_size_request(*self.FULL)
        self.canvas.add_events(Gdk.EventMask.BUTTON_PRESS_MASK |
                               Gdk.EventMask.BUTTON_RELEASE_MASK |
                               Gdk.EventMask.POINTER_MOTION_MASK)
        self.canvas.connect('draw', self._draw)
        self.canvas.connect('button-press-event', self._on_canvas_press)
        self.canvas.connect('button-release-event', self._on_canvas_release)
        self.canvas.connect('motion-notify-event', self._on_canvas_motion)
        self.canvas.set_tooltip_text('拖动空白处移动；双击暂停或继续；右键更多操作')
        self.overlay.add(self.canvas)

        self.controls = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.controls.set_halign(Gtk.Align.FILL)
        self.controls.set_valign(Gtk.Align.FILL)
        self.overlay.add_overlay(self.controls)

        top = Gtk.Box(spacing=0)
        top.set_margin_top(38)
        top.set_margin_start(44)
        top.set_margin_end(44)
        self.controls.pack_start(top, False, False, 0)
        self.tasks_button = self._icon('view-list-symbolic', '打开任务清单', self.open_tasks)
        top.pack_start(self.tasks_button, False, False, 0)
        top.pack_start(Gtk.Box(), True, True, 0)
        self.mini_button = self._icon('view-restore-symbolic', '缩小为迷你时钟', self.toggle_mini)
        top.pack_end(self.mini_button, False, False, 0)

        self.controls.pack_start(Gtk.Box(), True, True, 0)
        bottom = Gtk.Box(spacing=9)
        bottom.set_halign(Gtk.Align.CENTER)
        bottom.set_margin_bottom(46)
        self.controls.pack_end(bottom, False, False, 0)
        self.action_button = Gtk.Button(label='开始专注')
        self.action_button.get_style_context().add_class('orb-action')
        self.action_button.connect('clicked', host.toggle_timer)
        self.action_button.set_tooltip_text('开始或暂停计时  Space')
        bottom.pack_start(self.action_button, False, False, 0)
        self.reset_button = self._icon('view-refresh-symbolic', '重置当前计时', host.confirm_reset)
        self.reset_button.get_style_context().add_class('orb-reset')
        bottom.pack_end(self.reset_button, False, False, 0)

        self.show_all()
        self.set_mini(False)

    def _icon(self, icon_name, tooltip, callback):
        button = Gtk.Button()
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.set_image(Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.BUTTON))
        button.set_tooltip_text(tooltip)
        button.get_accessible().set_name(tooltip)
        button.get_style_context().add_class('orb-icon')
        button.connect('clicked', callback)
        return button

    def set_mini(self, mini):
        mini = bool(mini)
        self.mini = mini
        self.controls.set_visible(not mini)
        size = self.MINI if mini else self.FULL
        self.canvas.set_size_request(*size)
        self.resize(*size)
        self.queue_draw()

    def toggle_mini(self, *_):
        self.set_mini(not self.mini)
        self.present()

    def open_tasks(self, *_):
        self.set_mini(False)
        self.host._set_mode(False)
        self.host.present()

    def update(self, action=None):
        if action is not None and self.action_button.get_label() != action:
            self.action_button.set_label(action)
        self.canvas.queue_draw()

    def _draw(self, widget, cr):
        width = widget.get_allocated_width()
        height = widget.get_allocated_height()
        cr.save()
        # Full alpha clear; compositor may be absent on some X11 desktops.
        if self.has_rgba_visual:
            cr.set_operator(0)  # cairo.OPERATOR_CLEAR
            cr.paint()
            cr.set_operator(2)  # cairo.OPERATOR_OVER
        else:
            # Graceful fallback when the X11 desktop cannot composite alpha.
            cr.set_source_rgb(0.97, 0.98, 0.96)
            cr.paint()
        alpha = self.host.model.display.get('opacity', 0.9)
        phase = self.host.model.phase
        is_break = phase != 'focus'
        cr.translate(width / 2, height / 2)
        if self.mini:
            radius = min(width, height) / 2 - 4
            cr.set_source_rgba(0.958, 0.980, 0.966, alpha)
            cr.arc(0, 0, radius, 0, 2 * math.pi)
            cr.fill()
            ring_radius = radius - 6
            ring_y = 0
            thickness = 4.5
        else:
            # The slightly tall ellipse references a tomato without illustration.
            cr.save()
            cr.scale(1, 1.07)
            cr.set_source_rgba(0.958, 0.980, 0.966, alpha)
            cr.arc(0, 0, min(width / 2 - 5, height / 2 / 1.07 - 5),
                   0, 2 * math.pi)
            cr.fill()
            cr.restore()
            ring_radius = 105
            ring_y = -40
            thickness = 5.5
        cr.set_line_width(thickness)
        cr.set_source_rgba(0.68, 0.79, 0.73, 0.32)
        cr.arc(0, ring_y, ring_radius, 0, 2 * math.pi)
        cr.stroke()
        fraction = 1 - self.host.model.seconds() / max(1, self.host.model.phase_duration)
        fraction = min(1, max(0, fraction))
        cr.set_source_rgba(*(0.27, 0.49, 0.55, 1) if is_break else (0.20, 0.43, 0.32, 1))
        cr.arc(0, ring_y, ring_radius, -math.pi / 2, -math.pi / 2 + 2 * math.pi * fraction)
        cr.stroke()

        remaining = math.ceil(self.host.model.seconds())
        remaining_label = f'{remaining // 60:02d}:{remaining % 60:02d}'
        dark = (0.12, 0.30, 0.23, 1)
        subtle = (0.36, 0.47, 0.41, 1)
        if self.mini:
            draw_text(cr, remaining_label, 0, -13, size=18, color=dark,
                      weight=Pango.Weight.BOLD, width=84)
        else:
            phase_name = ('专注中 · 第 %s / 4 轮' % (self.host.model.completed_rounds % 4 + 1)) if phase == 'focus' else (
                '短休息 · 放松一下' if phase == 'short' else '长休息 · 好好充电')
            draw_text(cr, phase_name, 0, -93, size=13, color=subtle,
                      weight=Pango.Weight.SEMIBOLD, width=242)
            draw_text(cr, remaining_label, 0, -52, size=49, color=dark,
                      weight=Pango.Weight.BOLD, width=250)
            draw_text(cr, self.host.model.current_title(), 0, 8, size=14, color=dark,
                      weight=Pango.Weight.SEMIBOLD, width=202)
            rounds = self.host.model.completed_rounds % 4
            for index in range(4):
                cr.set_source_rgba(*(0.30, 0.54, 0.40, 0.98) if index < rounds
                                   else (0.72, 0.81, 0.75, 0.65))
                cr.arc((index - 1.5) * 17, 46, 3.5, 0, 2 * math.pi)
                cr.fill()
        cr.restore()
        return False

    def _cancel_click(self, *_):
        if self._click_source is not None:
            GLib.source_remove(self._click_source)
            self._click_source = None
        self._press_at = None

    def _single_click(self):
        self._click_source = None
        if self.mini:
            self.set_mini(False)
        return False

    def _on_canvas_release(self, _widget, event):
        if event.button == 1 and self._press_at is not None:
            self._press_at = None
            self._cancel_click()
            self._click_source = GLib.timeout_add(230, self._single_click)
            return True
        return False

    def _on_canvas_motion(self, _widget, event):
        if self._press_at is not None:
            x, y = self._press_at
            if (event.x_root - x) ** 2 + (event.y_root - y) ** 2 > 64:
                self._cancel_click()
                self.begin_move_drag(1, int(event.x_root), int(event.y_root), event.time)
                return True
        return False

    def _popup_menu(self, event):
        menu = Gtk.Menu()
        def entry(title, callback):
            item = Gtk.MenuItem(label=title)
            item.connect('activate', lambda *_: callback())
            menu.append(item)
        entry('打开任务清单', self.open_tasks)
        entry('展开时钟' if self.mini else '缩小为迷你时钟', self.toggle_mini)
        entry('暂停' if self.host.model.running() else '开始 / 继续', self.host.toggle_timer)
        entry('计时与透明度设置', self.host.open_settings)
        entry('取消置顶' if self.host.pinned else '保持置顶', self.host.toggle_pin)
        entry('退出青番', self.host.close)
        menu.show_all()
        menu.popup_at_pointer(event)

    def _on_canvas_press(self, _widget, event):
        if event.button == 3:
            self._popup_menu(event)
            return True
        if event.button == 2:
            self.begin_move_drag(event.button, int(event.x_root), int(event.y_root), event.time)
            return True
        if event.button == 1 and event.type == Gdk.EventType._2BUTTON_PRESS:
            self._cancel_click()
            self.host.toggle_timer()
            return True
        if event.button == 1:
            if self._click_source is not None:
                GLib.source_remove(self._click_source)
                self._click_source = None
            self._press_at = (event.x_root, event.y_root)
            return True
        return False

    def _on_key(self, _widget, event):
        if event.keyval in (Gdk.KEY_space, Gdk.KEY_KP_Space):
            self.host.toggle_timer()
            return True
        if event.keyval == Gdk.KEY_Escape and not self.mini:
            self.toggle_mini()
            return True
        if event.state & Gdk.ModifierType.CONTROL_MASK and event.keyval in (Gdk.KEY_l, Gdk.KEY_L):
            self.open_tasks()
            return True
        if event.state & Gdk.ModifierType.CONTROL_MASK and event.keyval in (Gdk.KEY_n, Gdk.KEY_N):
            self.open_tasks()
            self.host.entry.grab_focus()
            return True
        return False

    def _on_close(self, *_):
        # Closing the floating surface closes its hidden owner as well.
        self.host.close()
        return True

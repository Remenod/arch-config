#!/usr/bin/env python3
"""Notification archive panel: a second page of the swaync control center.

Lists what archive.sh logged, newest first, in a layer-shell panel at the
control center's place. It loads swaync's own style.css and builds its rows
from the same CSS classes, so it looks like the control center. Typing
filters, clicking a notification copies its text, and Escape, "back" or a
click outside closes it ("back" reopens the control center). Starting it
again while it is open closes it.

gtk4-layer-shell has to be loaded before libwayland-client, so archive.sh
starts this with LD_PRELOAD.
"""

import html
import json
import os
import re
import subprocess
from datetime import date, datetime, timedelta
from pathlib import Path

import gi

# GTK's default Vulkan renderer enumerates every GPU at start-up, which wakes
# the runtime-suspended RX 6700M and costs about a second; GL stays on the iGPU.
os.environ.setdefault("GSK_RENDERER", "ngl")

gi.require_version("Gdk", "4.0")
gi.require_version("GioUnix", "2.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gdk, GioUnix, GLib, Gtk, Pango  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

STATE_HOME = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
ARCHIVE_DIR = STATE_HOME / "notifications"
STYLE = CONFIG_HOME / "swaync/style.css"

# Matches control-center-width and the control-center margins in config.json.
WIDTH = 420
MARGIN = 5
# Rows built at once; a search looks through everything but shows this many.
MAX_ROWS = 300
BODY_LINES = 4

TAG = re.compile(r"<[^>]*>")


def plain(markup):
    """Notification text is Pango markup; the archive shows it as text."""
    return html.unescape(TAG.sub("", markup or "")).strip()


def load_entries():
    entries = []
    for path in sorted(ARCHIVE_DIR.glob("*.jsonl"), reverse=True):
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in reversed(lines):
            try:
                entry = json.loads(line)
                when = datetime.fromisoformat(entry["time"])
            except (ValueError, KeyError, TypeError):
                continue
            app = entry.get("app") or ""
            summary = plain(entry.get("summary"))
            body = plain(entry.get("body"))
            entries.append({
                "when": when,
                "app": app,
                "summary": summary,
                "body": body,
                "urgency": (entry.get("urgency") or "normal").lower(),
                "desktop_entry": entry.get("desktop_entry"),
                "search": f"{app} {summary} {body}".casefold(),
            })
    return entries


def day_label(day):
    today = date.today()
    if day == today:
        return "today"
    if day == today - timedelta(days=1):
        return "yesterday"
    return day.strftime("%d-%m" if day.year == today.year else "%d-%m-%Y")


class ArchivePanel(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.notification.archive")
        self.panel = None
        self.icons = {}

    def do_activate(self):
        # A second launch lands here in the running instance: toggle off.
        if self.panel is not None:
            self.quit()
            return

        Gtk.Settings.get_default().props.gtk_interface_color_scheme = Gtk.InterfaceColorScheme.DARK
        css = Gtk.CssProvider()
        css.load_from_path(str(STYLE))
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        self.entries = load_entries()
        self.build_blank()
        self.build_panel()
        self.refill()

    # A transparent window under the panel, as swaync has, so a click
    # anywhere else closes it.
    def build_blank(self):
        blank = Gtk.Window(application=self, css_classes=["archive-blank"])
        LayerShell.init_for_window(blank)
        LayerShell.set_namespace(blank, "notification-archive-blank")
        LayerShell.set_layer(blank, LayerShell.Layer.TOP)
        for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM,
                     LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(blank, edge, True)
        LayerShell.set_exclusive_zone(blank, -1)
        LayerShell.set_keyboard_mode(blank, LayerShell.KeyboardMode.NONE)
        click = Gtk.GestureClick()
        click.connect("released", lambda *_: self.quit())
        blank.add_controller(click)
        blank.present()

    def build_panel(self):
        panel = Gtk.Window(application=self, css_classes=["archive-panel"])
        panel.set_size_request(WIDTH, -1)
        LayerShell.init_for_window(panel)
        LayerShell.set_namespace(panel, "notification-archive")
        LayerShell.set_layer(panel, LayerShell.Layer.OVERLAY)
        for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM, LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(panel, edge, True)
            LayerShell.set_margin(panel, edge, MARGIN)
        LayerShell.set_keyboard_mode(panel, LayerShell.KeyboardMode.EXCLUSIVE)

        self.title = Gtk.Label(label="archive", xalign=0, hexpand=True)
        back = Gtk.Button(label="back")
        back.connect("clicked", self.on_back)
        title = Gtk.Box(css_classes=["widget", "widget-title"])
        title.append(self.title)
        title.append(back)

        self.search = Gtk.SearchEntry(placeholder_text="search", css_classes=["archive-search"])
        self.search.connect("search-changed", lambda *_: self.refill())

        self.list = Gtk.ListBox(css_classes=["control-center-list"],
                                selection_mode=Gtk.SelectionMode.NONE)
        self.placeholder = Gtk.Label(css_classes=["control-center-list-placeholder"],
                                     vexpand=True)
        self.list.set_placeholder(self.placeholder)
        scroll = Gtk.ScrolledWindow(child=self.list, vexpand=True,
                                    hscrollbar_policy=Gtk.PolicyType.NEVER)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                       css_classes=["control-center", "archive"])
        root.append(title)
        root.append(self.search)
        root.append(scroll)
        panel.set_child(root)

        # Capture phase: the search entry would otherwise take Escape itself.
        keys = Gtk.EventControllerKey(propagation_phase=Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self.on_key)
        panel.add_controller(keys)

        self.panel = panel
        panel.present()
        self.search.grab_focus()

    def refill(self):
        words = self.search.get_text().casefold().split()
        self.list.remove_all()
        self.placeholder.set_label("nothing found" if words else "no archived notifications")

        shown = 0
        last_day = None
        for entry in self.entries:
            if not all(word in entry["search"] for word in words):
                continue
            day = entry["when"].date()
            if day != last_day:
                self.list.append(self.day_row(day))
                last_day = day
            self.list.append(self.entry_row(entry))
            shown += 1
            if shown == MAX_ROWS:
                break

    def day_row(self, day):
        label = Gtk.Label(label=day_label(day), xalign=0, css_classes=["archive-day"])
        return Gtk.ListBoxRow(child=label, activatable=False, focusable=False)

    def icon(self, desktop_entry):
        if desktop_entry not in self.icons:
            try:
                info = GioUnix.DesktopAppInfo.new(desktop_entry + ".desktop")
            except TypeError:  # no such desktop file
                info = None
            self.icons[desktop_entry] = info.get_icon() if info else None
        return self.icons[desktop_entry]

    # Rows nest the classes swaync gives its own, so its style.css draws them.
    def entry_row(self, entry):
        summary = Gtk.Label(label=entry["summary"] or entry["app"], xalign=0, hexpand=True,
                            ellipsize=Pango.EllipsizeMode.END, css_classes=["summary"])
        stamp = entry["when"].strftime("%H:%M")
        time = Gtk.Label(label=f"{entry['app']} · {stamp}" if entry["app"] else stamp,
                         css_classes=["time"])
        head = Gtk.Box()
        head.append(summary)
        head.append(time)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True,
                       css_classes=["text-box"])
        text.append(head)
        if entry["body"]:
            text.append(Gtk.Label(label=entry["body"], xalign=0, wrap=True,
                                  wrap_mode=Pango.WrapMode.WORD_CHAR, max_width_chars=1,
                                  lines=BODY_LINES, ellipsize=Pango.EllipsizeMode.END,
                                  css_classes=["body"]))

        content = Gtk.Box(css_classes=["notification-content"])
        icon = self.icon(entry["desktop_entry"]) if entry["desktop_entry"] else None
        if icon is not None:
            content.append(Gtk.Image(gicon=icon, valign=Gtk.Align.START, css_classes=["image"]))
        content.append(text)

        action = Gtk.Button(child=content, css_classes=["notification-default-action"])
        action.connect("clicked", self.on_copy, entry)
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                       css_classes=["notification", entry["urgency"]])
        card.append(action)
        background = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                             css_classes=["notification-background"])
        background.append(card)
        return Gtk.ListBoxRow(child=background, activatable=False, focusable=False,
                              css_classes=["notification-row"])

    def on_copy(self, _button, entry):
        text = "\n".join(part for part in (entry["summary"], entry["body"]) if part)
        subprocess.run(["wl-copy"], input=text.encode(), check=False)
        self.title.set_label("copied")
        GLib.timeout_add(1200, self.reset_title)

    def reset_title(self):
        self.title.set_label("archive")
        return GLib.SOURCE_REMOVE

    def on_back(self, _button):
        subprocess.Popen(["swaync-client", "--open-panel", "--skip-wait"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.quit()

    def on_key(self, _controller, keyval, _keycode, _state):
        if keyval != Gdk.KEY_Escape:
            return False
        if self.search.get_text():
            self.search.set_text("")
        else:
            self.quit()
        return True


if __name__ == "__main__":
    ArchivePanel().run(None)

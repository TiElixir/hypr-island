#!/usr/bin/env python3
"""Minimal fake MPRIS player for testing the Spotify activity without Spotify.

    tests/fake-mpris.py [--name fakespotify] [--no-length]

Registers org.mpris.MediaPlayer2.<name>, plays a few fake tracks, and answers
play/pause/next/previous/seek, so `playerctl -p <name> ...` and the island's
buttons both work. Ctrl-C to quit.
"""
import argparse
import os
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

ART = os.path.expanduser("~/.config/quickshell/overview/assets/image.png")
TRACKS = [
    ("Midnight City", "M83", "Hurry Up, We're Dreaming", 243),
    ("A Very Long Track Title That Must Be Elided Properly", "Some Artist With A Long Name", "Album", 187),
    ("Short", "Duo", "EP", 95),
]
PLAYER = "org.mpris.MediaPlayer2.Player"
ROOT = "org.mpris.MediaPlayer2"
PROPS = "org.freedesktop.DBus.Properties"


class Fake(dbus.service.Object):
    def __init__(self, bus, name, with_length):
        super().__init__(bus, "/org/mpris/MediaPlayer2")
        self.name = name
        self.with_length = with_length
        self.idx = 0
        self.playing = True
        self.base_pos = 0.0
        self.base_t = time.monotonic()

    # ---- state -----------------------------------------------------------
    def pos(self):
        if not self.playing:
            return self.base_pos
        return self.base_pos + time.monotonic() - self.base_t

    def set_pos(self, seconds):
        self.base_pos = max(0.0, seconds)
        self.base_t = time.monotonic()

    def metadata(self):
        title, artist, album, length = TRACKS[self.idx]
        md = {
            "mpris:trackid": dbus.ObjectPath(f"/fake/track/{self.idx}"),
            "mpris:artUrl": "file://" + ART,
            "xesam:title": title,
            "xesam:artist": dbus.Array([artist], signature="s"),
            "xesam:album": album,
        }
        if self.with_length:
            md["mpris:length"] = dbus.Int64(length * 1_000_000)
        return dbus.Dictionary(md, signature="sv")

    def player_props(self):
        return {
            "PlaybackStatus": "Playing" if self.playing else "Paused",
            "Metadata": self.metadata(),
            "CanGoNext": True,
            "CanGoPrevious": True,
            "CanPlay": True,
            "CanPause": True,
            "CanSeek": self.with_length,
            "CanControl": True,
            "Rate": 1.0,
            "MinimumRate": 1.0,
            "MaximumRate": 1.0,
            "Volume": 1.0,
            "LoopStatus": "None",
            "Shuffle": False,
        }

    def root_props(self):
        return {
            "CanQuit": False,
            "CanRaise": False,
            "HasTrackList": False,
            "Identity": "Spotify",
            "DesktopEntry": "spotify",
            "SupportedUriSchemes": dbus.Array([], signature="s"),
            "SupportedMimeTypes": dbus.Array([], signature="s"),
        }

    def changed(self, *keys):
        props = self.player_props()
        self.PropertiesChanged(PLAYER, {k: props[k] for k in keys}, dbus.Array([], signature="s"))

    # ---- org.freedesktop.DBus.Properties ---------------------------------
    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        if iface == PLAYER:
            if prop == "Position":
                return dbus.Int64(self.pos() * 1_000_000)
            return self.player_props()[prop]
        return self.root_props()[prop]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        if iface == PLAYER:
            props = self.player_props()
            props["Position"] = dbus.Int64(self.pos() * 1_000_000)
            return props
        return self.root_props()

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, iface, prop, value):
        pass

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    # ---- org.mpris.MediaPlayer2 ------------------------------------------
    @dbus.service.method(ROOT)
    def Raise(self):
        pass

    @dbus.service.method(ROOT)
    def Quit(self):
        pass

    # ---- org.mpris.MediaPlayer2.Player -----------------------------------
    @dbus.service.method(PLAYER)
    def Play(self):
        if not self.playing:
            self.base_t = time.monotonic()
            self.playing = True
            self.changed("PlaybackStatus")

    @dbus.service.method(PLAYER)
    def Pause(self):
        if self.playing:
            self.base_pos = self.pos()
            self.playing = False
            self.changed("PlaybackStatus")

    @dbus.service.method(PLAYER)
    def PlayPause(self):
        self.Pause() if self.playing else self.Play()

    @dbus.service.method(PLAYER)
    def Stop(self):
        self.Pause()

    def _go(self, delta):
        self.idx = (self.idx + delta) % len(TRACKS)
        self.set_pos(0)
        self.changed("Metadata")

    @dbus.service.method(PLAYER)
    def Next(self):
        self._go(1)

    @dbus.service.method(PLAYER)
    def Previous(self):
        self._go(-1)

    @dbus.service.method(PLAYER, in_signature="x")
    def Seek(self, offset_us):
        self.set_pos(self.pos() + offset_us / 1_000_000)
        self.Seeked(dbus.Int64(self.pos() * 1_000_000))

    @dbus.service.method(PLAYER, in_signature="ox")
    def SetPosition(self, track_id, pos_us):
        self.set_pos(pos_us / 1_000_000)
        self.Seeked(dbus.Int64(pos_us))

    @dbus.service.signal(PLAYER, signature="x")
    def Seeked(self, pos_us):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="fakespotify")
    ap.add_argument("--no-length", action="store_true", help="simulate an ad/podcast with length 0")
    args = ap.parse_args()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    bus_name = dbus.service.BusName(f"org.mpris.MediaPlayer2.{args.name}", bus)  # keep a reference or the name is released
    Fake(bus, args.name, not args.no_length)
    print(f"fake player org.mpris.MediaPlayer2.{args.name} running", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()

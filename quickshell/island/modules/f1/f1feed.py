#!/usr/bin/env python3
"""Live Formula 1 timing for the island's f1 module.

Reads F1's own live-timing hub (livetiming.formula1.com, the feed OpenF1 and
FastF1 are built on), which needs no account. SignalR Core over Server-Sent
Events, so nothing beyond the standard library is needed. Every line printed is
one JSON object for the module:

  {"t":"state", ...}     session, track status and every car's timing, throttled
  {"t":"drivers", ...}   the entry list, when it changes
  {"_event":"pit"|"penalty"|"position"|"status"|"start", ...}   things that just
                         happened, for every driver (the module picks yours; the
                         island also emits these as f1.<name> on its bus)

Every car is sent so that choosing a driver in the island is instant and needs
no reconnect. Option: ISLAND_OPT_SESSIONS ("races" or "all"). The script
connects only while a session is on or close.
"""
import datetime as dt
import http.cookiejar
import json
import os
import re
import sys
import threading
import time
import urllib.request

BASE = os.environ.get("ISLAND_F1_URL", "https://livetiming.formula1.com/signalrcore")
TOPICS = ["Heartbeat", "SessionInfo", "SessionStatus", "TrackStatus", "RaceControlMessages",
          "TimingData", "TimingAppData", "DriverList", "LapCount", "PitLaneTimeCollection",
          "PitStopSeries"]
RS = "\x1e"
UA = {"User-Agent": "island-f1/1.0"}
ALL_SESSIONS = os.environ.get("ISLAND_OPT_SESSIONS", "races") == "all"

TRACK = {"1": ("green", "Track clear"), "2": ("yellow", "Yellow flag"), "4": ("sc", "Safety car"),
         "5": ("red", "Red flag"), "6": ("vsc", "Virtual safety car"), "7": ("vscending", "VSC ending")}
SEG = {2048: "y", 2049: "g", 2050: "y", 2051: "p", 2052: "y", 2064: "pit"}
# Formation lap: this many cars timed on track within this many seconds.
FORMATION_CARS = 3
FORMATION_WINDOW = 45


def log(*a):
    print("f1feed:", *a, file=sys.stderr, flush=True)


_out_lock = threading.Lock()


def out(obj):
    with _out_lock:
        sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def norm(x):
    """Lists become {"0": ..} dicts so incremental updates can merge into them."""
    if isinstance(x, list):
        return {str(i): norm(v) for i, v in enumerate(x)}
    if isinstance(x, dict):
        return {k: norm(v) for k, v in x.items()}
    return x


def merge(dst, src):
    for k, v in src.items():
        if k == "_deleted" and isinstance(v, (list, dict)):
            for d in (v.values() if isinstance(v, dict) else v):
                dst.pop(str(d), None)
        elif isinstance(v, dict) and isinstance(dst.get(k), dict):
            merge(dst[k], v)
        else:
            dst[k] = v


def ordered(d):
    if not isinstance(d, dict):
        return []
    return [d[k] for k in sorted(d, key=lambda s: int(s) if s.isdigit() else 1 << 30)]


def to_int(v):
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return None


def moving(ln):
    """A car's timing update shows it passing a minisector or a speed trap.
    Resets (status 0, empty values) don't count."""
    secs = ln.get("Sectors")
    for sec in secs.values() if isinstance(secs, dict) else []:
        if not isinstance(sec, dict):
            continue
        segs = sec.get("Segments")
        if sec.get("Value") or (isinstance(segs, dict) and any(isinstance(g, dict) and to_int(g.get("Status"))
                                                                for g in segs.values())):
            return True
    speeds = ln.get("Speeds")
    return isinstance(speeds, dict) and any(isinstance(v, dict) and v.get("Value") for v in speeds.values())


def utc_of(local, offset):
    """SessionInfo dates are track-local; GmtOffset is like -06:00:00."""
    try:
        t = dt.datetime.fromisoformat(local)
        sign = -1 if offset.startswith("-") else 1
        h, m, s = (int(x) for x in offset.lstrip("+-").split(":"))
        return (t - sign * dt.timedelta(hours=h, minutes=m, seconds=s)).replace(tzinfo=dt.timezone.utc)
    except (ValueError, TypeError, AttributeError):
        return None


class Feed:
    def __init__(self):
        self.s = {}
        self.lock = threading.Lock()
        self.dirty = False
        self.ready = False
        self.seen_rc = set()
        self.prev_pos = {}
        self.prev_inpit = {}
        self.prev_track = None
        self.prev_status = None
        self.formation = False
        self.moved = {}          # car -> when its timing last showed it on track
        self.pits = {}
        self.sectors_flag = {}
        self.drivers_sig = ""

    # ---- ingest ------------------------------------------------------------
    def snapshot(self, res):
        with self.lock:
            for topic, data in res.items():
                if isinstance(data, (dict, list)):
                    self.s[topic] = norm(data)
            for m in ordered(self.s.get("RaceControlMessages", {}).get("Messages")):
                self.seen_rc.add(self.rc_key(m))
                self.track_sector_flag(m)
            self.ready = True
            self.analyse(initial=True)
            self.dirty = True

    def update(self, topic, data):
        if topic == "Heartbeat" or not isinstance(data, (dict, list)):
            return
        with self.lock:
            cur = self.s.setdefault(topic, {})
            diff = norm(data)
            merge(cur, diff)
            if topic == "RaceControlMessages":
                self.new_rc(ordered(diff.get("Messages")))
            if topic == "TimingData" and isinstance(diff.get("Lines"), dict):
                now = time.time()
                for num, ln in diff["Lines"].items():
                    if isinstance(ln, dict) and moving(ln):
                        self.moved[num] = now
            if self.ready:
                self.analyse(initial=False)
            self.dirty = True

    # ---- the selected driver ----------------------------------------------------
    def drivers(self):
        out_ = []
        for num, d in (self.s.get("DriverList") or {}).items():
            if not isinstance(d, dict) or not d.get("Tla"):
                continue
            out_.append({"n": num, "tla": d.get("Tla", ""), "name": d.get("FullName") or d.get("BroadcastName", ""),
                         "team": d.get("TeamName", ""), "color": "#" + (d.get("TeamColour") or "888888"),
                         "line": to_int(d.get("Line")) or 99})
        out_.sort(key=lambda x: x["line"])
        return out_

    def lines(self):
        ls = (self.s.get("TimingData") or {}).get("Lines") or {}
        return {k: v for k, v in ls.items() if isinstance(v, dict)}

    def stint(self, num):
        app = ((self.s.get("TimingAppData") or {}).get("Lines") or {}).get(num) or {}
        st = ordered(app.get("Stints"))
        return (st[-1] if st else None), len(st)

    def session_type(self):
        return (self.s.get("SessionInfo") or {}).get("Type", "")

    def wanted_session(self):
        return ALL_SESSIONS or self.session_type() == "Race"

    def race_running(self):
        return (self.s.get("SessionStatus") or {}).get("Status") in ("Started", "Aborted")

    def start_time(self):
        si = self.s.get("SessionInfo") or {}
        return utc_of(si.get("StartDate"), si.get("GmtOffset", "00:00:00"))

    def formation_now(self):
        """F1 sends nothing for the formation lap: it is a race that hasn't
        started, past its scheduled start, with cars being timed on track. The
        start time rules out the reconnaissance laps half an hour earlier."""
        if self.session_type() != "Race" or (self.s.get("SessionStatus") or {}).get("Status") != "Inactive":
            return False
        start = self.start_time()
        if start is None or dt.datetime.now(dt.timezone.utc) < start - dt.timedelta(minutes=1):
            return False
        now = time.time()
        return sum(1 for t in self.moved.values() if now - t < FORMATION_WINDOW) >= FORMATION_CARS

    def live(self):
        """On track now, or within an hour before / half an hour after."""
        si = self.s.get("SessionInfo") or {}
        if not si or not self.wanted_session():
            return False
        if self.race_running():
            return True
        status = (self.s.get("SessionStatus") or {}).get("Status", "")
        start = self.start_time()
        end = utc_of(si.get("EndDate"), si.get("GmtOffset", "00:00:00"))
        now = dt.datetime.now(dt.timezone.utc)
        if status in ("Finished", "Finalised", "Ends"):
            return end is not None and now < end + dt.timedelta(minutes=30)
        return start is not None and start - dt.timedelta(hours=1) <= now <= (end or start) + dt.timedelta(minutes=30)

    # ---- race control ---------------------------------------------------------
    @staticmethod
    def rc_key(m):
        return (m.get("Utc"), m.get("Message"))

    def track_sector_flag(self, m):
        if m.get("Category") != "Flag":
            return
        flag = (m.get("Flag") or "").upper()
        if m.get("Scope") == "Sector" and m.get("Sector") is not None:
            if flag in ("CLEAR", "GREEN"):
                self.sectors_flag.pop(str(m["Sector"]), None)
            else:
                self.sectors_flag[str(m["Sector"])] = flag
        elif m.get("Scope") == "Track" and flag in ("GREEN", "CLEAR", "CHEQUERED", "RED"):
            self.sectors_flag.clear()

    def new_rc(self, msgs):
        for m in msgs:
            if not isinstance(m, dict):
                continue
            k = self.rc_key(m)
            if k in self.seen_rc:
                continue
            self.seen_rc.add(k)
            self.track_sector_flag(m)
            text = m.get("Message", "")
            up = text.upper()
            if (m.get("Flag") or "").upper() == "CHEQUERED":
                out({"_event": "status", "code": "chequered", "label": "Chequered flag", "message": text})
            if "PENALTY" in up and not re.search(r"SERVED|NO FURTHER|NOTED|UNDER INVESTIGATION|REVOKED|CANCELLED", up):
                car = m.get("RacingNumber") or (re.search(r"\bCAR (\d+)", up) or [None, None])[1]
                tla = next((d["tla"] for d in self.drivers() if d["n"] == str(car)), "")
                out({"_event": "penalty", "driver": str(car or ""), "tla": tla,
                     "lap": m.get("Lap"), "message": text, "summary": penalty_summary(up)})

    # ---- derived events ----------------------------------------------------------
    def analyse(self, initial):
        ts = (self.s.get("TrackStatus") or {}).get("Status")
        if ts != self.prev_track:
            if not initial and ts in TRACK:
                code, label = TRACK[ts]
                out({"_event": "status", "code": code, "label": label, "sectors": sorted(self.sectors_flag)})
            self.prev_track = ts

        race = self.session_type() == "Race"
        # Lights out: a race going from not started (or red-flagged) to started.
        status = (self.s.get("SessionStatus") or {}).get("Status")
        if status != self.prev_status:
            if not initial and race and status == "Started" and self.prev_status in ("Inactive", "Aborted"):
                out({"_event": "start", "restart": self.prev_status == "Aborted",
                     "lap": to_int((self.s.get("LapCount") or {}).get("CurrentLap"))})
            self.prev_status = status
        form = self.formation_now()
        if form != self.formation:
            if form and not initial:
                out({"_event": "status", "code": "formation", "label": "Formation lap", "sectors": []})
            self.formation = form

        running = self.race_running()
        now = time.time()
        for num, ln in self.lines().items():
            pos = to_int(ln.get("Position"))
            prev = self.prev_pos.get(num)
            if pos and prev and pos != prev and not initial and running and race:
                out({"_event": "position", "driver": num, "from": prev, "to": pos, "gained": prev - pos})
            if pos:
                self.prev_pos[num] = pos

            inpit = bool(ln.get("InPit"))
            st, nst = self.stint(num)
            if self.prev_inpit.get(num) is False and inpit and not initial and running:
                self.pits[num] = {"phase": "in", "since": now, "lap": to_int(ln.get("NumberOfLaps")),
                                  "oldCompound": (st or {}).get("Compound", ""), "stints": nst,
                                  "compound": "", "new": None, "stop": "", "lane": ""}
                out({"_event": "pit", "phase": "in", "driver": num, "lap": self.pits[num]["lap"]})
            self.prev_inpit[num] = inpit
            if num in self.pits:
                self.track_pit(num, inpit, st, nst, now)

    def track_pit(self, num, inpit, st, nst, now):
        p = self.pits[num]
        if p["phase"] == "in" and not inpit:
            p["phase"], p["out"] = "out", now
        if nst > p["stints"] and st:
            p["compound"] = st.get("Compound", "")
            p["new"] = str(st.get("New", "")).lower() == "true"
        lane = ((self.s.get("PitLaneTimeCollection") or {}).get("PitTimes") or {}).get(num) or {}
        if lane.get("Duration"):
            p["lane"] = lane["Duration"]
        stops = ordered(((self.s.get("PitStopSeries") or {}).get("PitTimes") or {}).get(num))
        if stops:
            ps = (stops[-1] or {}).get("PitStop") or {}
            if to_int(ps.get("Lap")) is None or p["lap"] is None or to_int(ps.get("Lap")) >= p["lap"]:
                p["stop"] = ps.get("PitStopTime") or p["stop"]
                p["lane"] = p["lane"] or ps.get("PitLaneTime") or ""
        if p["phase"] == "out" and ((p["lane"] and p["compound"]) or now - p["out"] > 40):
            p["phase"], p["done"] = "done", now
            out({"_event": "pit", "phase": "done", "driver": num, "lap": p["lap"],
                 "compound": p["compound"], "new": p["new"], "stop": p["stop"], "lane": p["lane"]})
        if (p["phase"] == "done" and now - p["done"] > 12) or now - p["since"] > 150:
            del self.pits[num]

    # ---- output ----------------------------------------------------------------
    def state(self):
        si = self.s.get("SessionInfo") or {}
        lc = self.s.get("LapCount") or {}
        ts = (self.s.get("TrackStatus") or {}).get("Status", "1")
        code, label = TRACK.get(ts, ("green", "Track clear"))
        st = {"t": "state", "live": self.live(),
              "session": {"type": si.get("Type", ""), "name": si.get("Name", ""),
                          "meeting": (si.get("Meeting") or {}).get("Name", ""),
                          "status": (self.s.get("SessionStatus") or {}).get("Status", ""),
                          "formation": self.formation_now()},
              "lap": [to_int(lc.get("CurrentLap")) or 0, to_int(lc.get("TotalLaps")) or 0],
              "track": {"code": code, "label": label, "sectors": sorted(self.sectors_flag, key=lambda x: to_int(x) or 0)},
              "cars": {num: self.car(num, ln) for num, ln in self.lines().items()},
              "pits": {num: {k: v for k, v in p.items() if k in ("phase", "lap", "oldCompound", "compound", "new", "stop", "lane")}
                       for num, p in self.pits.items()}}
        return st

    def car(self, num, ln):
        secs = []
        for sec in ordered(ln.get("Sectors"))[:3]:
            v = sec.get("Value", "") or ""
            c = "p" if sec.get("OverallFastest") and v else "g" if sec.get("PersonalFastest") and v else "y" if v else ""
            secs.append({"v": v, "c": c, "seg": [SEG.get(to_int(g.get("Status")) or 0, "")
                                                    for g in ordered(sec.get("Segments"))]})
        last = ln.get("LastLapTime") or {}
        lv = last.get("Value", "") or ""
        stt, nst = self.stint(num)
        iv = ln.get("IntervalToPositionAhead")
        return {
            "pos": to_int(ln.get("Position")), "laps": to_int(ln.get("NumberOfLaps")),
            "inPit": bool(ln.get("InPit")), "pitOut": bool(ln.get("PitOut")),
            "retired": bool(ln.get("Retired")), "stopped": bool(ln.get("Stopped")),
            "stops": to_int(ln.get("NumberOfPitStops")) or 0,
            "gap": ln.get("GapToLeader", "") if not isinstance(ln.get("GapToLeader"), dict) else "",
            "interval": (iv.get("Value", "") if isinstance(iv, dict) else (iv or "")),
            "sectors": secs,
            "last": {"v": lv, "c": "p" if last.get("OverallFastest") and lv else "g" if last.get("PersonalFastest") and lv else "y" if lv else ""},
            "best": ((ln.get("BestLapTime") or {}).get("Value", "")) or "",
            "tyre": {"c": (stt or {}).get("Compound", ""), "new": str((stt or {}).get("New", "")).lower() == "true",
                     "age": to_int((stt or {}).get("TotalLaps")) or 0} if stt else None,
        }

    def flush(self, force=False):
        with self.lock:
            if not self.ready or not (self.dirty or force):
                return
            self.dirty = False
            if self.pits:
                self.analyse(initial=False)
            ds = self.drivers()
            sig = json.dumps(ds)
            if sig != self.drivers_sig:
                self.drivers_sig = sig
                out({"t": "drivers", "list": [{k: d[k] for k in ("n", "tla", "name", "team", "color")} for d in ds]})
            out(self.state())


def penalty_summary(up):
    m = re.search(r"(\d+)\s*SECOND TIME PENALTY", up)
    if m:
        return m.group(1) + "s penalty"
    for key, text in (("DRIVE THROUGH", "Drive-through"), ("STOP AND GO", "Stop and go"), ("STOP/GO", "Stop and go"),
                      ("GRID PENALTY", "Grid penalty"), ("PENALTY POINT", "Penalty points"), ("TIME PENALTY", "Time penalty")):
        if key in up:
            return text
    return "Penalty"


class Conn:
    def __init__(self, feed):
        self.feed = feed
        jar = http.cookiejar.CookieJar()   # the hub's load balancer pins a connection with a cookie
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        self.tok = None
        self.closed = False

    def post(self, obj):
        req = urllib.request.Request(BASE + "?id=" + self.tok, data=(json.dumps(obj) + RS).encode(),
                                     headers=dict(UA, **{"Content-Type": "text/plain;charset=UTF-8"}), method="POST")
        with self.op.open(req, timeout=10) as r:
            r.read()

    def run(self):
        neg = json.load(self.op.open(urllib.request.Request(BASE + "/negotiate?negotiateVersion=1", data=b"",
                                                            headers=UA, method="POST"), timeout=15))
        self.tok = neg["connectionToken"]
        resp = self.op.open(urllib.request.Request(BASE + "?id=" + self.tok,
                                                   headers=dict(UA, Accept="text/event-stream")), timeout=40)
        self.post({"protocol": "json", "version": 1})
        threading.Thread(target=self.subscribe, daemon=True).start()
        threading.Thread(target=self.pinger, daemon=True).start()
        buf = []
        idle_since = None
        try:
            while True:
                raw = resp.readline()
                if not raw:
                    raise ConnectionError("stream closed")
                line = raw.decode("utf-8", "replace").rstrip("\r\n")
                if line.startswith("data:"):
                    buf.append(line[5:].removeprefix(" "))
                    continue
                if line or not buf:
                    continue
                for part in "\n".join(buf).split(RS):
                    if part.strip():
                        self.handle(json.loads(part))
                buf = []
                if self.feed.ready:
                    if self.feed.live():
                        idle_since = None
                    elif idle_since is None:
                        idle_since = time.time()
                    elif time.time() - idle_since > 600:
                        return "idle"
        finally:
            self.closed = True
            resp.close()

    def subscribe(self):
        time.sleep(0.3)
        self.post({"type": 1, "invocationId": "0", "target": "Subscribe", "arguments": [TOPICS]})

    def pinger(self):
        while not self.closed:
            time.sleep(15)
            try:
                if not self.closed:
                    self.post({"type": 6})
            except OSError as e:
                log("ping failed:", e)

    def handle(self, m):
        t = m.get("type")
        if t == 3 and isinstance(m.get("result"), dict):
            self.feed.snapshot(m["result"])
        elif t == 1 and m.get("target") == "feed":
            a = m.get("arguments") or []
            if len(a) >= 2:
                self.feed.update(a[0], a[1])
        elif t == 7:
            raise ConnectionError("server closed: " + str(m.get("error", "")))


def main():
    feed = None
    stop = threading.Event()

    def flusher():
        while not stop.is_set():
            time.sleep(0.4)
            if feed is not None:
                feed.flush()

    threading.Thread(target=flusher, daemon=True).start()
    backoff = 5
    while True:
        feed = Feed()
        why = None
        try:
            why = Conn(feed).run()
            backoff = 5
        except Exception as e:  # network trouble of any kind: report and retry
            log("connection:", e)
            out({"t": "offline", "error": str(e)[:200]})
        if why == "idle":
            # no session near: report that, then look again in a while
            feed.flush(force=True)
            time.sleep(600)
        else:
            time.sleep(backoff)
            backoff = min(120, backoff * 2)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass

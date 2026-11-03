#!/usr/bin/env python3
"""Discord voice call feed for the Island discord module (standard library only).

Talks to the running Discord client over its local RPC socket
($XDG_RUNTIME_DIR/discord-ipc-N), the same one Rich Presence uses. That API is
only open to apps you register yourself, so the first start asks Discord to
authorise your own application (Discord shows a prompt) and keeps the token in
~/.config/island/discord-token.json.

stdout, one JSON object per line:
  {"t":"status","state":"setup|offline|authorizing|ready|error","message":""}
  {"t":"call","inCall":true,"id","name","guild","kind","since","me","members":[...]}
  {"t":"voice","mute":false,"deaf":false}
  {"t":"speaking","id":"...","on":true}
  {"_event":"join|leave|voice", ...}        also goes on the island's event bus
stdin, one JSON object per line:
  {"cmd":"mute","value":true}  {"cmd":"deaf","value":false}  {"cmd":"leave"}

Test-only: ISLAND_DISCORD_API and ISLAND_DISCORD_CDN replace the web endpoints.
"""
import asyncio
import json
import os
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

HOME = os.path.expanduser("~")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
CLIENT_ID = os.environ.get("ISLAND_OPT_CLIENTID", "").strip()
CLIENT_SECRET = os.environ.get("ISLAND_OPT_CLIENTSECRET", "").strip()
REDIRECT_URI = os.environ.get("ISLAND_OPT_REDIRECTURI", "").strip() or "http://localhost"
SCOPES = ["rpc", "rpc.voice.read", "rpc.voice.write"]
API = os.environ.get("ISLAND_DISCORD_API", "https://discord.com/api/v10")
CDN = os.environ.get("ISLAND_DISCORD_CDN", "https://cdn.discordapp.com")
USER_AGENT = "DiscordBot (https://github.com/TiElixir/hypr-island, 1.0)"

TOKEN_FILE = os.path.join(HOME, ".config/island/discord-token.json")
STATE_FILE = os.path.join(RUNTIME, "island/discord-call.json")
AVATAR_DIR = os.path.join(HOME, ".cache/island/discord")

SOCKET_POLL_SEC = 5      # how often to look for Discord while it is not running
AUTH_RETRY_SEC = 600     # after a refused or failed authorisation
CALL_RESUME_SEC = 120    # a restart this soon after keeps the call's start time
CHANNEL_KINDS = {1: "dm", 2: "voice", 3: "group", 13: "stage"}


def emit(obj):
    print(json.dumps(obj, separators=(",", ":")), flush=True)


def log(*a):
    print("discordfeed:", *a, file=sys.stderr, flush=True)


class Closed(Exception):
    pass


class RpcError(Exception):
    def __init__(self, code, message):
        super().__init__(f"{message} ({code})")
        self.code = code
        self.message = message


class AuthProblem(Exception):
    """Authorisation did not work; retrying right away would only nag."""


# ---- Discord's local RPC: framed JSON over a unix socket ---------------------------

class Rpc:
    def __init__(self, reader, writer):
        self.reader = reader
        self.writer = writer
        self.pending = {}
        self.on_event = lambda evt, data: None

    async def frame(self):
        op, size = struct.unpack("<II", await self.reader.readexactly(8))
        body = await self.reader.readexactly(size) if size else b""
        return op, (json.loads(body) if body else {})

    def send(self, op, obj):
        raw = json.dumps(obj).encode()
        self.writer.write(struct.pack("<II", op, len(raw)) + raw)

    async def handshake(self):
        self.send(0, {"v": 1, "client_id": CLIENT_ID})
        await self.writer.drain()
        op, msg = await asyncio.wait_for(self.frame(), 10)
        if op == 2:
            raise AuthProblem(f"Discord refused the application ID: {msg.get('message', 'closed')}")
        if msg.get("evt") != "READY":
            raise Closed("no READY from Discord")

    async def pump(self):
        """Read until the socket closes; routes replies to request() and events to on_event."""
        try:
            while True:
                op, msg = await self.frame()
                if op == 3:
                    self.send(4, msg)
                    continue
                if op == 2:
                    raise Closed(msg.get("message", "closed"))
                fut = self.pending.pop(msg.get("nonce"), None)
                if fut is not None:
                    if fut.done():
                        continue
                    if msg.get("evt") == "ERROR":
                        data = msg.get("data") or {}
                        fut.set_exception(RpcError(data.get("code"), data.get("message", "error")))
                    else:
                        fut.set_result(msg.get("data"))
                elif msg.get("cmd") == "DISPATCH":
                    self.on_event(msg.get("evt"), msg.get("data") or {})
        finally:
            for fut in self.pending.values():
                if not fut.done():
                    fut.set_exception(Closed("connection closed"))
            self.pending.clear()

    async def request(self, cmd, args=None, evt=None, timeout=10):
        nonce = str(uuid.uuid4())
        fut = asyncio.get_running_loop().create_future()
        self.pending[nonce] = fut
        payload = {"cmd": cmd, "args": args or {}, "nonce": nonce}
        if evt:
            payload["evt"] = evt
        try:
            self.send(1, payload)
            await self.writer.drain()
            return await asyncio.wait_for(fut, timeout)
        finally:
            self.pending.pop(nonce, None)


def socket_paths():
    bases = [RUNTIME, RUNTIME + "/app/com.discordapp.Discord", RUNTIME + "/snap.discord"]
    return [f"{b}/discord-ipc-{i}" for b in bases for i in range(10) if os.path.exists(f"{b}/discord-ipc-{i}")]


# ---- OAuth: the token that lets this script use the RPC ---------------------------------

def oauth(params):
    req = urllib.request.Request(
        API + "/oauth2/token",
        urllib.parse.urlencode(params).encode(),
        {"Content-Type": "application/x-www-form-urlencoded", "User-Agent": USER_AGENT},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            tok = json.load(r)
    except urllib.error.HTTPError as e:
        try:
            body = json.load(e)
            why = body.get("error_description") or body.get("error")
        except Exception:
            why = None
        raise AuthProblem(f"Discord refused the login: {why or 'HTTP %d' % e.code}")
    return {
        "client_id": CLIENT_ID,
        "access_token": tok["access_token"],
        "refresh_token": tok.get("refresh_token", ""),
        "expires_at": time.time() + int(tok.get("expires_in", 604800)),
    }


def load_token():
    try:
        with open(TOKEN_FILE) as f:
            tok = json.load(f)
        return tok if tok.get("client_id") == CLIENT_ID and tok.get("access_token") else None
    except (OSError, ValueError):
        return None


def save_token(tok):
    os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
    tmp = TOKEN_FILE + ".part"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(tok, f)
    os.replace(tmp, TOKEN_FILE)


def forget_token():
    try:
        os.remove(TOKEN_FILE)
    except OSError:
        pass


# ---- avatars ------------------------------------------------------------------------------

def avatar_url(user):
    uid, h = str(user.get("id", "0")), user.get("avatar")
    if h:
        return f"{CDN}/avatars/{uid}/{h}.png?size=64", f"{uid}_{h}.png"
    n = (int(uid) >> 22) % 6 if uid.isdigit() else 0
    return f"{CDN}/embed/avatars/{n}.png", f"default_{n}.png"


def download(url, dest):
    os.makedirs(AVATAR_DIR, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=10) as r:
        data = r.read(2_000_000)
    with open(dest + ".part", "wb") as f:
        f.write(data)
    os.replace(dest + ".part", dest)


def prune_avatars():
    try:
        cutoff = time.time() - 30 * 86400
        for n in os.listdir(AVATAR_DIR):
            p = os.path.join(AVATAR_DIR, n)
            if os.path.getmtime(p) < cutoff:
                os.remove(p)
    except OSError:
        pass


# ---- one connection to Discord ---------------------------------------------------------------

class Session:
    def __init__(self, rpc):
        self.rpc = rpc
        self.me = ""
        self.mute = None
        self.deaf = None
        self.channel = None        # RPC channel object, None when not in a call
        self.members = {}          # user id -> dict, in join order
        self.guild = ""
        self.since = 0.0
        self.subscribed = None     # channel id with per-channel subscriptions
        self.flush_handle = None
        self.fetching = set()
        self.lock = asyncio.Lock()
        self.tasks = set()
        rpc.on_event = self.on_event

    def spawn(self, coro):
        t = asyncio.create_task(coro)
        self.tasks.add(t)
        t.add_done_callback(self.tasks.discard)
        return t

    # -- startup --
    async def authenticate(self):
        tok = load_token()
        if tok:
            try:
                if tok["expires_at"] < time.time() + 300:
                    tok = await asyncio.to_thread(oauth, {
                        "grant_type": "refresh_token", "refresh_token": tok["refresh_token"],
                        "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET})
                    save_token(tok)
                return await self.rpc.request("AUTHENTICATE", {"access_token": tok["access_token"]})
            except (AuthProblem, RpcError) as e:
                log("saved token no longer works:", e)
                forget_token()
        set_status("authorizing", "Approve the prompt in Discord")
        try:
            data = await self.rpc.request("AUTHORIZE", {"client_id": CLIENT_ID, "scopes": SCOPES}, timeout=300)
        except RpcError as e:
            raise AuthProblem(f"Discord did not authorise Island: {e.message}")
        except asyncio.TimeoutError:
            raise AuthProblem("Nobody approved the prompt in Discord")
        tok = await asyncio.to_thread(oauth, {
            "grant_type": "authorization_code", "code": data["code"], "redirect_uri": REDIRECT_URI,
            "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET})
        save_token(tok)
        try:
            return await self.rpc.request("AUTHENTICATE", {"access_token": tok["access_token"]})
        except RpcError as e:
            raise AuthProblem(f"Discord rejected the new login: {e.message}")

    async def start(self):
        auth = await self.authenticate()
        self.me = str(((auth or {}).get("user") or {}).get("id", ""))
        set_status("ready")
        await self.rpc.request("SUBSCRIBE", evt="VOICE_CHANNEL_SELECT")
        await self.rpc.request("SUBSCRIBE", evt="VOICE_SETTINGS_UPDATE")
        self.voice_settings(await self.rpc.request("GET_VOICE_SETTINGS"))
        await self.sync(None, check=False, initial=True)
        self.spawn(self.heartbeat())

    # -- events --
    def on_event(self, evt, data):
        if evt == "VOICE_CHANNEL_SELECT":
            self.spawn(self.sync(data.get("channel_id")))
        elif evt == "VOICE_SETTINGS_UPDATE":
            self.voice_settings(data)
        elif evt in ("VOICE_STATE_CREATE", "VOICE_STATE_UPDATE"):
            self.put_member(data)
            self.dirty()
        elif evt == "VOICE_STATE_DELETE":
            self.members.pop(str((data.get("user") or {}).get("id", "")), None)
            self.dirty()
        elif evt in ("SPEAKING_START", "SPEAKING_STOP"):
            uid = str(data.get("user_id", ""))
            if uid in self.members:
                self.members[uid]["speaking"] = evt == "SPEAKING_START"
                emit({"t": "speaking", "id": uid, "on": evt == "SPEAKING_START"})

    def voice_settings(self, data):
        mute, deaf = bool((data or {}).get("mute")), bool((data or {}).get("deaf"))
        if (mute, deaf) == (self.mute, self.deaf):
            return
        first = self.mute is None
        self.mute, self.deaf = mute, deaf
        emit({"t": "voice", "mute": mute, "deaf": deaf})
        if not first:
            emit({"_event": "voice", "mute": mute, "deaf": deaf})

    # -- the call --
    async def sync(self, expect, check=True, initial=False):
        """Reads the selected voice channel. After a VOICE_CHANNEL_SELECT it may
        lag behind the event for a moment, so it is read again until it agrees."""
        async with self.lock:
            ch = None
            for _ in range(5):
                ch = await self.rpc.request("GET_SELECTED_VOICE_CHANNEL")
                if not check or (ch.get("id") if ch else None) == expect:
                    break
                await asyncio.sleep(0.4)
            await self.apply(ch, initial)

    async def apply(self, ch, initial=False):
        new = str(ch["id"]) if ch else None
        old = str(self.channel["id"]) if self.channel else None
        if new != old:
            await self.unsubscribe()
            if old:
                self.left()
            if not new:
                self.channel = None
                self.members = {}
                emit({"t": "call", "inCall": False})
                return
            self.since = self.resume(new)
            self.guild = ""
            if ch.get("guild_id"):
                try:
                    self.guild = str((await self.rpc.request("GET_GUILD", {"guild_id": ch["guild_id"]}) or {}).get("name", ""))
                except (RpcError, asyncio.TimeoutError):
                    pass
        if ch is None:
            return
        self.channel = ch
        before, self.members = self.members, {}
        for vs in ch.get("voice_states") or []:
            uid = str((vs.get("user") or {}).get("id", ""))
            if uid in before:
                self.members[uid] = before[uid]
            self.put_member(vs)
        if new != old:
            self.save_state()
            if not initial:   # a call that was already going when the script started is not a join
                emit({"_event": "join", "channel": self.label(), "guild": self.guild, "kind": self.kind()})
            await self.subscribe(new)
        self.dirty()

    async def subscribe(self, cid):
        self.subscribed = cid
        for evt in ("VOICE_STATE_CREATE", "VOICE_STATE_UPDATE", "VOICE_STATE_DELETE", "SPEAKING_START", "SPEAKING_STOP"):
            try:
                await self.rpc.request("SUBSCRIBE", {"channel_id": cid}, evt=evt)
            except (RpcError, asyncio.TimeoutError) as e:
                log("cannot subscribe to", evt, e)

    async def unsubscribe(self):
        cid, self.subscribed = self.subscribed, None
        if cid is None:
            return
        for evt in ("VOICE_STATE_CREATE", "VOICE_STATE_UPDATE", "VOICE_STATE_DELETE", "SPEAKING_START", "SPEAKING_STOP"):
            try:
                await self.rpc.request("UNSUBSCRIBE", {"channel_id": cid}, evt=evt)
            except (RpcError, asyncio.TimeoutError, Closed):
                pass

    def left(self):
        emit({"_event": "leave", "channel": self.label(), "guild": self.guild,
              "seconds": int(max(0, time.time() - self.since))})
        try:
            os.remove(STATE_FILE)
        except OSError:
            pass

    def kind(self):
        return CHANNEL_KINDS.get((self.channel or {}).get("type"), "voice")

    def label(self):
        name = str((self.channel or {}).get("name") or "")
        if name:
            return name
        others = [m["name"] for uid, m in self.members.items() if uid != self.me]
        return ", ".join(others[:3]) + ("…" if len(others) > 3 else "") if others else "Voice call"

    def put_member(self, vs):
        user = vs.get("user") or {}
        uid = str(user.get("id", ""))
        if not uid:
            return
        state = vs.get("voice_state") or {}
        old = self.members.get(uid, {})
        url, fname = avatar_url(user)
        path = os.path.join(AVATAR_DIR, fname)
        self.members[uid] = {
            "id": uid,
            "name": vs.get("nick") or user.get("global_name") or user.get("username") or uid,
            "avatar": path if os.path.exists(path) else "",
            "muted": bool(state.get("mute") or state.get("self_mute")),
            "deafened": bool(state.get("deaf") or state.get("self_deaf")),
            "speaking": bool(old.get("speaking")),
        }
        if not self.members[uid]["avatar"] and path not in self.fetching:
            self.fetching.add(path)
            self.spawn(self.fetch_avatar(uid, url, path))

    async def fetch_avatar(self, uid, url, path):
        try:
            await asyncio.to_thread(download, url, path)
            if uid in self.members:
                self.members[uid]["avatar"] = path
                self.dirty()
        except Exception as e:
            log("avatar", uid, e)
        finally:
            self.fetching.discard(path)

    # -- output --
    def dirty(self):
        """Coalesces a burst of changes (a full channel joining) into one message."""
        if self.flush_handle is None:
            self.flush_handle = asyncio.get_running_loop().call_later(0.05, self.flush)

    def flush(self):
        self.flush_handle = None
        if self.channel is None:
            return
        ordered = sorted(self.members.values(), key=lambda m: m["id"] != self.me)
        emit({"t": "call", "inCall": True, "id": str(self.channel["id"]), "name": self.label(), "guild": self.guild,
              "kind": self.kind(), "since": self.since, "me": self.me, "members": ordered})

    # -- the start time survives a restart of the island --
    def resume(self, cid):
        try:
            with open(STATE_FILE) as f:
                s = json.load(f)
            if s.get("channel") == cid and time.time() - float(s.get("seen", 0)) < CALL_RESUME_SEC:
                return float(s["since"])
        except (OSError, ValueError, KeyError):
            pass
        return time.time()

    def save_state(self):
        if self.channel is None:
            return
        try:
            os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
            with open(STATE_FILE, "w") as f:
                json.dump({"channel": str(self.channel["id"]), "since": self.since, "seen": time.time()}, f)
        except OSError:
            pass

    async def heartbeat(self):
        while True:
            await asyncio.sleep(30)
            self.save_state()

    # -- commands from the island --
    async def command(self, msg):
        cmd, value = msg.get("cmd"), bool(msg.get("value"))
        try:
            if cmd in ("mute", "deaf"):
                self.voice_settings(await self.rpc.request("SET_VOICE_SETTINGS", {cmd: value}))
            elif cmd == "leave":
                await self.rpc.request("SELECT_VOICE_CHANNEL", {"channel_id": None, "force": True})
        except (RpcError, asyncio.TimeoutError, Closed) as e:
            log(cmd, "failed:", e)

    def close(self):
        for t in list(self.tasks):
            t.cancel()
        if self.flush_handle is not None:
            self.flush_handle.cancel()
        if self.channel is not None:
            self.left()
            emit({"t": "call", "inCall": False})


# ---- main loop ------------------------------------------------------------------------------------

_status = [None]


def set_status(state, message=""):
    if _status[0] != (state, message):
        _status[0] = (state, message)
        emit({"t": "status", "state": state, "message": message})


current = [None]


async def read_commands():
    reader = asyncio.StreamReader()
    await asyncio.get_running_loop().connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    while True:
        line = await reader.readline()
        if not line:
            # The island closed our stdin: it is gone or stopped this module.
            os._exit(0)
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if current[0] is not None and isinstance(msg, dict):
            current[0].spawn(current[0].command(msg))


async def connect():
    for path in socket_paths():
        try:
            return await asyncio.open_unix_connection(path)
        except OSError:
            continue
    return None


async def run_once():
    conn = await connect()
    if conn is None:
        set_status("offline")
        return
    rpc = Rpc(*conn)
    sess = None
    pump = None
    try:
        await rpc.handshake()
        pump = asyncio.create_task(rpc.pump())
        sess = Session(rpc)
        starting = asyncio.create_task(sess.start())
        await asyncio.wait({starting, pump}, return_when=asyncio.FIRST_COMPLETED)
        if starting.done():
            starting.result()
            current[0] = sess
            await pump
        else:
            starting.cancel()
            await pump
    finally:
        current[0] = None
        if sess is not None:
            sess.close()
        if pump is not None:
            pump.cancel()
        rpc.writer.close()


async def main():
    if not CLIENT_ID or not CLIENT_SECRET:
        set_status("setup", "Add the application ID and client secret in Settings")
        await asyncio.Event().wait()
    commands = asyncio.create_task(read_commands())   # keep a reference: tasks nobody holds get collected
    prune_avatars()
    while True:
        wait = SOCKET_POLL_SEC
        try:
            await run_once()
        except AuthProblem as e:
            set_status("error", str(e))
            wait = AUTH_RETRY_SEC
        except (OSError, Closed, RpcError, asyncio.IncompleteReadError, asyncio.TimeoutError) as e:
            log("connection lost:", e)
            set_status("offline")
        await asyncio.sleep(wait)
    await commands


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass

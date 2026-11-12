#!/usr/bin/env python3
"""Browser control panel for the HERO pan/tilt mount.

The HERO has no network of its own, so this runs on the machine the board is
plugged into: it serves a slider UI and relays commands down the USB serial
link to the ServoControl sketch.

    python3 scripts/servo_web.py [--port /dev/cu.usbserial-XXXX]

Then open http://localhost:8090
"""

import argparse
import glob
import http.server
import os
import termios
import threading
import time
import urllib.parse

import serial

# Measured on the mount: tilt binds around 150, so its ceiling sits 5 degrees
# below that. Pan reached both ends without binding. Keep in step with the
# matching constants in ServoControl/ServoControl.ino.
LIMITS = {"p": (10, 170), "t": (10, 145)}

lock = threading.Lock()
board = None
board_port = None

PAGE = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TrainCam Servo Jog</title>
<style>
  body { background:#111; color:#eee; font:16px system-ui; margin:0; padding:2rem; }
  h1 { font-size:1.2rem; font-weight:600; }
  .axis { margin:2rem 0; }
  label { display:flex; justify-content:space-between; margin-bottom:.5rem; }
  .val { font-variant-numeric:tabular-nums; color:#6cf; }
  input[type=range] { width:100%; height:2.5rem; }
  button { background:#333; color:#eee; border:1px solid #555; border-radius:6px;
           padding:.6rem 1.2rem; font-size:1rem; margin-right:.5rem; }
  #status { color:#888; font-size:.85rem; margin-top:1.5rem; }
</style>
</head>
<body>
<h1>TrainCam pan/tilt jog</h1>

<div class="axis">
  <label>PAN (D9) <span class="val" id="pval">90</span></label>
  <input type="range" id="pan" min="PMIN" max="PMAX" value="90">
</div>

<div class="axis">
  <label>TILT (D10) <span class="val" id="tval">90</span></label>
  <input type="range" id="tilt" min="TMIN" max="TMAX" value="90">
</div>

<button onclick="center()">Center both</button>
<div id="status">ready</div>

<script>
const status = document.getElementById('status');

function bind(id, axis, out) {
  const el = document.getElementById(id);
  const lbl = document.getElementById(out);
  let pending = null, busy = false;

  async function flush() {
    if (busy || pending === null) return;
    busy = true;
    const angle = pending; pending = null;
    try {
      const r = await fetch(`/set?axis=${axis}&angle=${angle}`);
      status.textContent = await r.text();
    } catch (e) {
      status.textContent = 'error: ' + e;
    }
    busy = false;
    flush();
  }

  el.addEventListener('input', () => {
    lbl.textContent = el.value;
    pending = el.value;
    flush();
  });
}

bind('pan', 'p', 'pval');
bind('tilt', 't', 'tval');

async function center() {
  const r = await fetch('/center');
  status.textContent = await r.text();
  document.getElementById('pan').value = 90;
  document.getElementById('tilt').value = 90;
  document.getElementById('pval').textContent = '90';
  document.getElementById('tval').textContent = '90';
}
</script>
</body>
</html>
"""


def connect(port=None):
    """Open the serial port, waiting out the board's reset-on-open."""
    global board, board_port

    if board is not None:
        try:
            board.close()
        except Exception:
            pass
        board = None

    if port:
        board_port = port
    if not board_port or not os.path.exists(board_port):
        board_port = autodetect()

    board = serial.Serial(board_port, 115200, timeout=1)
    time.sleep(2)  # board resets when the port opens
    board.reset_input_buffer()
    return board_port


def _exchange(cmd):
    board.reset_input_buffer()
    board.write(cmd.encode())
    board.flush()
    deadline = time.time() + 3
    while time.time() < deadline:
        line = board.readline().decode("utf-8", "replace").strip()
        if line.startswith("P:"):
            return line
    return "no response from board"


def send(cmd):
    """Write one command and return the board's position report.

    Unplugging the board invalidates the file descriptor, so on an I/O error
    reopen the port once and retry. Note the reopen resets the board, which
    returns both servos to center.
    """
    with lock:
        try:
            return _exchange(cmd)
        except (serial.SerialException, termios.error, OSError):
            pass

        try:
            connect()
        except Exception as e:
            return f"board disconnected ({e})"

        try:
            return f"{_exchange(cmd)} (reconnected, servos re-centered)"
        except Exception as e:
            return f"board disconnected ({e})"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)

        if url.path == "/":
            body = (PAGE
                    .replace("PMIN", str(LIMITS["p"][0]))
                    .replace("PMAX", str(LIMITS["p"][1]))
                    .replace("TMIN", str(LIMITS["t"][0]))
                    .replace("TMAX", str(LIMITS["t"][1])))
            self.respond(body, "text/html")
        elif url.path == "/set":
            axis = query.get("axis", ["p"])[0]
            angle = int(query.get("angle", ["90"])[0])
            if axis not in LIMITS:
                self.respond("bad axis", "text/plain", code=400)
                return
            lo, hi = LIMITS[axis]
            angle = max(lo, min(hi, angle))
            self.respond(send(f"{axis}{angle}\n"), "text/plain")
        elif url.path == "/center":
            self.respond(send("c\n"), "text/plain")
        else:
            self.respond("not found", "text/plain", code=404)

    def respond(self, body, ctype, code=200):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass  # keep the console quiet


def autodetect():
    ports = glob.glob("/dev/cu.usbserial-*") + glob.glob("/dev/ttyUSB*")
    if not ports:
        raise RuntimeError("no USB serial board found")
    return ports[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", help="serial port (autodetected if omitted)")
    ap.add_argument("--http-port", type=int, default=8090)
    args = ap.parse_args()

    try:
        port = connect(args.port)
    except RuntimeError as e:
        raise SystemExit(f"{e}. Plug the board in, or pass --port explicitly.")

    print(f"Board:  {port}")
    print(f"Open:   http://localhost:{args.http_port}")
    print("Ctrl-C to quit.")
    http.server.HTTPServer(("127.0.0.1", args.http_port), Handler).serve_forever()


if __name__ == "__main__":
    main()

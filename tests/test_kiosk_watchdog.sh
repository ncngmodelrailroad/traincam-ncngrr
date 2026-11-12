#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from functools import partial
import http.client
from http.server import ThreadingHTTPServer
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from unittest.mock import patch

path = Path("ansible/roles/trainview/files/kiosk-server.py")
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("kiosk_server", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with patch.object(module.time, "monotonic", return_value=0) as clock:
    health = module.Health()
    assert health.check(True, "10") is None
    clock.return_value = 179
    assert health.check(True, "10") is None
    clock.return_value = 180
    assert health.check(True, "10") == ["1", "usb"], "an unloaded page must recover"
    assert health.check(True, "11") is None
    for now in range(185, 601, 5):
        clock.return_value = now
        for output in module.OUTPUTS:
            health.heartbeat(output)
        assert health.check(True, "11") is None, "responsive offline pages are healthy"
    clock.return_value = 645
    health.heartbeat("1")
    assert health.check(True, "11") == ["usb"], "each display must be watched"
    clock.return_value = 650
    assert health.check(False, "0") is None
    clock.return_value = 1000
    assert health.check(False, "0") is None, "do not restart an intentionally stopped kiosk"

    clock.return_value = 0
    health = module.Health()
    health.check(True, "10")
    for attempt in range(1, 4):
        clock.return_value = attempt * 180
        assert health.check(True, "10") == ["1", "usb"]
    clock.return_value = 720
    assert health.check(True, "10") is None
    assert health.limited
    clock.return_value = 1080
    assert health.check(True, "10") == ["1", "usb"], "retry only after the budget window"

    clock.return_value = 0
    health = module.Health()
    health.check(True, "10")
    clock.return_value = 180
    stop = module.threading.Event()
    result = subprocess.CompletedProcess([], 0, "ActiveState=active\nMainPID=10\n")
    with patch.object(stop, "wait", side_effect=[False, True]), \
            patch.object(module.subprocess, "run", return_value=result) as run:
        module.monitor(health, stop)
    assert run.call_args_list[1].args[0] == [
        "systemctl", "--user", "restart", "traincam-kiosk.service"
    ], "recovery must only restart the browser service"

with tempfile.TemporaryDirectory() as directory:
    Path(directory, "index.html").write_text("local viewer", encoding="utf-8")
    handler = partial(module.Handler, directory=directory)
    with ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
        server.health = module.Health()
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def request(path, method="POST", origin=None, body=None):
            connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
            headers = {} if origin is None else {"Origin": origin}
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            result = response.status, response.read()
            connection.close()
            return result
        origin = f"http://localhost:{server.server_port}"
        assert request("/_kiosk/heartbeat/1", origin=origin)[0] == 204
        assert server.health.seen["1"] is not None
        assert request("/_kiosk/heartbeat/usb", origin="https://unrelated.invalid")[0] == 403
        assert server.health.seen["usb"] is None
        assert request("/_kiosk/heartbeat/other", origin=origin)[0] == 404
        assert request("/_kiosk/heartbeat/usb", origin=origin, body="bad")[0] == 400
        assert request("/", "GET") == (200, b"local viewer")
        assert request("/_kiosk/health", "GET")[0] == 200
        server.shutdown()
        thread.join()
print("PASS: startup, offline operation, per-display stalls, restart budget and HTTP guard")
PY

node - <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('ansible/roles/trainview/files/visitor/kiosk.js', 'utf8');
let now = 0;
const windows = { pi: {}, esp32: {}, usb: {}, visitor: {} };
const frames = Object.fromEntries(Object.keys(windows).map(id => [
  id, { contentWindow: windows[id], dataset: { src: `/${id}.html` }, src: '' },
]));
const feeds = Object.fromEntries(['pi', 'esp32', 'usb', 'visitor'].map(id => [
  id, { hidden: false, remove() { this.removed = true; }, querySelector: () => frames[id] },
]));
const handlers = {}, intervals = [], requests = [];
const context = {
  document: { getElementById: id => feeds[id] },
  location: { origin: 'http://localhost:8081', search: '?output=1' },
  window: { addEventListener: (event, callback) => handlers[event] = callback },
  performance: { now: () => now }, URLSearchParams, AbortSignal, console,
  setInterval: callback => intervals.push(callback),
  fetch: async (url, options) => {
    requests.push({ url, options });
    return { ok: false };
  },
};
vm.runInNewContext(source, context);
const flush = () => new Promise(resolve => setImmediate(resolve));
const beat = (source, live = false) => handlers.message({
  origin: context.location.origin, data: { type: 'traincam-viewer-heartbeat', live }, source,
});
(async () => {
  await flush();
  const tick = intervals[1];
  const posts = () => requests.filter(request => request.options.method === 'POST');
  tick();
  assert.equal(posts().length, 0, 'no heartbeat until a viewer has loaded');
  assert.equal(feeds.visitor.hidden, false);
  assert.equal(feeds.usb.removed, true, 'first screen must not duplicate the USB stream');
  for (const id of ['esp32', 'pi', 'visitor']) {
    assert.equal(frames[id].src, frames[id].dataset.src, `${id} must load on the train screen`);
  }
  assert.equal(frames.usb.src, '', 'an excluded camera must never start loading');
  beat(windows.visitor);
  tick();
  assert.equal(posts().length, 1, 'an offline but responsive viewer is healthy');
  assert.equal(posts()[0].url, '/_kiosk/heartbeat/1');
  now = 16000;
  beat(windows.pi);
  tick();
  assert.equal(posts().length, 1, 'a hidden viewer cannot mask a stuck visible viewer');
  handlers.message({
    origin: 'https://unrelated.invalid', source: windows.pi,
    data: { type: 'traincam-viewer-heartbeat' },
  });
  beat({});
  tick();
  assert.equal(posts().length, 1, 'reject spoofed heartbeats');
  beat(windows.visitor);
  tick();
  assert.equal(posts().length, 2, 'heartbeats resume after viewer recovery');
  for (now = 17000; now <= 29000; now += 2000) {
    beat(windows.pi, true);
    beat(windows.visitor);
  }
  assert.equal(feeds.pi.hidden, false, 'fresh video must become visible after ten stable seconds');
  assert.equal(feeds.visitor.hidden, true);
  beat(windows.pi, false);
  assert.equal(feeds.visitor.hidden, false, 'HTTP reachability cannot suppress fallback');
  for (now = 32000; now <= 44000; now += 2000) beat(windows.pi, true);
  now = 51000;
  intervals[0]();
  assert.equal(feeds.visitor.hidden, false, 'lost heartbeat must trigger fallback');
  for (now = 52000; now <= 64000; now += 2000) {
    beat(windows.pi, true);
    beat(windows.esp32, true);
  }
  assert.equal(feeds.esp32.hidden, false, 'ESP32 must win when both train cameras have fresh video');
  assert.equal(feeds.pi.hidden, true);
  beat(windows.esp32, false);
  assert.equal(feeds.pi.hidden, false, 'a healthy Pi remains a fallback when ESP32 is lost');
  for (now = 68000; now <= 80000; now += 2000) {
    beat(windows.pi, true);
    beat(windows.esp32, true);
  }
  assert.equal(feeds.esp32.hidden, false, 'ESP32 must return after ten stable seconds');
  console.log('PASS: visible-viewer heartbeat, offline operation, stalling and origin checks');
})().catch(error => { console.error(error); process.exitCode = 1; });
JS

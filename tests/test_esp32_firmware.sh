#!/usr/bin/env bash
# Guards the ESP32 backup camera's unattended-operation properties.
#
# Hardware recovery uses source checks; the frame limiter also runs on the host
# with a changing FPS value to reproduce concurrent control updates.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INO="$ROOT/CameraWebServer/CameraWebServer.ino"
HTTPD="$ROOT/CameraWebServer/app_httpd.cpp"
pass=0
fail=0

check() {
  if [[ "$2" == "$3" ]]; then
    echo "✓ $1"
    pass=$((pass + 1))
  else
    echo "✗ $1: expected '$3', got '$2'"
    fail=$((fail + 1))
  fi
}

echo "==> Testing ESP32 firmware hardening"

# These checks are about code, so strip whole-line comments first. Written the
# naive way, this file failed itself twice: the prose describing the old
# `if (Serial)` bug matched the grep looking for that bug.
CODE="$(mktemp)"
trap 'rm -f "$CODE"' EXIT
sed -E 's#^[[:space:]]*//.*$##' "$INO" > "$CODE"

# 1. THE ONE THAT MATTERS. The stock sketch waits for WiFi with
#    `while (WiFi.status() != WL_CONNECTED) delay(500);` - no timeout. If the AP
#    is not up when the board boots, which is near certain at a fair where
#    everything powers on at once, setup() never returns and the camera is gone
#    for the day. Verified on hardware with a nonexistent SSID: the board now
#    prints "WiFi did not come up; rebooting to retry" and soft-resets on a ~31s
#    cycle (rst:0xc RTC_SW_CPU_RST) instead of hanging.
#
# A wait loop is fine; an ESCAPELESS one is the defect. So require that every
# wait loop lives in connectWiFi(), which is the only place with a timeout.
waits=$(grep -Ec 'while[[:space:]]*\([[:space:]]*WiFi\.status\(\)[[:space:]]*!=[[:space:]]*WL_CONNECTED[[:space:]]*\)' "$CODE" || true)
check "exactly one wait-for-WiFi loop" "$waits" "1"

# ...and that the loop it sits in can actually exit. Extract connectWiFi's body
# and require a bail-out inside it.
body=$(awk '/^static bool connectWiFi/,/^}/' "$CODE")
if grep -Eq 'while[[:space:]]*\([[:space:]]*WiFi\.status' <<<"$body" \
   && grep -q 'return false' <<<"$body"; then
  got=bounded
else
  got=unbounded
fi
check "the wait loop has a timeout escape" "$got" "bounded"

for token in "WIFI_CONNECT_TIMEOUT_MS" "connectWiFi"; do
  if grep -qF "$token" "$INO"; then got=yes; else got=no; fi
  check "bounded connect: $token present" "$got" "yes"
done

# Overflow-safe elapsed-time comparison. `millis() + timeout` wraps after 49
# days and would then never expire; `millis() - start > timeout` is correct
# across the wrap. A show is short, but an unattended spare may not be.
if grep -Eq 'millis\(\)[[:space:]]*-[[:space:]]*start[[:space:]]*[<>]' "$INO"; then
  got=yes
else
  got=no
fi
check "connect timeout is wrap-safe" "$got" "yes"

# 2. NO RECOVERY FROM A DROPPED LINK. loop() was an empty delay(10000): nothing
#    noticed or recovered a lost association. A moving train on a busy fair
#    network will drop.
for token in "WIFI_GRACE_MS" "lastConnectedMs" "ESP.restart"; do
  if grep -qF "$token" "$INO"; then got=yes; else got=no; fi
  check "link-loss recovery: $token present" "$got" "yes"
done

# 3. NO WATCHDOG, where the Pi runs RuntimeWatchdogSec=14. Verified on hardware
#    by hanging loop() deliberately: "task_wdt: Task watchdog got triggered ...
#    - loopTask (CPU 1)" then panic and clean reboot, so the loop task really is
#    subscribed. esp_task_wdt_reset() in loop() is what keeps it fed - drop that
#    line and the board reboots every WDT_TIMEOUT_MS instead.
for token in "esp_task_wdt_reconfigure" "esp_task_wdt_add" "esp_task_wdt_reset"; do
  if grep -qF "$token" "$INO"; then got=yes; else got=no; fi
  check "task watchdog: $token present" "$got" "yes"
done

# Serial.begin must come before anything that gates on `if (Serial)`. The stock
# sketch tested `if (Serial)` BEFORE begin, so on a native-USB board it could
# skip serial init entirely - and the camera-init failure message then printed
# nowhere. On a headless board that is the only diagnostic channel there is,
# and it is how this session's "zero serial output" scare started.
begin_line=$(grep -n "Serial.begin" "$CODE" | head -1 | cut -d: -f1 || true)
# No match is the PASSING case here, and grep exits 1 on no match, which under
# `set -o pipefail` would abort the run and look like a pass.
gate_line=$(grep -n "if[[:space:]]*([[:space:]]*Serial[[:space:]]*)" "$CODE" | head -1 | cut -d: -f1 || true)
if [[ -z "$gate_line" || "$begin_line" -lt "$gate_line" ]]; then
  got=ok
else
  got="gated at line $gate_line before begin at $begin_line"
fi
check "Serial.begin is not gated on itself" "$got" "ok"

# The httpd keeps one socket per connected client. Every kiosk refresh, phone
# lock and walk-out-of-range strands one, and the default LRU purge is off, so
# the server stops accepting once the table fills. This is the ESP32's version
# of the WHEP session leak fixed on the Pi in b52d740.
if grep -Eq 'lru_purge_enable[[:space:]]*=[[:space:]]*true' "$HTTPD"; then
  got=yes
else
  got=no
fi
check "httpd purges stale sockets" "$got" "yes"

# /status is the only way to tell a healthy board from one that has been
# rebooting all afternoon - boots and wifi_restarts live in RTC memory and
# survive the soft resets above.
for token in "wifi_restarts" "min_heap" "uptime_s" "battery_mv" "temperature_c" "sensor_pid"; do
  if grep -qF "$token" "$HTTPD"; then got=yes; else got=no; fi
  check "/status reports $token" "$got" "yes"
done

for token in "analogReadMilliVolts" "BATTERY_CALIBRATION" "16.0f) * 2.0f" \
             "TELEMETRY_INTERVAL_MS" "temperature_sensor_get_celsius"; do
  if grep -qF "$token" "$INO"; then got=yes; else got=no; fi
  check "battery divider readout: $token present" "$got" "yes"
done

if grep -qF "readBatteryMillivolts()" "$HTTPD"; then got=no; else got=yes; fi
check "/status uses cached telemetry" "$got" "yes"

# Low-light tuning has to happen live at the layout, not through flash cycles.
for knob in gainceiling aec2 ae_level aec_value agc_gain awb wb_mode lenc; do
  if grep -qF "{\"$knob\"," "$HTTPD"; then got=yes; else got=no; fi
  check "/control accepts $knob" "$got" "yes"
done

if grep -qF '"fps", val' "$HTTPD" && grep -qF "static std::atomic<int> maxFps{20};" "$HTTPD"; then got=yes; else got=no; fi
check "/control accepts fps, default cap 20" "$got" "yes"
if grep -qF '"tx_power", val' "$HTTPD" && grep -qF "esp_wifi_set_max_tx_power(52);" "$INO" && grep -qF "setCpuFrequencyMhz(160);" "$INO"; then got=yes; else got=no; fi
check "cool defaults 13dBm/160MHz, tunable via /control" "$got" "yes"

if grep -qF "config.jpeg_quality = 9;" "$CODE"; then got=yes; else got=no; fi
check "PSRAM JPEG quality defaults to 9" "$got" "yes"
if grep -qF "s->id.PID == OV2640_PID &&" "$CODE" \
   && grep -qF "s->set_gainceiling(s, GAINCEILING_4X) != 0" "$CODE"; then got=yes; else got=no; fi
check "OV2640 uses a checked 4x automatic gain ceiling" "$got" "yes"

if grep -qF "config.xclk_freq_hz = 20000000;" "$CODE"; then got=yes; else got=no; fi
check "camera uses 20MHz XCLK to avoid measured XGA color stripes" "$got" "yes"

if grep -qFx "  CONFIG_LWIP_TCP_TMR_INTERVAL=25" "$ROOT/platformio.ini"; then got=yes; else got=no; fi
check "PlatformIO uses the measured 25ms TCP recovery timer" "$got" "yes"

python3 - "$HTTPD" <<'PY'
from pathlib import Path
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).read_text()
limiter = source.split("  while (true) {\n", 1)[1].split(
    "    lastFrameUs = esp_timer_get_time();", 1
)[0]
program = r"""
#include <cassert>
#include <cstdint>
struct Fps {
  int value, next, reads;
  int load() { ++reads; int result = value; value = next; return result; }
  operator int() { return load(); }
};
int64_t waitedMs = -1;
int64_t esp_timer_get_time() { return 1000; }
void vTaskDelay(int64_t ms) { waitedMs = ms; }
#define pdMS_TO_TICKS(ms) (ms)
void limit(Fps &maxFps, int64_t lastFrameUs) {
""" + limiter + r"""
}
int main() {
  Fps disabling{20, 0, 0};
  limit(disabling, 0);
  assert(disabling.reads == 1 && waitedMs == 49);
  waitedMs = -1;
  Fps enabling{0, 20, 0};
  limit(enabling, 0);
  assert(enabling.reads == 1 && waitedMs == -1);
}
"""
with tempfile.TemporaryDirectory(prefix="traincam-fps-") as directory:
    path = Path(directory)
    (path / "fps.cpp").write_text(program)
    subprocess.run(["c++", "-std=c++11", "-Wall", "-Wextra", "-Werror",
                    str(path / "fps.cpp"), "-o", str(path / "fps")], check=True)
    subprocess.run([str(path / "fps")], check=True)
print("PASS: FPS changes use one snapshot without dividing by a new zero value")
PY

echo
if [[ "$fail" -gt 0 ]]; then
  echo "==> ESP32 firmware tests FAILED ($fail failed, $pass passed)"
  exit 1
fi
echo "==> ESP32 firmware tests passed ($pass checks)"

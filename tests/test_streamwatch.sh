#!/usr/bin/env bash
# Test the stream watchdog logic in streamwatch.sh.j2
#
# It restarts the camera service on an unattended device, so what matters is
# that it restarts on a real freeze and never on a stream that is flowing,
# starting up, or already restarting.
set -uo pipefail

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "✓ $name"
    PASS=$((PASS + 1))
  else
    echo "✗ $name: expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../ansible/roles/traincam/templates/streamwatch.sh.j2"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

sed -e 's/{{ traincam_service_name }}/traincam/g' \
    -e 's/{{ traincam_streamwatch_threshold }}/3/g' \
    -e 's/{{ traincam_streamwatch_interval_sec }}/10/g' \
    "$TEMPLATE" >"$TMP/streamwatch.sh"

if grep -q '{{' "$TMP/streamwatch.sh"; then
  echo "✗ unrendered Jinja left in template"
  FAIL=$((FAIL + 1))
fi

cat >"$TMP/fake-restart" <<EOF
#!/usr/bin/env bash
echo restart >>"$TMP/restarts"
EOF
cat >"$TMP/fake-log" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$TMP/log"
EOF
cat >"$TMP/fake-sample" <<EOF
#!/usr/bin/env bash
cat "$TMP/sample"
EOF
chmod +x "$TMP"/fake-*

# $1 = what the sampler reports: "<pid> <bytes>", or "" for no ffmpeg.
run() {
  printf '%s' "$1" >"$TMP/sample"
  TRAINCAM_STREAMWATCH_STATE="$TMP/state" \
  TRAINCAM_STREAMWATCH_SAMPLE_CMD="$TMP/fake-sample" \
  TRAINCAM_STREAMWATCH_RESTART_CMD="$TMP/fake-restart" \
  TRAINCAM_STREAMWATCH_LOG_CMD="$TMP/fake-log" \
    bash "$TMP/streamwatch.sh"
}
restarts() { if [[ -f "$TMP/restarts" ]]; then wc -l <"$TMP/restarts" | tr -d ' '; else echo 0; fi; }
reset() { rm -f "$TMP/state" "$TMP/restarts" "$TMP/log"; }

# Flowing stream never restarts.
reset
for b in 100 200 300 400 500; do run "42 $b"; done
check "flowing stream is left alone" "0" "$(restarts)"

# A freeze restarts after exactly THRESHOLD stalled samples.
reset
run "42 1000"; run "42 1000"; run "42 1000"
check "two stalled samples are tolerated" "0" "$(restarts)"
run "42 1000"
check "third stalled sample restarts" "1" "$(restarts)"
grep -q "for 30s with ffmpeg 42" "$TMP/log"
check "restart is logged with duration and pid" "0" "$?"

# After a restart the count starts over rather than restarting every tick.
run "42 1000"; run "42 1000"
check "no immediate second restart" "1" "$(restarts)"

# A brief stall that recovers resets the count.
reset
run "42 10"; run "42 10"; run "42 10"; run "42 20"; run "42 20"; run "42 20"
check "recovered stream resets the stall count" "0" "$(restarts)"

# A new ffmpeg (systemd already restarted it) is a fresh start, not a stall,
# even though its byte counter starts lower.
reset
run "42 5000"; run "42 5000"; run "43 10"; run "43 10"; run "43 10"
check "new pid resets the stall count" "0" "$(restarts)"

# No ffmpeg (service between processes) is systemd's job; never restart.
reset
run "42 10"; run "42 10"; run ""; run ""; run ""; run ""
check "missing ffmpeg does not restart" "0" "$(restarts)"
[[ ! -f "$TMP/state" ]]
check "missing ffmpeg clears state" "0" "$?"

# Corrupt state is treated as a fresh start, not a crash.
reset
echo "garbage" >"$TMP/state"
run "42 10"
check "corrupt state does not fail the script" "0" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

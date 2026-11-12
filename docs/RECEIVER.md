# TrainCam display receiver

The Raspberry Pi 5 receiver runs two independent 1920x1080 HDMI displays:

- **HDMI-A-1 (larger display):** live ESP32 camera, then Pi if it has fresh frames; otherwise
  local photographs and visitor information.
- **HDMI-A-2 (smaller display):** full-screen USB camera; visitor information while USB is absent
  or recovering. The USB display does not depend on the Pi camera or WiFi.

Screen selection happens before viewer URLs are loaded. The larger screen
loads only ESP32 and Pi fallback viewers; the smaller screen loads only the
USB viewer. Both load the local visitor page. This avoids starting camera
connections only to discard them, without delaying startup or changing failover.

The custom labwc autostart launches both `kanshi` and the browser service.
It replaces the desktop's default autostart, so it must start `kanshi`
explicitly to apply the saved HDMI positions when displays connect.
Healthy page heartbeats alone do not prove the windows are on the right screens.

Eight distinct layout photos rotate every 20 seconds (a 2-minute-40-second
photo loop). The four visitor messages and QR codes for the website, historic
map, volunteering, and donation inquiries repeat across those photos.
All photos and QR codes are stored locally.
When a camera hides the visitor page, slide rotation and image changes pause;
the page continues sending health heartbeats and resumes rotation when shown,
unless the operator has paused it.
The kiosk needs no internet to show them. Scanning a QR code opens the public
website on the visitor's phone, which does require internet.

Both kiosk outputs keep a 5% border on every edge to tolerate display overscan.
Camera images use **Fit**, not cropped Fill, and the kiosk shows a large live
status instead of small diagnostic clocks. Visitor text and QR codes are sized
for viewing at a distance. The direct camera viewer retains its normal controls
and diagnostics; these adjustments apply only to `?kiosk=1`. If a physical
screen still clips, select its native/full-pixel picture mode in the monitor
menu rather than reducing resolution.

## Provisioning

Start with 64-bit Raspberry Pi OS Desktop, the `train` user, SSH, and a working
desktop session. From this repository:

```bash
ansible-playbook -i inventory kiosk.yml
```

`scripts/setup-kiosk.sh` is a compatibility wrapper for this command. The
playbook installs runtime packages, deploys the viewer, relays, offline assets,
watchdog, and display layout, then restarts the kiosk services. **Provisioning
interrupts the displays.** Do not run a full playbook during a public show just
to recover a camera. The old standalone installer and its `--uninstall` option
are no longer supported.

Configuration lives in `group_vars/trainview.yml`. The layout's USB camera is
selected by `/dev/v4l/by-id/usb-Razer_Inc_Razer_Kiyo_Pro-video-index0`, not by a
potentially changing `/dev/video0` number. Update that value for another camera.
The role defaults to `/dev/video0` for generic receivers.

## Recovery behavior

The USB relay requires a **complete JPEG within five seconds**, including at
startup. No bytes, partial frames, oversized frames, and EOF all cause capture
to reopen after two seconds. A stuck FFmpeg receives SIGTERM, then SIGKILL
after two seconds. HTTP streams close when frames go stale, rather than
holding a frozen image indefinitely. `/status` returns 503 without fresh
frames. Slow/disconnected HTTP clients have bounded waits.

The ESP32 relay discards a JPEG if the source disconnects before its declared
`Content-Length` arrives, then reconnects after two seconds. A partial image
does not replace the last complete frame or advance the frame-health counters.

The browser selector uses viewer-reported video health, not HTTP reachability:
WebRTC requires an advancing playback clock; MJPEG requires an image load
plus fresh relay frame status. Loss selects visitor information; ten seconds
of sustained good video is required before switching back. WHEP connection
attempts and status requests are time-bounded. Unresponsive child pages
reload at most once per minute.

The local server watches a separate heartbeat from the currently visible
page on each display. A missing initial page gets 180 seconds; a lost heartbeat
gets 45 seconds. It restarts only the browser service, with at most three
attempts in a rolling 15-minute window. An intentionally stopped browser stays
stopped. This is **not proof that the GPU or physical monitor is displaying
frames**: JavaScript can remain responsive during a graphics fault.

## Live checks

```bash
ssh train@trainview1.local
curl -fsS http://127.0.0.1:8081/_kiosk/health
curl -sS http://127.0.0.1:8083/status
sudo journalctl -b -u user@1000.service --no-pager
sudo journalctl -b _SYSTEMD_USER_UNIT=traincam-usb-relay.service --no-pager
sudo journalctl -b _SYSTEMD_USER_UNIT=traincam-kiosk-www.service --no-pager
```

Increasing `frame_sequence` and a small `frame_age_ms` indicate fresh capture.
`frame_sequence: 0` or `frame_age_ms: null` means capture has not succeeded;
an active systemd unit alone does not establish video health.

On September 29, 2026, the deployed old relay was stuck in a blocking read,
FFmpeg consumed a core, and the kernel reported USB/UVC resets and errors.
The bounded capture fix allowed retries; unplugging and reconnecting the
camera restored frames without another service restart. That does **not**
establish whether the original USB fault was cable, camera firmware, host
controller, or power. Use a short known-good cable directly into the Pi and
investigate recurring kernel USB errors; software cannot guarantee recovery
from a device that requires physical power cycling.

In the live recovery exercise, a deliberately stopped FFmpeg was replaced and
fresh USB frames resumed within 15 seconds. With the Pi video service stopped
but its HTTP status still answering, the train-camera display showed visitor
slides while USB continued on the other; restoring video restored the train view.
These targeted checks are not a substitute for the cold-boot and soak checks.
USB3 U1/U2 controls reported `disabled` during inspection, so the kernel's
failed U1-enable messages alone are not proof that active link power saving
caused the fault. No kernel USB quirk was applied.

### Kiyo Pro link power management

Linux has a [device-specific NO_LPM fix for the Razer Kiyo Pro](https://github.com/torvalds/linux/commit/8b7a42ecdcdeb55580d9345412f7f8fc5aca3f6c)
because its firmware can stop responding after link power transitions.
For older kernels, the role's `99-traincam-kiyo-lpm.rules` disables
`power/usb2_hardware_lpm` only for
`1532:0e05`, on connection or a device change event. This does not reset
the camera, its host controller, or the root SSD. USB2 L1 link power management
is separate from runtime autosuspend: `runtime_suspended_time: 0` does not
mean link power management is off.

This rule is a USB2 workaround, not a substitute for a kernel containing the
[Raspberry Pi backport](https://github.com/raspberrypi/linux/commit/3ac9c06f80ada8fb91e79f4bbdc995fa1a27e023),
especially before moving the camera back to USB3. On fixed kernels the rule
skips the missing attribute. Do not blindly add `usbcore.quirks=1532:0e05:k`:
that parameter toggles the built-in flag and can undo the fix after an upgrade.
Two-second capture pauses still occurred with LPM disabled on November 12, 2026,
so this workaround does not establish that every dropout is fixed.
Persistent USB descriptor errors still require cable/camera/port isolation;
a clean short observation or a successful replug is not proof of repair.

Deploy only this rule without restarting the displays or capture services:
`ansible-playbook -i inventory kiosk.yml --tags trainview_usb_lpm`.

## Before the Christmas fair

```bash
bash tests/test_usb_recovery.sh
bash tests/test_kiosk_watchdog.sh
bash tests/test_kiosk_provisioning.sh
bash tests/test_viewer_reconnect.sh
CHROME=/path/to/chromium node tests/test_kiosk_browser.mjs
```

On hardware, verify both HDMI outputs separately, unplug/replug USB, start
without network cameras, return the train camera, and run an extended soak.
Repeat cold boots and power-loss checks on a spare card before calling the
system fair-ready. The existing live root filesystem is writable and the
clock is unsynchronized; this change does not enable overlay root, change the
network, upgrade graphics drivers, or reboot the Pi.

Offline photos were approved for this layout kiosk by its operator. Sources:
[gallery](https://ncngmodelrailroad.org/gallery/),
[volunteering](https://ncngmodelrailroad.org/volunteer/),
[support](https://ncngmodelrailroad.org/donate/), and
[historic map](https://ncngmodelrailroad.org/map/), accessed September 29, 2026.
No online donation checkout or confirmed sponsorship program is implied.
Five additional gallery photos were added on October 30, 2026. They are
resized JPEGs with a maximum edge of 1280 pixels; no gallery requests occur
at runtime.

| Local photo | Gallery source |
|---|---|
| `depot.jpg` | [Depot and passengers](https://ncngmodelrailroad.org/images/gallery-img_1165.jpg) |
| `mine.jpg` | [Mine and timber ore bin](https://ncngmodelrailroad.org/images/gallery-img_1181.jpg) |
| `repair-yard.jpg` | [Freight-car repair scene](https://ncngmodelrailroad.org/images/gallery-img_1173.jpg) |
| `car-show.jpg` | [Miniature car show](https://ncngmodelrailroad.org/images/gallery-img_1566.jpg) |
| `christmas-train.jpg` | [No. 9 by the decorated Kidder house](https://ncngmodelrailroad.org/images/gallery-img_9711.jpg) |

The QR PNGs are generated locally with Python `qrcode` 8.2, error correction M,
ten-pixel modules and a four-module quiet zone. No runtime QR dependency or
third-party QR service is used.

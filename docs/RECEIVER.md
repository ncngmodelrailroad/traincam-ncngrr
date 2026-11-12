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
desktop session. For the Razer Kiyo Pro, use a supported kernel containing the
[Kiyo USB fix](https://github.com/torvalds/linux/commit/8b7a42ecdcdeb55580d9345412f7f8fc5aca3f6c);
the receiver was updated to **6.12.115** on November 12, 2026.
The kiosk playbook does not upgrade the Pi kernel; update older base images
using [the maintenance procedure below](#kernel-updates-without-layout-internet).
From this repository:

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

### Razer status and limits

On November 12, the old 6.12.25 kernel stopped delivering camera buffers, then
USB control requests and enumeration failed. Browser retries were not the fix,
and disabling USB2 link power management at runtime did not prevent recurrence.
After the supported 6.12.115 update and reboot, the camera reported the built-in
`NO_LPM` quirk (`0x400`), with no hardware-LPM attributes. A 20-second check
received 602 distinct JPEGs with no gaps over 250 ms. **Extended stability is
still unproven.** Keep the required cable reach; a bad cable was not established.

The role's `99-traincam-kiyo-lpm.rules` is only an older-kernel USB2 workaround;
it skips the missing attribute on fixed kernels. It can be deployed separately
with `--tags trainview_usb_lpm`, but is not a substitute for the kernel update.
Do not add `usbcore.quirks=1532:0e05:k` blindly: it toggles the built-in flag and
can undo the fix. Never reset or power-cycle the shared USB controller or hub:
the receiver's live root filesystem is on the USB SSD.

## Kernel updates without layout internet

Use the laptop's internet through SSH; leave the Pi's Ethernet and WiFi setup
alone. In one laptop terminal, keep this temporary, loopback-only proxy running:

```bash
ssh -S none -N -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes \
  -R 127.0.0.1:18088 train@trainview1.local
```

In another terminal, SSH to the receiver. Check its clock with `date -u` and
correct it from a trusted clock if necessary; do not bypass APT signature or
date checks. For this **Pi 5 receiver**, retain the running kernel, save the boot
files, then install the supported kernel package:

```bash
backup="/var/backups/traincam-boot-$(date -u +%Y%m%dT%H%M%SZ).tar"
proxy=socks5h://127.0.0.1:18088
sudo apt-mark manual "linux-image-$(uname -r)" &&
sudo tar -C /boot/firmware -cpf "$backup" . &&
sudo apt-get -o Acquire::http::Proxy="$proxy" -o Acquire::https::Proxy="$proxy" \
  -o APT::Update::Error-Mode=any update &&
sudo apt-get -o Acquire::http::Proxy="$proxy" -o Acquire::https::Proxy="$proxy" \
  --no-install-recommends --no-remove install linux-image-rpi-2712
```

APT still verifies the normal signed repositories. Record the backup pathname
and reboot only after installation succeeds. Keep power connected until it
finishes. After reconnecting, check `uname -r`, actual camera frames and both
screens. Stop the laptop proxy with Ctrl-C. Do not use `rpi-update` or a full
distribution upgrade to solve this camera issue.

Keep the old kernel and boot backup until the updated setup has run reliably.
If rollback is needed, restore the saved archive into `/boot/firmware` with
`sudo tar -xpf /path/to/saved-backup.tar -C /boot/firmware`, then sync and reboot.
If the receiver cannot boot, restoration requires physical access.
For departure, use `sudo sync && sudo systemctl poweroff` before removing power.

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
system fair-ready. Measure frame gaps and terminal outages, not just average
FPS. The live root filesystem is writable; do not interrupt its power.

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

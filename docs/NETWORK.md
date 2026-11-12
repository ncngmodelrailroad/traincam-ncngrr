# TrainCam Network Requirements

This document describes the network configuration needed for TrainCam to function.

## WiFi Network

All TrainCam devices connect to a dedicated WiFi network:

| Setting | Value |
|---------|-------|
| SSID | _(your network name)_ |
| Password | _(your password)_ |

**Note:** ESP32 WiFi credentials go in `CameraWebServer/secrets.h`, which is gitignored — copy `secrets.h.example` to `secrets.h` and fill it in before uploading. The build fails with a clear error if it's missing. Configure the Pi network with Raspberry Pi Imager or NetworkManager.

### Any saved network that outranks the layout network is an outage

NetworkManager picks by `autoconnect-priority`, highest wins. A phone hotspot
profile saved for field debugging sat at priority 10 while the layout network
(`preconfigured`) sat at 5 — so whenever that hotspot was switched on nearby, the
camera would leave the layout network and the kiosk would lose it. Nothing logs
this as an error; the Pi is happily online, just not where anyone can reach it.

Ansible does not manage WiFi profiles (they come from the Imager), so this is
checked, not deployed:

```bash
nmcli -f NAME,AUTOCONNECT,AUTOCONNECT-PRIORITY con show
```

The layout network must have the highest priority of anything with
`AUTOCONNECT: yes`. Keep debug profiles, but disarm them rather than deleting —
`nmcli con mod <name> connection.autoconnect no` still leaves `nmcli con up
<name>` available when you actually want it.

## Required Ports

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 8554 | TCP | RTSP | Video ingest and playback (MediaMTX) |
| 8889 | TCP | HTTP | WebRTC/WHEP endpoint (MediaMTX) |
| 8080 | TCP | HTTP | Static file server (viewer.html) |
| 22 | TCP | SSH | Ansible deployment access |

## mDNS / Service Discovery

TrainCam uses mDNS (Avahi/Bonjour) for hostname resolution. This works on:
- Home WiFi networks
- iPhone/Android hotspots
- Any local network (no internet required)

| Hostname | Device | Purpose |
|----------|--------|---------|
| `traincam1.local` | Onboard camera (Pi Zero 2 W) | **Primary URL — use this everywhere** |
| `traincam-xxxxxx.local` | ESP32 camera | Unique name derived from the module ID |

**Viewer URL:**
```
http://traincam1.local:8080/viewer.html
```

### Pi mDNS

Raspberry Pi OS has Avahi (mDNS) enabled by default. The Pi is addressable at `<hostname>.local`.

### ESP32 mDNS

The ESP32 advertises `_traincam._tcp` and `_http._tcp` on port 80. Its unique hostname is printed over Serial after WiFi connects.

## Network Topology

```
traincameranet (WiFi AP)
       │
       ├─── traincam1.local (Pi Zero 2 W - onboard camera)
       │         │
       │         ├── RTSP: rtsp://traincam1.local:8554/traincam
       │         ├── WHEP: http://traincam1.local:8889/traincam/whep
       │         └── Viewer: http://traincam1.local:8080/viewer.html
       │
       └─── trainview1.local (Pi 5 - receiver)
                 │
                 └── Chromium → http://localhost:8081/kiosk.html
```

The receiver serves its pages and visitor slides locally. Its independent USB
camera remains usable without WiFi; remote video health controls the other
display. See [receiver deployment and recovery](RECEIVER.md).

## Viewer URL Parameters

The WebRTC viewer (`viewer.html`) accepts URL parameters for network flexibility:

| Parameter | Example | Description |
|-----------|---------|-------------|
| `whepPort` | `?whepPort=8889` | Override WHEP port (default: 8889) |
| `whepBase` | `?whepBase=http://192.168.1.100:8889` | Override entire WHEP base URL |

### Examples

```
# Default (same host as viewer)
http://traincam1.local:8080/viewer.html

# Explicit WHEP server
http://traincam1.local:8080/viewer.html?whepBase=http://relay.local:8889

# From a different network segment
http://192.168.1.50:8080/viewer.html?whepBase=http://192.168.1.50:8889
```

## Firewall Considerations

If running a firewall on the Pi, allow these ports:

```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 8080/tcp  # Viewer
sudo ufw allow 8554/tcp  # RTSP
sudo ufw allow 8889/tcp  # WebRTC/WHEP
sudo ufw allow 5353/udp  # mDNS
```

## Troubleshooting

### mDNS not resolving

If `traincam1.local` doesn't resolve:

1. Ensure Avahi is running: `systemctl status avahi-daemon`
2. Check hostname: `hostname` on the Pi should return `traincam1`
3. Use IP address as fallback: `ip addr show wlan0`

### WiFi connection issues

On the Pi:
```bash
# Check connection status
nmcli device wifi list
nmcli connection show

# Reconnect
nmcli connection up traincameranet
```

On ESP32:
- Check Serial output for connection status
- Verify SSID/password match exactly (case-sensitive)
- Ensure `WiFi.setSleep(false)` is set for reliable streaming

### Port conflicts

If MediaMTX fails to start:
```bash
# Check what's using ports
sudo lsof -i :8554
sudo lsof -i :8889
```

## The WiFi chip wedges and never comes back

The most likely unattended failure on a Pi Zero 2 W. Seen 2026-07-28.

**Symptom:** the camera vanishes from the network and stays gone. It looks
exactly like a dead battery — but the Pi is running perfectly the whole time.

**How to tell it apart:**

| Back on its own in ~30s | Kernel hung; the hardware watchdog fixed it. See `journalctl -b -1`. |
| Gone, but the green ACT LED still flickers | This failure. WiFi is dead, the Pi is fine. |
| Gone and completely dark | Actually a power problem. |

**Confirm it after the fact.** With `traincam_root_overlay: true` (overlayroot
on tmpfs) the journal lives in RAM and is gone after any reboot, so check
*before* rebooting, or tell a watchdog reset from a power loss with
`sudo vcgencmd get_rsts` (`0x1020` = watchdog, `0x1000` = power-on). With a
writable root the journal is persistent:

```bash
journalctl -b -1 -k | grep -E "failed backplane access|status -110"
```

**What happens.** The SDIO bus between the SoC and the BCM43430 WiFi chip
times out under sustained TX. `brcmf_sdio_dpc()` halts, but it only marks the
bus down on `-ENOMEDIUM`, and this is `-ETIMEDOUT` — so the bus is never
marked down. Consequences worth knowing:

- `wlan0` keeps reporting `operstate=up` and `carrier=1`. **Link state lies.**
  Never write a health check against it; ping the gateway instead.
- The kernel stays healthy, so systemd keeps petting `/dev/watchdog0`. The
  hardware watchdog **cannot** catch this.
- NetworkManager keeps polling the dead chip every ~6s forever, which is the
  repeating `-110` in the log.

**What we do about it.** In order of how much they help:

1. `--bitrate 2500000` — sustained high-bitrate TX is the trigger. Capping it
   is the only change that attacks the cause rather than the symptom.
2. `traincam-netwatch.timer` — pings the gateway every 30s and reboots after
   5 minutes of failure. See below.
3. `dtparam=sdio_overclock=25` — halves the SDIO clock from 50MHz for wider
   timing margins (verify with `sudo cat /sys/kernel/debug/mmc1/ios`).
4. WiFi power save off — a failed KSO wake reports the same `-110`. The ESP32
   notes above already said this; it applies to the Pi too.
5. A heatsink. 78 C with no heatsink is a real aggravator.

None of these are a fix. The firmware bug is Broadcom's and there is no known
patch; `firmware-brcm80211` is already on RPi's `rpt3` stability release.

### Is a reboot even enough?

**Unknown, and worth checking.** The WiFi chip shares a power domain with the
SoC, so a warm reboot may leave a wedged chip wedged. The watchdog is built to
answer this in the field: it reboots once, and if the network is still gone
afterwards it does **not** try again. Instead it logs

```
STILL unreachable after a reboot: a warm reboot does NOT clear this.
```

So after any incident, check:

```bash
journalctl -u traincam-netwatch --no-pager | tail -20
```

- Rebooted, then silence -> a warm reboot fixes it. We are done.
- The `STILL unreachable` line -> it does not. We need a USB WiFi dongle
  (bypasses the SDIO bus entirely) or an external circuit that cuts the 5V.

It deliberately never reboots twice in a row, so it cannot boot-loop in front
of visitors.

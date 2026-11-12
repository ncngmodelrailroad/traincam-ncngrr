# TrainCam

**See what the engineer sees** — a live camera feed from a model train, powered by the track.

## What Is It?

A tiny camera rides on a model train and streams the engineer's view to any screen.

```
🚂 Camera on Train  ───►  📡 WiFi  ───►  📺 Phone / TV / Laptop
```

**No batteries to swap** — the camera harvests power from the DCC track.

## Hardware Options

| Option | Size | Best For |
|--------|------|----------|
| **Raspberry Pi Zero 2 W** | Credit card | Validated 720p WebRTC camera |
| **ESP32-S3 XIAO** | Postage stamp | Tighter spaces, simpler setup |

See [docs/HARDWARE.md](docs/HARDWARE.md) for the full power chain (rectifier → buck converter → battery → camera).

## Quick Start

### Pi Zero (Ansible deployment)

```bash
# 1. Clone the repo
git clone https://github.com/djdefi/traincam-ncngrr
cd traincam-ncngrr

# 2. Edit inventory with your Pi's hostname
vim inventory

# 3. Deploy
ansible-playbook -i inventory traincam.yml

# 4. View the stream
open http://traincam1.local:8080/viewer.html
```

### ESP32 (Arduino)

1. `cp CameraWebServer/secrets.h.example CameraWebServer/secrets.h` and set your WiFi credentials in it (it's gitignored — this repo is public)
2. `pio run -t upload` from the repo root (PlatformIO; uses larger TCP buffers for a faster stream — see `docs/HARDWARE.md`), or open `CameraWebServer/CameraWebServer.ino` in Arduino IDE and upload to the XIAO ESP32S3 Sense
3. Open the `http://traincam-xxxxxx.local/stream` URL printed over Serial

### Pi 5 display receiver

See [docs/RECEIVER.md](docs/RECEIVER.md) for the two-screen kiosk, the supported
Razer camera kernel baseline, and updates through a laptop when the layout has
no internet.

## Project Structure

```
traincam-ncngrr/
├── ansible/              # Ansible role for Pi deployment
├── CameraWebServer/      # ESP32 Arduino firmware
├── client/               # WebRTC viewer (HTML/JS)
├── docs/                 # Documentation
│   ├── ARCHITECTURE.md   # System design (all skill levels)
│   ├── HARDWARE.md       # Power chain details
│   ├── NETWORK.md        # WiFi, ports, mDNS
│   └── PRINTABLE_HANDOUT.md  # One-page handout for demos
├── ios/                  # Native iOS viewer app (SwiftUI)
├── tests/                # Automated tests
└── traincam.yml          # Main Ansible playbook
```

## Streaming Stack (Pi)

```
rpicam-vid (H.264) → ffmpeg → MediaMTX → WebRTC/RTSP
                                  ↓
                           viewer.html
```

| Port | Protocol | What |
|------|----------|------|
| 8080 | HTTP | Web viewer |
| 8554 | RTSP | Direct stream (VLC) |
| 8889 | WebRTC | Low-latency browser view |

## Configuration

Edit `group_vars/traincam.yml` for resolution, FPS, and latency:

```yaml
traincam_width: 1280
traincam_height: 720
traincam_fps: 24
LATENCY_MODE: ultra_plus  # Options: low (~1s), ultra (~0.5s), ultra_plus (~0.25s)
```

## iOS App

The **RailCam** iOS app is a native SwiftUI viewer for TrainCam streams.

- **Auto-discovery** of cameras via mDNS and Bluetooth
- **MJPEG streaming** from ESP32 cameras
- **WebRTC/WHEP streaming** from Raspberry Pi cameras
- **Real-time telemetry** and manual camera entry

**Requirements:** iOS 17.0+, iPhone

**Build from source:**

```bash
open ios/TrainCam/TrainCam.xcodeproj
# Build and run in Xcode
```

**App Store:** Search for "RailCam" — coming soon.

**Privacy:** See [Privacy Policy](docs/privacy-policy.html).

## Development

```bash
# Lint everything
./scripts/lint.sh

# Run tests
./tests/run_tests.sh
```

## Roadmap

- [ ] Multiple cameras (cab, yard, rear view)
- [x] ESP32 mDNS discovery
- [ ] Recording & playback
- [ ] Audio from train

## Contributing

Built by hobbyists, for hobbyists. All skill levels welcome:
- **Train folks:** Test on your layout, share feedback
- **Electronics:** Improve power supply, try new hardware
- **Software:** Add features, fix bugs, improve docs

## License

Open source. See [LICENSE](LICENSE) for details.

---

**Contact:** [Open an issue](https://github.com/djdefi/traincam-ncngrr/issues)

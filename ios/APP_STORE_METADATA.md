# App Store Connect Metadata — RailCam

All metadata required for App Store submission. Character limits noted inline.

---

## App Information

| Field                | Value                                    |
|----------------------|------------------------------------------|
| **App Name**         | RailCam                                  |
| **Subtitle**         | Model railroad camera viewer             |
| **Bundle ID**        | `com.traincam.app`                       |
| **Primary Category** | Utilities *(alternatively: Entertainment — choose based on review feedback)* |
| **Secondary Category** | Entertainment                          |
| **Age Rating**       | 4+                                       |
| **Price**            | Free                                     |
| **In-App Purchases** | None                                     |
| **Ads**              | None                                     |

> **Subtitle limit:** 30 characters. "Model railroad camera viewer" = 28 chars.

---

## App Store Description

> **Limit:** 4,000 characters

```
Turn your model railroad into a live broadcast. RailCam lets you view real-time video from tiny cameras mounted on moving trains — all over local WiFi, with no cloud services or accounts required.

Whether you're running an ESP32 camera car or a Raspberry Pi streaming rig, RailCam discovers your cameras automatically and connects in seconds.

KEY FEATURES

• Auto-Discovery — Cameras are found instantly via mDNS and Bluetooth. No manual IP entry needed.

• Dual Camera Support — Works with both ESP32 (MJPEG) and Raspberry Pi (WebRTC/WHEP) camera sources out of the box.

• Live Streaming — Watch smooth, low-latency video from your train's perspective as it rolls through tunnels, over bridges, and past miniature towns.

• Real-Time Telemetry — Monitor camera signal strength, frame rate, and connection status at a glance from the built-in telemetry dashboard.

• Dark-Themed UI — Designed for layout rooms and dim lighting. The dark interface keeps focus on the video feed.

HOW IT WORKS

Mount a small camera on your train and connect it to your local WiFi network. RailCam finds the camera, connects directly over your LAN, and streams video to your iPhone or iPad. Everything stays on your network — no cloud, no subscriptions, no tracking.

COMPATIBLE HARDWARE

• ESP32 XIAO S3 Sense — Streams MJPEG video directly from the camera module.
• Raspberry Pi (Zero W / Zero 2 W) — Uses rpicam-vid with MediaMTX to stream via WebRTC/WHEP or RTSP.

RailCam also works with any standard MJPEG stream source or WebRTC/WHEP-compatible server, so you can use it beyond model railroads with other camera setups.

PERFECT FOR

• Model railroad enthusiasts who want a cab ride or trackside view
• Layout open houses, club meetings, and train shows
• Anyone who wants to watch a live camera feed on their local network

Download RailCam and see your layout from a whole new perspective.
```

> **Character count:** ~1,550 characters (well within the 4,000 limit).

---

## Keywords

> **Limit:** 100 characters total, comma-separated. Do not repeat the app name.

```
model railroad,train camera,live stream,MJPEG,WebRTC,ESP32,Raspberry Pi,train cam,hobby
```

> **Character count:** 89 characters.

---

## What's New (Version History)

### v1.0

```
Initial release.

• Auto-discover ESP32 and Raspberry Pi cameras via mDNS and Bluetooth
• Live MJPEG and WebRTC/WHEP streaming
• Real-time telemetry dashboard
• Dark-themed interface optimized for layout rooms
```

---

## URLs

| Field                  | URL                                                          |
|------------------------|--------------------------------------------------------------|
| **Support URL**        | https://github.com/djdefi/traincam-ncngrr                   |
| **Marketing URL**      | https://github.com/djdefi/traincam-ncngrr                   |
| **Privacy Policy URL** | https://djdefi.github.io/traincam-ncngrr/privacy-policy.html |

---

## Screenshot Requirements

The Simulator test `TrainCamUITests/testCaptureAppStoreScreenshots` writes to
`ios/screenshots/` in its source checkout, matching the Fastlane upload path.
It creates the directory and reports write errors instead of silently skipping images.

### Required Device Sizes

| Device Class          | Display Size | Resolution (portrait)  | Required |
|-----------------------|-------------|------------------------|----------|
| iPhone 6.7"           | 6.7"        | 1290 × 2796 px        | Yes      |
| iPhone 6.1"           | 6.1"        | 1179 × 2556 px        | Yes      |

> App Store Connect requires at least one set of screenshots for the largest device size (6.7"). The 6.1" set is strongly recommended. iPad screenshots are required only if the app supports iPad.

### Suggested Screenshots (5)

| #  | Screen               | Content Description                                                  |
|----|----------------------|----------------------------------------------------------------------|
| 1  | Camera List          | Home screen showing auto-discovered cameras (ESP32 and Pi) with status indicators |
| 2  | Live MJPEG Stream    | Full-screen MJPEG video feed from an ESP32 camera on a moving train  |
| 3  | Live WebRTC Stream   | Full-screen WebRTC video feed from a Raspberry Pi camera             |
| 4  | Telemetry Dashboard  | Real-time telemetry overlay showing signal strength, FPS, and connection info |
| 5  | Camera Detail        | Camera info/settings screen showing device name, IP, stream type, and status |

> **Tips:**
> - Use real footage from a model railroad for maximum appeal.
> - Capture in both light and dark environments to showcase the dark theme.
> - Screenshots must not include status bar content that could be misleading (Apple guideline).

---

## Review Notes (for App Store Review)

```
RailCam connects to TrainCam cameras on the local WiFi network. To test, you need either:

1. An ESP32 XIAO S3 Sense camera on the same WiFi network, or
2. A Raspberry Pi running MediaMTX (WebRTC/WHEP) on the same WiFi network.

The app uses mDNS (Bonjour) and Bluetooth for camera discovery. No account or login is required. No data is collected or transmitted off-device.

Source code: https://github.com/djdefi/traincam-ncngrr
```

---

## Content Rights

- [x] App does not contain, show, or access third-party content
- [x] No user-generated content
- [x] No streaming of copyrighted material

## Export Compliance

- [x] App uses HTTPS (ATS) — qualifies for encryption exemption
- [x] No custom encryption algorithms

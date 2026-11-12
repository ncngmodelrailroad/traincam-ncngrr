# TrainCam Hardware - Power Chain

The onboard camera runs on power harvested from the DCC track. This document describes the power chain from rails to camera.

## Power Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           POWER CHAIN                                       │
│                                                                             │
│   DCC Track    Truck        Bridge       Buck         USB Battery   Camera  │
│   Power     →  Pickups   →  Rectifier →  Converter →  Bank       →  Unit   │
│                                                                             │
│   ~14V AC      Wheels       AC → DC      DC → 5V      Buffer &      RPi    │
│   (NCE          contact      ~14V DC      USB out      charge       Zero W  │
│   PowerCab)     rails                                               + Cam   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. DCC Track Power

**Source:** NCE PowerCab (or compatible DCC system)

**Output:** ~14V AC (On3 scale, varies by DCC system and load)

**Notes:** DCC is AC-like (square wave), not pure DC. The bridge rectifier handles this.

### 2. Truck/Wheel Pickups

**Purpose:** Collect power from rails via wheel contact

**Implementation:**
- Metal wheels with electrical contact to trucks
- Wires from trucks routed through train car body
- Both rails used (common return)

**Tips:**
- Keep connections clean for reliable power
- Use multiple wheel pickups if possible for redundancy
- Flexible wire to allow truck pivoting

### 3. Bridge Rectifier

**Purpose:** Convert AC/DCC square wave to DC

**Specs:**
- Input: ~14V AC from track
- Output: ~12-14V DC (unregulated)
- Type: Full-wave bridge rectifier (4 diodes or integrated module)

**Common parts:**
- MB10S bridge rectifier (small, SMD)
- 2W10 bridge rectifier (through-hole)
- Any 1A+ rated bridge rectifier rated for 25V+

### 4. Buck Converter

**Purpose:** Step down ~14V DC to stable 5V DC

**Specs:**
- Input: 8-24V DC (handles track voltage variations)
- Output: 5V DC, 2A+ capable
- Efficiency: 90%+ preferred for heat management

**Common parts:**
- MP1584 module (small, cheap)
- LM2596 module (common, adjustable)
- Any 5V USB output buck converter

**Important:** Must provide stable 5V even with track voltage fluctuations (dirty track, load changes, etc.)

### 5. USB Battery Bank

**Purpose:** Buffer power and provide stable 5V to Pi

**Why a battery bank?**
- Buffers momentary power interruptions (dirty track, switch gaps)
- Provides stable 5V USB output
- Pass-through charging keeps it topped up while power is available
- Pi continues running briefly during power gaps

> **Not every bank does this, and it is the hardest spec to satisfy.**
> "Pass-through charging" on the box usually means only that the bank *can*
> charge and output at the same time. It does not promise the output stays up
> when the input goes away. Many banks drop the rail for tens of milliseconds
> while they switch from charge mode to discharge mode, which brown-outs the Pi
> — a Zero has very little bulk capacitance to ride it out. A bank can run the
> Pi happily for hours on its cells and still fail this. Measured 2026-07-31:
> the bank fitted at the time rebooted the Pi four times out of four when its
> input was pulled, two of those hard enough to crash during early boot, and
> `vcgencmd get_throttled` never once reported undervoltage first. What you want
> is sometimes sold as "UPS mode" or "uninterruptible"; it is rarely stated, so
> step 2 of *Before Installing in a Car* is the arbiter, not the marketing.

**Specs:**
- Small form factor (fits in train car)
- Pass-through charging support
- **Uninterruptible output when input is removed** (test it; see above)
- 5V 2A+ output capability
- 2000-5000mAh capacity (balance size vs runtime)

**Example:** Small USB power banks with pass-through charging (check specs)

> **Meter every LiPo pigtail before it touches anything.** JST-PH has no polarity
> standard — JST specifies the housing and crimps, not which pin is positive, so
> the assembler decides and both conventions ship. The housing is keyed, which
> makes it worse: it clicks in, feels right, and can still be backwards.
>
> Test: red probe on the red wire, black on black. A **negative** reading means
> the colours are lying and the pigtail is reversed. Re-pin the housing (lift the
> retention tab, swap the two crimps) before connecting anything.
>
> Measured 2026-08-03: a cell supplied with a Waveshare UPS HAT (C) read positive
> only with the probes swapped, i.e. its black wire was the positive lead. The
> board got hot on connection. The Pi survived (`throttled=0x0`, no mmc/ext4
> errors, camera unaffected); the cell was discarded as damaged.

**A UPS HAT is a real option, but check the mating and measure your load.**
The Waveshare UPS HAT (C) ([wiki](https://www.waveshare.com/wiki/UPS_HAT_(C))) is
the right *class* of device where a USB power bank is not: its charger does
dynamic path management, which is the uninterrupted switchover a power-bank IC
never promises, and its onboard INA219 reports live battery voltage/current/percent
over I2C — useful for an unattended show. Capacity is your choice; the vendor's
803040 1000mAh cell is the matching accessory, not a limit ("the capacity is not
the affecting factor" — vendor FAQ).

Two things to check before trusting one in a car:
- It mates by **spring pogo pins** under screw tension, and the vendor's FAQ lists
  poor pogo contact as a known failure mode ("tighten the screws"). Vibration in a
  moving car is the risk; verify the I2C gauge still enumerates after a run.
- Discharge is capped around **1.8A**, with a vendor note that an over-current load
  makes the Pi reboot. Measure the actual 5V draw with a viewer connected (step 6
  of *Before Installing in a Car*) rather than assuming either way — this repo has
  never recorded that figure.

Using one needs `dtparam=i2c_arm=on` and `i2c-tools`; neither is currently set by
the playbook, so `/dev/i2c-1` does not exist and the gauge cannot be seen at all.

### 6. Camera Unit

**Option A: Raspberry Pi Zero 2 W + Camera Module**
- Pi Zero 2 W running 64-bit Raspberry Pi OS
- Camera Module v2 or v3 (CSI connector)
- Power: 5V via micro USB from battery bank
- Runs `rpicam-vid` for H.264 streaming
- Provisioned headless: no desktop, VNC, HDMI, audio, or Bluetooth

**Option B: ESP32-S3 + OV2640**
- Seeed Studio XIAO ESP32S3 Sense
- OV2640 camera (built-in on Sense module)
- Power: 5V via USB-C from battery bank
- Runs `CameraWebServer` sketch for MJPEG streaming

**Tuning the ESP32 live.** `:81/status` reports `sensor_pid` (`0x26` OV2640,
`0x3660` OV3660 — Seeed changed the Sense module in 2025). `:81/control` takes
`framesize`, `quality`, and the sensor's exposure and colour settings
(`gainceiling` 0–6, `aec2`, `ae_level` -2–2, `aec`/`aec_value`, `agc`/`agc_gain`,
`brightness`/`contrast`/`saturation`, `awb`/`awb_gain`/`wb_mode` 0–4, `lenc`,
`bpc`, `wpc`), and echoes what stuck. Changes last until reboot; bake the winners
into `setup()`. `fps=N` caps the frame rate (default 20; capture and WiFi can
reduce the delivered rate; 0 = uncapped). With PSRAM, JPEG quality defaults to
9. The OV2640 uses a 4x automatic gain ceiling (`gainceiling=1`) to recover
shadow detail; automatic exposure and gain remain enabled. The camera clock
is 20MHz.

Measured 2026-10-24 (OV2640, SVGA): the Arduino core's prebuilt 5.7KB TCP send
buffer capped the stream at ~8fps / 1.1Mbps (throughput ≈ buffer ÷ round-trip).
`platformio.ini` rebuilds the core with 64KB TCP buffers and a wider WiFi TX
window (`pio run -t upload`); the Arduino IDE build cannot change these. With
it, uncapped:

| framesize | quality | fps | KB/frame |
|---|---|---|---|
| 11 SVGA 800x600 | 10 (then default) | 25 | 39 |
| 11 SVGA | 8 | 19 | 47 |
| 11 SVGA | 6 | 10 | 59 |
| 13 HD 1280x720 | 10 | 10 | 77 |
| 15 UXGA 1600x1200 | 10 | 5 | 171 |

Above SVGA the OV2640 drops to its slower full-resolution mode, and HD showed
vertical stripe noise and a darker image; SVGA q10 was chosen in that round.
With the original radio/CPU settings, the die ran hot:
68°C idle (camera always capturing, WiFi power save off, battery charging),
~80–87°C streaming at 20fps, 92°C+ uncapped — hence the default cap. Give it
airflow in the car.

The radio and CPU are most of that heat. A 6-minute soak per setting, streaming
at the 20fps cap (temperature at the end):

| tx_power | cpu_mhz | °C | fps | ping |
|---|---|---|---|---|
| 80 (20dBm) | 240 | 85 | 17 | 55ms |
| 52 (13dBm) | 240 | 74 | 19 | 14ms |
| 80 | 160 | 85 | 19 | 24ms |
| 52 | 160 (default) | 69 | 20 | 10ms |

That was at -48..-54dBm RSSI. If the car loses signal far from the router, raise
the power live with `/control?tx_power=80` (8–84, in 0.25dBm steps); `cpu_mhz`
takes 80/160/240. After a viewer disconnects the next one waits ~8s for the
single stream slot (the server's 5s send timeout on the dead socket).

Measured 2026-10-26 on the same OV2640: repeated bench comparisons selected
JPEG quality 9 and the 4x gain ceiling. Dark objects were more visible and JPEG
blocking was reduced, at the cost of more grain and larger frames. These are
not fixed-gain or manual-exposure settings; very bright windows can still clip.

| Settings | Delivered fps | Mean JPEG size |
|---|---|---|
| Previous: q10, 2x gain ceiling, 13dBm | 18.8–20.1 | 39–40KB |
| New: q9, 4x gain ceiling, 13dBm (5-minute run after flashing) | 19.75 | 54.3KB |

The final run delivered 8.58Mbps, with a highest reported die temperature of
73.6°C, RSSI -48 to -50dBm, unchanged boot/WiFi-restart counters, and minimum
free heap 150496 bytes. In that round, CPU 160MHz, XCLK 24MHz, SVGA and the
20fps cap were unchanged. The 20MHz clock and higher TX power did not establish
a clear win in that comparison; the daylight clock result below supersedes it.

Earlier runs at -67 to -74dBm delivered only about 7–12fps. The later recovery
to a stronger signal is not an image-setting improvement. These are stationary
bench results, not proof of moving-train sharpness or enclosed-car cooling.
To compare the previous image settings live, use
`:81/control?quality=10&gainceiling=0`; reboot restores the new defaults.

**Daylight clock comparison, 2026-10-27.** XGA (1024x768) at quality 9 showed
strong vertical color stripes at 24MHz. Returning to 20MHz removed the strong
stripe pattern; reflashing 24MHz reproduced it. The default is now 20MHz,
with SVGA retained at about 20fps. XGA delivered about 12fps at 20MHz versus
14–16fps with the striped 24MHz image, so it remains a live option rather than
the default. Lower gain, contrast changes and quality 8 did not establish a
better overall image in this daylight comparison.

**Long stream pauses.** Average FPS hid occasional freezes. TCP traces showed
out-of-order data during the gaps, before the receiver relay. The PlatformIO
build now uses `CONFIG_LWIP_TCP_TMR_INTERVAL=25` instead of 250ms; the
[ESP-IDF 5.5.5 setting](https://github.com/espressif/esp-idf/blob/v5.5.5/components/lwip/Kconfig)
supports a shorter interval to speed recovery of unacknowledged packets.
Reflashing the old build reproduced a 1.42s pause. Two 25ms runs, totaling eight
minutes, had no gaps over one second; the final five-minute run delivered
20.28fps, with a longest gap of 519ms and a final reported die temperature of
69.6°C. A later two-minute daylight run still had a 1.84s gap: this is a
mitigation, not a freeze fix. Temporary on-board timing at 20MHz subsequently
recorded 590ms blocked in frame transmission, with no capture wait over 100ms
in that three-minute run. The remaining delivery pauses are not explained by
image quality or average FPS. The Arduino IDE build does not apply these SDK
settings.

The earlier `CONFIG_ESP_WIFI_DYNAMIC_TX_BUFFER_NUM=64` override was ineffective:
Arduino initializes its own 32-buffer dynamic configuration unless static
buffers are explicitly enabled. It was removed. Static-buffer and TCP_NODELAY
experiments did not establish a further improvement and were not retained.

Low-light quality remains separate: testing 8x/16x/32x gain and longer manual
exposure in the current near-dark scene did not reveal useful scene detail.
Those changes were reverted rather than treating brighter noise as a fix.

## Physical Installation

```
┌─────────────────────────────────────────────────────────────────┐
│                      TRAIN CAR LAYOUT                           │
│                                                                 │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │
│   │Rectifier│──│  Buck   │──│ Battery │──│ Pi Zero + Cam   │   │
│   └────┬────┘  │Converter│  │  Bank   │  │    (forward)    │   │
│        │       └─────────┘  └─────────┘  └─────────────────┘   │
│   ┌────┴────┐                                                   │
│   │  Truck  │ ← Wheel pickups                                   │
│   │ Pickups │                                                   │
│   └─────────┘                                                   │
└─────────────────────────────────────────────────────────────────┘
```

**Tips:**
- Mount camera at front of car for engineer's view
- Secure battery bank to prevent shifting
- Use hot glue or foam tape for component mounting
- Route wires to avoid interference with trucks
- Consider adding a power switch for easy on/off

## Before Installing in a Car

1. Set the buck converter to 5.1V before connecting a camera, then confirm it stays stable under camera load.
2. Verify the battery bank supports simultaneous charge and output without resetting when track power is removed and restored. Watch `/proc/sys/kernel/random/boot_id` across the gap, not uptime and not the LEDs — if that value changes, the Pi rebooted and the bank does not buffer. Test escalating gaps (a ~0.5s tap, 2s, 10s, 30s); the short ones matter most, because a switch gap is far shorter than a dead section. Note that undervoltage gives no warning: `get_throttled` stayed `0x0` right up to the moment of death in every failure observed so far.
3. Run the complete camera for 30 minutes and confirm `vcgencmd get_throttled` reports `0x0`.
4. Insulate every exposed conductor, add strain relief, and keep the converter and camera ventilated.
5. Repeat the test from wheel pickups on the layout before securing the car body.
6. Measure 5V input current while a viewer is connected; size the converter and battery from the measured load, not a module's advertised maximum.

The Pi role disables hardware and services that the headless camera does not
use. A reboot is required after the first deployment. It deliberately leaves
WiFi, CPU clocks, resolution, frame rate, and keyframe timing unchanged.

## Troubleshooting

| Problem | Possible Cause | Fix |
|---------|---------------|-----|
| Pi reboots randomly | Power interruptions | Check wheel pickup contacts, add capacitor buffer |
| No power at all | Bridge rectifier failed | Check rectifier with multimeter |
| Pi won't boot | Buck converter voltage wrong | Verify 5V output with multimeter |
| Overheating | Buck converter undersized | Use higher efficiency/capacity buck |
| Weak WiFi | Camera position | Ensure antenna not blocked by metal |
| Purple/magenta image | NoIR module using the IR-filtered tuning | Point `traincam_tuning_source` at the `*_noir.json` for that sensor |
| Green/cyan image | IR-filtered module using the NoIR tuning | The reverse — use the plain `*.json` |
| Soft AND washed out, even with correct tuning | NoIR module in visible light | Physics, not config — see "NoIR is the wrong module for daylight" below |
| Camera "not detected" after a swap | Third-party sensor invisible to `camera_auto_detect`, or a cable that does not fit | Set `traincam_camera_overlay` — see "Swapping the camera module" below |
| Field of view much narrower than the lens | libcamera chose a cropped sensor mode to match the output aspect | Pin the mode — see "Check the sensor mode after any camera change" |
| Dark, noisy, or smeared on a dim layout | Unbinned sensor mode, ¼ the light per pixel | Same — pin the full-FOV binned mode |

## NoIR is the wrong module for daylight

**RESOLVED 2026-08-03: an IR-cut IMX219 is now fitted, and this section is
history plus the evidence for why the swap was right.** Keep it — the failure is
subtle, was misdiagnosed twice, and will recur the next time a module is swapped.

The first two modules were NoIR. The `*_noir.json` tuning corrects the colour
matrix but it cannot undo the two physical costs, and no config setting will:

- **Washed out.** Infrared floods every photosite. The tuning rebalances the
  result; it cannot remove the light that already landed.
- **Soft.** IR focuses at a different plane than visible light, so the IR
  component lands defocused on top of the sharp visible image.

NoIR modules exist for night vision with an IR illuminator. For a lit layout an
IR-filtered module is the correct part, and swapping is the only real fix.

**What the swap actually bought** (Arducam IMX219 standard, $17, 2026-08-03).
Both predicted symptoms cleared at once, which is the strongest evidence that
they had one shared cause:

| | NoIR + `_noir` tuning | IR-cut + plain tuning |
|---|---|---|
| `calibrate_awb.py verify` distance | **0.446** (bad) | **0.014** (good) |
| Colour | salmon-pink deck and dirt | neutral |
| Sharpness | soft | visibly sharper, no focus change |
| `ColourTemperature` | pinned placeholder | **2915 K**, a real reading |
| `--awb` modes | no-op — `rpi.awb` is `{"bayes": 0}` | all 7 work |

That last row matters beyond colour: under noir tuning `--awb` did nothing at
all, so `--awbgains` was the only control. The plain `imx219.json` carries a real
`ct_curve`, so auto white balance genuinely works now and `--awb incandescent`
is available if the venue's halogen needs it.

**How bad it is depends entirely on the lighting.** Incandescent and halogen are
blackbody radiators: a ~2800K filament emits more power in near-IR than in
visible, and halogen floods more still. They are the worst case. Fluorescent is
a line spectrum and modern LED emits almost no IR, so under those a NoIR module
with the `_noir` tuning can be close to fine.

**The Aug 2026 venue is mostly incandescent/halogen flood.** So this was the bad
case, and no software setting fixed it: Bayer dyes are largely transparent above
~700nm, which means IR lands in R, G and B at similar strength. That is a
common-mode pedestal, and per-channel gains are multiplicative — you cannot
subtract a common term by multiplying. This is exactly why IR-cut filters exist
in hardware instead of in software.

**A good white-card score does NOT rule out IR.** This wasted a day. White paper
reflects IR roughly in proportion to visible light, so it balances fine on a NoIR
module — a venue calibration scored distance 0.024 on a bulletin board while the
layout it was for still rendered salmon-pink. IR damage is *differential*: it
lifts materials with high IR reflectance (plaster, wood, some paints) and leaves
others alone. Judge IR on the scene you actually shoot, never on a card.

**Telling them apart, no tools:** point a TV remote at the lens and hold a
button. On the stream, a NoIR module shows the remote's LED as an obvious bright
white/violet dot. An IR-filtered module shows nothing at all.

**Telling them apart by measurement**, which is the reliable way — the eye gets
this backwards, because a correct rendering looks green immediately after a
magenta one, and any coloured room lighting defeats judgement entirely.

> **Measure in the video path. Never `rpicam-jpeg`.**
> The still and video pipelines converge on different white balance. Byte-
> identical options on one scene measured 1.046/1.032 through `rpicam-jpeg` and
> 0.785/0.809 through `rpicam-vid`. An earlier version of this page recommended
> `rpicam-jpeg` here, and following it produced a confident, wrong conclusion
> about which tuning file this module needs. Use `--codec mjpeg`:

```bash
sudo systemctl stop traincam
for t in imx219 imx219_noir; do
  rpicam-vid --nopreview -t 3000 --codec mjpeg --width 1280 --height 720 \
    --mode 1640:1232 --segment 1 -o /tmp/$t-%03d.jpg \
    --tuning-file /usr/share/libcamera/ipa/rpi/vc4/$t.json
done
sudo systemctl start traincam
```

Sample a genuinely neutral surface (white trim, a sheet of paper) and take the
channel ratios. Neutral is `R/G = B/G = 1.0`; above 1 is magenta, below is
green. Measured here in the video path: `imx219.json` gave 1.610/1.356,
`imx219_noir.json` gave 0.791/0.838.

**R and B elevated *together* is the IR signature** — coloured room lighting
would push one channel much harder than the other.

## White balance must be recalibrated at the venue

`imx219_noir.json` ships `rpi.awb = {"bayes": 0}`. Bayesian AWB is switched off
outright: there is no `ct_curve`, no `priors`, and no `modes` dict. Three
consequences, all confirmed by measurement:

- **`--awb` is a no-op** under this tuning. All seven modes measure identically,
  because the modes dict it would select from does not exist.
- libcamera falls back to **grey-world** AWB, which depends purely on scene
  statistics. That is why the still and video paths disagree: different sensor
  mode and downscale, different statistics.
- So `traincam_awb_gains` is not a workaround — it is the only white balance
  control that exists here.

The colour matrices are fine, though: the `_noir` file carries 8 CCMs spanning
2498–8575K, reaching further into tungsten than `imx219.json`'s 2860K. libcamera
back-derives colour temperature from manual gains (locked gains of `0.99,2.23`
reported `ColourTemperature: 2706`) and picks the right matrix, so no CCM
override is needed.

Because the lock is a fixed number, **it is only correct for the light it was
measured under**. Evidence it does not travel: with gains unchanged, one room
measured 0.985/1.094 in the evening and 1.152/1.114 the next morning.

Use the helper rather than doing this by hand:

```bash
./scripts/calibrate_awb.py measure   # white paper FILLING the frame, venue lighting
# paste the printed traincam_awb_gains into group_vars/traincam.yml
ansible-playbook -i inventory traincam.yml
./scripts/calibrate_awb.py verify    # normal scene; wants R/G and B/G near 1.00
```

The card must fill the frame because grey-world assumes the frame averages to
grey. Both commands stop the stream and restart it on exit, including on
failure.

**If there is no time to calibrate at the venue, clear `traincam_awb_gains`
rather than shipping a lock from another room.** Grey-world auto is at least
self-correcting; a wrong fixed lock is not.

## Swapping the camera module

`camera_auto_detect=1` probes **only** the official Raspberry Pi sensors:
`ov5647` (v1), `imx219` (v2), `imx477` (HQ), `imx708` (v3). Anything else —
Arducam's `imx519` 16MP, `ov64a40` 64MP, the Pivariety low-light boards — is
invisible to it, and the symptom is identical to a dead ribbon cable. Some
third-party clones of supported sensors also fail the probe.

1. **Power off.** Never swap a CSI cable live: the ribbon carries 3.3 V and I²C,
   and the contacts bridge against each other on the way in.
2. **Use the cable that fits the new module**, not the one that works today. A
   Pi Zero 2 W is narrow 22-pin at its end, but the module end varies — the
   OV5647 here uses narrow→wide (15-pin), which physically will not fit a module
   with a 22-pin socket. A mismatched cable is a plausible reason a module
   "was never detected". A 22-to-22 cable has shipping lead time; check first.
3. Boot and check: `rpicam-vid --list-cameras`
4. If it lists nothing, name the sensor explicitly in `group_vars/traincam.yml`
   and re-deploy, then reboot:
   ```yaml
   traincam_camera_overlay: imx219
   ```
   The deploy asserts the `.dtbo` exists, so a typo fails the run rather than
   the camera, and it sets `camera_auto_detect=0` to match — the explicit
   overlay and the probe must not both run. Clearing the variable reverses
   both. See what this Pi has:
   `ls /boot/firmware/overlays/ | grep -E 'imx|ov[0-9]'`
5. Read `dmesg` — the three outcomes are unambiguous, and this split is the
   whole diagnostic:
   | `sudo dmesg \| grep -i imx219` | Meaning |
   |---|---|
   | `failed to read chip id` | Driver loaded, sensor unreachable: cable, orientation, or dead module |
   | Registers / dependency-cycle lines | Working |
   | No mention at all | The overlay did not load |
6. **Set the matching tuning**, or the colour will be wrong in a new way. Do
   not guess — shoot the same scene through both and pick, it takes two
   minutes:
   ```yaml
   traincam_tuning_source: /usr/share/libcamera/ipa/rpi/vc4/imx219.json       # IR-filtered
   # traincam_tuning_source: /usr/share/libcamera/ipa/rpi/vc4/imx219_noir.json  # NoIR
   ```
7. **Check which sensor mode libcamera picked** — see below. This is the step
   that is easiest to skip and costs the most.

## Check the sensor mode after any camera change

libcamera picks a sensor mode to match the *aspect ratio* of the requested
output, which is often not the mode you want. On the IMX219 at 1280x720 it
chooses 1920x1080 — an **unbinned crop** of the 3280x2464 array, measured at
left 688, top 700. That is 58% of the sensor width: a keyhole instead of the
room, and a quarter of the light per pixel because nothing is binned.

`--mode 1640:1232` in `traincam_extra_opts` pins the full-FOV 2×2-binned mode
instead. Confirm which one is live — this reads the hardware, not the config:

```bash
v4l2-ctl -d /dev/v4l-subdev0 --get-subdev-fmt | grep -i width
v4l2-ctl -d /dev/v4l-subdev0 --get-subdev-selection target=crop
```

Full FOV reads `crop, Left 8, Top 8, Width 3280, Height 2464`. Anything else is
a crop.

Binning matters here more than it looks. Measured in a *lit* room at 33–41 lux
the AGC was already pegged at its ceiling — 66502 µs at gain 5.95 — and a layout
with tunnels is darker. Binning is 4× the photons per output pixel. The same
conclusion came out of testing the OV5647's unbinned 1920x1080 mode, which was
rejected as visibly darker and noisier.

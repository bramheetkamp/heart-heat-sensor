# Biometric Chest-Strap Wearable — Firmware (PoC)

nRF54L15 firmware for a sports biometric chest strap. It streams two
heat-flux core-temperature estimates (four TMP117 sensors) and an
electrodermal-activity / GSR signal over **ANT+ (primary)** and a custom
**BLE GATT service (secondary)**.

This is a **proof-of-concept**: enough to prove the sensor signals correlate.
No OTA, no deep power-management state machine, no settings UI.

---

## Assumptions (confirm before relying on a build)

These were the working assumptions when the firmware was written
(2026-06). Verify them against your installed tooling — the spec explicitly
asks for this because the ANT add-on moves fast.

| Item | Assumption | How to confirm |
|---|---|---|
| **NCS version** | nRF Connect SDK **v3.3.0** (latest 2026-06). nRF54L15 has been fully supported since NCS **2.8.0**. | `west list nrf` / NCS release notes |
| **ANT add-on** | ANT is an **add-on** (not in the default NCS manifest). Its releases are tagged to match `sdk-nrf` tags; nRF54L support landed in recent releases. Pulled in via `west.yml`. SoftDevice-style API (`sd_ant_*`). | ANT add-on *Compatibility* page + release notes; set the exact tag in `west.yml` |
| **TMP117 driver** | The Zephyr in-tree `ti,tmp116` driver covers the **TMP117**. Enabled with `CONFIG_TMP116=y`. | `zephyr/drivers/sensor/tmp116` |
| **WS2812** | Driven by `worldsemi,ws2812-spi` on SPIM21. | overlay |
| **Multiprotocol** | BLE + ANT coexist through the **MPSL** timeslot arbitration NCS provides. No hand-rolled timeslots. | `CONFIG_MPSL=y` |

> If the ANT add-on is **not** installed, the app still builds and runs
> BLE-only: `ant_profile.c` is fully guarded by `CONFIG_ANT` and degrades to a
> logged no-op.

---

## Architecture (text diagram)

```
                         +-----------------------------+
                         |          main.c             |
                         |  init order + sensor thread |
                         +--------------+--------------+
                                        | k_sleep(250 ms) loop
                                        v
                         +-----------------------------+
                         |   app_state.collect()       |  data aggregation
                         |   -> biometric_frame_t      |
                         +----+----------+---------+----+
                              |          |         |
                  +-----------+   +------+----+   +----------------+
                  v               v          v                    v
        +-----------------+ +-----------+ +-----------+   (battery flag)
        | temp_tmp117 (I2C)| | heatflux  | | eda_gsr   |
        |  4x TMP117       | | Fourier's | | SAADC +   |
        |  2 stacks        | |  law      | | exc. gate |
        +-----------------+ +-----------+ +-----------+
                              frame
                  +-----------+-----------+
                  v                       v
        +-------------------+   +-----------------------+
        | ant_profile (ANT+)|   | ble_service (BLE GATT)|   radios
        |  custom page, 4Hz |   |  4 chars + notify     |
        +-------------------+   +-----------------------+

   HMI:  buttons (gpio-keys)   leds (D1..D3)   status_led (WS2812)
```

One module = one responsibility, each with an `_init()`, a public `.h` API,
and private statics in the `.c`. The sensor sampling runs in its own Zephyr
thread; button debounce runs on the system workqueue; BLE/ANT run on their
stacks. `main.c` only wires things together.

---

## Build & flash

The firmware is a standard NCS application. Build from an NCS workspace that
includes the ANT add-on (see `west.yml` if you manage it freestanding).

### DK (nRF54L15 DK, J-Link on-board)

```sh
# from this directory (Firmware/biometric-wearable)
west build -b nrf54l15dk/nrf54l15/cpuapp .
west flash                 # J-Link via the DK
```

The DK overlay `boards/nrf54l15dk_nrf54l15_cpuapp.overlay` wires the TMP117
I²C bus, the EDA SAADC channel + excitation gate, and the WS2812 pixel. The
DK's own LEDs/buttons are reused. Pin choices in the overlay are placeholders —
jumper the DK to match or edit the overlay.

### Custom PCB (BodyTempSensor board, TC2030 SWD)

```sh
west build -b bodytemp_wearable/nrf54l15/cpuapp . --board-root .
west flash --runner jlink   # via the TC2030 (J2) pogo header
```

> The custom board under `boards/bodytemp_wearable/` is **scaffolded**: copy the
> exact SoC include, RAM/flash `chosen`, and flash partitioning from the
> installed NCS `nrf54l15dk` board files, then confirm every pin against the
> KiCad schematic before a board spin.

### Serial log

By default logging goes to the DK VCOM (115200 8N1). To use USB-C (J1)
instead, uncomment the USB CDC ACM block in `prj.conf`.

---

## ANT+ data page

Custom page, page number `0x10`, transmitted at ~4 Hz (channel period 8192).
RF frequency 2457 MHz (ANT+ network). All multi-byte fields little-endian.

| Byte | Field | Encoding |
|---|---|---|
| 0 | Page number | `0x10` |
| 1 | Fault/status flags | `APP_FLAG_*` bitmask |
| 2–3 | Core temp (stack 0) | int16, 0.01 °C |
| 4–5 | Skin temp (stack 0) | int16, 0.01 °C |
| 6–7 | EDA conductance | uint16, 0.1 µS |

> The ANT+ **managed network key** (from thisisant.com) must be set in
> `ant_profile.c` (`m_network_key`) before a Garmin will accept the broadcast
> on the ANT+ frequency. Zeros = public network (own-node bench testing only).

---

## BLE GATT service

Custom 128-bit service, base UUID `a0b4xxxx-7e9c-4f1a-9a1e-7c0ffeed0001`.
Device advertises as `BodyTempPoC`.

| Characteristic | UUID (xxxx) | Type | Properties | Payload |
|---|---|---|---|---|
| Service | `0000` | — | — | — |
| Skin temperature | `0001` | float32 °C (stack 0) | Read, Notify | 4 B |
| Core temperature | `0002` | float32 °C (stack 0) | Read, Notify | 4 B |
| EDA conductance | `0003` | float32 µS | Read, Notify | 4 B |
| Combined frame | `0004` | raw `biometric_frame_t` | Read, Notify | `sizeof(struct)` |

The combined characteristic is the whole `biometric_frame_t` copied byte for
byte (little-endian). A host script unpacks it directly; a production build
would version and explicitly serialise it.

---

## Status indicators

**WS2812 status pixel (LED1):**

| Colour | Meaning |
|---|---|
| White | Booting / init in progress |
| Blue | Advertising / ANT up, no central |
| Green | BLE connected, streaming |
| Red | Sensor fault (latched until reboot) |

**Discrete LEDs:** D1 = power/alive, D2 = charging, D3 = fault.

---

## Deferred work (TODO for the PoC)

- **Calibration constants** — `APP_R_PORON_K_M2_PER_W`, `APP_R_BODY_K_M2_PER_W`
  (heat-flux model) and `APP_EDA_US_PER_MV` (conductance scaling) are
  placeholders in `app_config.h`. Characterise per build.
- **ANT+ network key** — set the managed key in `ant_profile.c`.
- **Second button** — only ACT1 is populated; a disabled `button_1` child is in
  the board DTS. Enable it (no code change) when a second switch is fitted.
- **Battery STAT** — `battery.c` is stubbed unless the MCP73833 STAT1/STAT2 pins
  are routed to GPIO. Confirm on the schematic and add a `charger` node.
- **Custom board** — finalise SoC include, partitioning, and pin map against the
  KiCad schematic.
- **OTA** — out of scope for the PoC.
- **Long-press action** — currently only logged; wire it to a session
  start/stop when the logging path exists.

---

## File tree

```
biometric-wearable/
├── CMakeLists.txt        prj.conf        Kconfig        sample.yaml   west.yml
├── README.md
├── boards/
│   ├── nrf54l15dk_nrf54l15_cpuapp.overlay   (DK bring-up)
│   └── bodytemp_wearable/                    (custom PCB, scaffold)
├── src/
│   ├── main.c
│   ├── app/      app_config.h  app_data.h  app_state.[ch]
│   ├── sensors/  temp_tmp117.[ch]  eda_gsr.[ch]  heatflux.[ch]
│   ├── radio/    ant_profile.[ch]  ble_service.[ch]
│   ├── hmi/      buttons.[ch]  leds.[ch]  status_led.[ch]
│   └── util/     log_cfg.h  battery.[ch]
└── dts/bindings/  (none needed for the PoC — see README there)
```

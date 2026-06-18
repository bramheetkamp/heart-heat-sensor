# Custom devicetree bindings

This folder holds custom devicetree bindings if any peripheral needs one.

For the proof-of-concept **none are required**:

- **TMP117** uses the in-tree Zephyr binding `ti,tmp116` (it covers the TMP117).
- **WS2812** uses the in-tree `worldsemi,ws2812-spi` binding.
- **Buttons / LEDs** use the in-tree `gpio-keys` / `gpio-leds` bindings.
- The **EDA excitation gate** and **EDA ADC channel** are exposed through the
  standard `zephyr,user` node (`eda-gate-gpios` + `io-channels`), so no binding
  is needed.

Add a `*.yaml` binding here only if a future sensor needs properties the
in-tree bindings do not express.

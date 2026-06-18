/**
 * ============================================================================
 *  File:    status_led.h
 *  Purpose: Single WS2812 RGB status pixel (LED1) via the led_strip driver.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    One addressable WS2812C-2020 pixel conveys richer state than the discrete
 *    LEDs can: advertising, connected/transmitting, or fault. Callers set a
 *    semantic state and this module maps it to a colour.
 * ============================================================================
 */

#ifndef STATUS_LED_H_
#define STATUS_LED_H_

/** @brief High-level device states shown on the RGB pixel. */
typedef enum {
	STATUS_OFF = 0,
	STATUS_BOOTING,       /* white  - init in progress           */
	STATUS_ADVERTISING,   /* blue   - BLE advertising / ANT up    */
	STATUS_CONNECTED,     /* green  - link up, streaming frames    */
	STATUS_SENSOR_FAULT,  /* red    - one or more sensors faulted  */
} status_state_t;

/**
 * @brief  Initialise the WS2812 strip and show the booting colour.
 * @return 0 on success, negative errno if the strip is not ready.
 */
int status_led_init(void);

/**
 * @brief  Set the status colour for a high-level device state.
 * @param  state  Semantic state to display.
 */
void status_led_set(status_state_t state);

#endif /* STATUS_LED_H_ */

/**
 * ============================================================================
 *  File:    status_led.c
 *  Purpose: WS2812 single-pixel status indicator via Zephyr led_strip.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Drives the single WS2812C-2020 pixel (LED1) through the Zephyr led_strip
 *    API. The strip device (SPI- or PWM-backed) is selected in the board
 *    overlay via the chosen `zephyr,led-strip` or a labelled node; this file
 *    only knows there is one pixel and which colour each state maps to.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "status_led.h"
#include "app_config.h"
#include "util/log_cfg.h"

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/led_strip.h>

LOG_MODULE_REGISTER(status_led, APP_LOG_LEVEL);

/* ============================================================
 *  DEFINES / BINDING
 * ============================================================ */

/* The board overlay marks the WS2812 node as chosen "zephyr,led-strip". */
#define STRIP_NODE      DT_CHOSEN(zephyr_led_strip)
#define STRIP_NUM_PIXELS 1

/* Keep the brightness modest — this is an indicator, not a torch. */
#define LVL 0x20

/* ============================================================
 *  STATIC GLOBALS
 * ============================================================ */
static const struct device *m_strip = DEVICE_DT_GET(STRIP_NODE);
static struct led_rgb m_pixel; /* single-pixel frame buffer */
static bool m_ready;

/* ============================================================
 *  PRIVATE FUNCTION PROTOTYPES
 * ============================================================ */
static void show(uint8_t r, uint8_t g, uint8_t b);

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Initialise the WS2812 strip and show the booting colour.
 * @return 0 on success, negative errno if the strip is not ready.
 */
int status_led_init(void)
{
	if (!device_is_ready(m_strip)) {
		LOG_ERR("WS2812 strip not ready");
		return -ENODEV;
	}

	m_ready = true;
	status_led_set(STATUS_BOOTING);
	LOG_INF("Status LED ready");
	return 0;
}

/**
 * @brief  Set the status colour for a high-level device state.
 * @param  state  Semantic state to display.
 */
void status_led_set(status_state_t state)
{
	switch (state) {
	case STATUS_OFF:          show(0,   0,   0);   break;
	case STATUS_BOOTING:      show(LVL, LVL, LVL); break; /* white */
	case STATUS_ADVERTISING:  show(0,   0,   LVL); break; /* blue  */
	case STATUS_CONNECTED:    show(0,   LVL, 0);   break; /* green */
	case STATUS_SENSOR_FAULT: show(LVL, 0,   0);   break; /* red   */
	default:                  show(0,   0,   0);   break;
	}
}

/* ============================================================
 *  PRIVATE FUNCTIONS
 * ============================================================ */

/**
 * @brief  Push one RGB colour to the single pixel.
 * @param  r  Red   channel (0-255, pre-scaled by caller).
 * @param  g  Green channel.
 * @param  b  Blue  channel.
 *
 * led_strip_update_rgb transmits the whole strip; with one pixel that is a
 * single short SPI/PWM burst, cheap enough to call on every state change.
 */
static void show(uint8_t r, uint8_t g, uint8_t b)
{
	if (!m_ready) {
		return;
	}

	m_pixel.r = r;
	m_pixel.g = g;
	m_pixel.b = b;

	int rc = led_strip_update_rgb(m_strip, &m_pixel, STRIP_NUM_PIXELS);
	if (rc != 0) {
		LOG_WRN("WS2812 update failed (%d)", rc);
	}
}

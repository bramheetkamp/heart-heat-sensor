/**
 * ============================================================================
 *  File:    leds.c
 *  Purpose: Discrete GPIO LED control (D1/D2/D3).
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Drives the three discrete indicator LEDs declared under the devicetree
 *    `leds` (gpio-leds) node. The role enum maps onto devicetree child order,
 *    so re-routing an LED is a board-file change, not a code change.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "leds.h"
#include "app_config.h"
#include "util/log_cfg.h"

#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>

LOG_MODULE_REGISTER(leds, APP_LOG_LEVEL);

/* ============================================================
 *  DEFINES
 * ============================================================ */
#define LEDS_NODE          DT_NODELABEL(leds)
#define LED_SPEC(node_id)  GPIO_DT_SPEC_GET(node_id, gpios),

/* ============================================================
 *  STATIC GLOBALS
 * ============================================================ */
static const struct gpio_dt_spec m_leds[] = {
	DT_FOREACH_CHILD_STATUS_OKAY(LEDS_NODE, LED_SPEC)
};

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Initialise the discrete LEDs (all start off).
 * @return 0 on success, negative errno if none are usable.
 */
int leds_init(void)
{
	unsigned int ok = 0U;

	for (size_t i = 0; i < ARRAY_SIZE(m_leds); i++) {
		if (!gpio_is_ready_dt(&m_leds[i])) {
			LOG_WRN("LED %u not ready", (unsigned)i);
			continue;
		}
		if (gpio_pin_configure_dt(&m_leds[i], GPIO_OUTPUT_INACTIVE) == 0) {
			ok++;
		}
	}

	if (ok == 0U) {
		LOG_ERR("No usable discrete LEDs");
		return -ENODEV;
	}

	LOG_INF("Discrete LEDs init: %u LED(s)", ok);
	return 0;
}

/**
 * @brief  Set one discrete LED on or off.
 * @param  role  Which LED (see led_role_t).
 * @param  on    true to light it, false to clear it.
 */
void leds_set(led_role_t role, bool on)
{
	/* Guard against a role with no populated LED (e.g. fewer than 3 fitted). */
	if ((size_t)role >= ARRAY_SIZE(m_leds)) {
		return;
	}
	(void)gpio_pin_set_dt(&m_leds[role], on ? 1 : 0);
}

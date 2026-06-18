/**
 * ============================================================================
 *  File:    battery.c
 *  Purpose: Decode MCP73833 STAT1/STAT2 charge status (optional).
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    The MCP73833 exposes two open-drain status outputs. Their truth table
 *    (active-low, pulled up to the MCU rail) is:
 *        STAT1  STAT2   meaning
 *          L      H     charging
 *          H      L     charge complete
 *          L      L     (used by some configs) / system test
 *          H      H     standby / no battery / fault
 *
 *  TODO(PoC): confirm STAT1/STAT2 are actually routed to MCU GPIO on the
 *  schematic. If they are, declare a `charger` node with stat1-gpios/stat2-gpios
 *  in the board files; if not, this module stays stubbed and reports UNKNOWN.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "battery.h"
#include "app_config.h"
#include "util/log_cfg.h"

#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>

LOG_MODULE_REGISTER(battery, APP_LOG_LEVEL);

/* ============================================================
 *  DEVICETREE BINDING (compile-time optional)
 * ============================================================ */

/*
 * Only build the real implementation if a `charger` node with both STAT GPIOs
 * exists. Otherwise everything below collapses to the UNKNOWN stub, satisfying
 * the spec's "stub with a TODO if not routed" requirement.
 */
#define CHARGER_NODE DT_NODELABEL(charger)

#if DT_NODE_HAS_PROP(CHARGER_NODE, stat1_gpios) && \
	DT_NODE_HAS_PROP(CHARGER_NODE, stat2_gpios)
#define BATTERY_STAT_ROUTED 1
#else
#define BATTERY_STAT_ROUTED 0
#endif

#if BATTERY_STAT_ROUTED
static const struct gpio_dt_spec m_stat1 =
	GPIO_DT_SPEC_GET(CHARGER_NODE, stat1_gpios);
static const struct gpio_dt_spec m_stat2 =
	GPIO_DT_SPEC_GET(CHARGER_NODE, stat2_gpios);
static bool m_ready;
#endif

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Initialise the STAT GPIO inputs if they exist in devicetree.
 * @return 0 on success (or when stubbed out), negative errno on GPIO error.
 */
int battery_init(void)
{
#if BATTERY_STAT_ROUTED
	if (!gpio_is_ready_dt(&m_stat1) || !gpio_is_ready_dt(&m_stat2)) {
		LOG_WRN("Charger STAT GPIOs not ready");
		return -ENODEV;
	}
	int rc = gpio_pin_configure_dt(&m_stat1, GPIO_INPUT);
	rc |= gpio_pin_configure_dt(&m_stat2, GPIO_INPUT);
	if (rc != 0) {
		LOG_WRN("Charger STAT config failed (%d)", rc);
		return rc;
	}
	m_ready = true;
	LOG_INF("Battery STAT inputs ready");
	return 0;
#else
	LOG_INF("Charger STAT not routed; battery state stubbed (TODO)");
	return 0;
#endif
}

/**
 * @brief  Read the current charge state.
 * @return One of battery_state_t; BATTERY_UNKNOWN if STAT pins are not routed.
 */
battery_state_t battery_get_state(void)
{
#if BATTERY_STAT_ROUTED
	if (!m_ready) {
		return BATTERY_UNKNOWN;
	}

	/* GPIO flags in devicetree make these logical (active-low handled there). */
	int s1 = gpio_pin_get_dt(&m_stat1); /* 1 == asserted */
	int s2 = gpio_pin_get_dt(&m_stat2);

	if (s1 == 1 && s2 == 0) {
		return BATTERY_CHARGING;
	}
	if (s1 == 0 && s2 == 1) {
		return BATTERY_CHARGED;
	}
	if (s1 == 0 && s2 == 0) {
		return BATTERY_FAULT;
	}
	return BATTERY_UNKNOWN; /* both de-asserted: standby / no battery */
#else
	return BATTERY_UNKNOWN;
#endif
}

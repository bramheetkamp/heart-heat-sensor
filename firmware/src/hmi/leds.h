/**
 * ============================================================================
 *  File:    leds.h
 *  Purpose: Discrete GPIO status LEDs (D1, D2, D3).
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Thin wrapper over the devicetree `leds` (gpio-leds) node for the three
 *    discrete indicator LEDs. Logical roles are given names so callers say
 *    "fault LED on" rather than juggling array indices.
 * ============================================================================
 */

#ifndef LEDS_H_
#define LEDS_H_

#include <stdbool.h>
#include <stdint.h>

/** @brief Logical roles mapped onto the discrete LEDs in devicetree order. */
typedef enum {
	LED_ROLE_POWER = 0, /* D1: powered / alive   */
	LED_ROLE_CHARGE,    /* D2: charging          */
	LED_ROLE_FAULT,     /* D3: sensor/system fault */
	LED_ROLE_COUNT,
} led_role_t;

/**
 * @brief  Initialise the discrete LEDs (all start off).
 * @return 0 on success, negative errno if none are usable.
 */
int leds_init(void);

/**
 * @brief  Set one discrete LED on or off.
 * @param  role  Which LED (see led_role_t).
 * @param  on    true to light it, false to clear it.
 */
void leds_set(led_role_t role, bool on);

#endif /* LEDS_H_ */

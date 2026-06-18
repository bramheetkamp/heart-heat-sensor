/**
 * ============================================================================
 *  File:    battery.h
 *  Purpose: MCP73833 charge-status read (optional).
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    If the MCP73833 STAT1/STAT2 open-drain status pins are routed to GPIO,
 *    this module decodes them into a charge state. If they are not routed the
 *    module compiles to stubs that report UNKNOWN, so the rest of the firmware
 *    does not care whether the strap senses charging.
 * ============================================================================
 */

#ifndef BATTERY_H_
#define BATTERY_H_

/** @brief Decoded MCP73833 charge state. */
typedef enum {
	BATTERY_UNKNOWN = 0, /* STAT pins not routed / indeterminate */
	BATTERY_CHARGING,    /* charge in progress                   */
	BATTERY_CHARGED,     /* charge complete                      */
	BATTERY_FAULT,       /* charger fault / no battery           */
} battery_state_t;

/**
 * @brief  Initialise the STAT GPIO inputs if they exist in devicetree.
 * @return 0 on success (or when stubbed out), negative errno on GPIO error.
 */
int battery_init(void);

/**
 * @brief  Read the current charge state.
 * @return One of battery_state_t; BATTERY_UNKNOWN if STAT pins are not routed.
 */
battery_state_t battery_get_state(void);

#endif /* BATTERY_H_ */

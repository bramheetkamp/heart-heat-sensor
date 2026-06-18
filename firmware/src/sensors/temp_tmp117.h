/**
 * ============================================================================
 *  File:    temp_tmp117.h
 *  Purpose: Public API for the four-TMP117 heat-flux temperature front-end.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Wraps the Zephyr in-tree tmp116 driver (which also covers the TMP117)
 *    behind a "stack" view: two sensors per heat-flux stack, skin-side and
 *    ambient-side. Bus and I2C address live entirely in devicetree, so this
 *    header exposes only logical stack IDs.
 * ============================================================================
 */

#ifndef TEMP_TMP117_H_
#define TEMP_TMP117_H_

#include "app_data.h"

/**
 * @brief  Initialise every TMP117 referenced by devicetree.
 * @return 0 if at least one sensor is ready, negative errno if none are.
 *
 * Each sensor is checked for readiness and configured for continuous
 * conversion with averaging. A single missing sensor is logged and marked
 * faulted rather than failing the whole init.
 */
int temp_tmp117_init(void);

/**
 * @brief  Read both temperatures of one heat-flux stack.
 * @param  stack_id  Stack index [0 .. APP_NUM_HEATFLUX_STACKS-1].
 * @param  out       Filled with skin-side and ambient-side temps; .valid is
 *                   set false if either sensor faulted.
 * @return 0 on success, negative errno on bad arg or full I2C failure.
 *
 * On a transient I2C error the read is retried once before the sensor is
 * marked faulted; the call never blocks indefinitely.
 */
int temp_tmp117_read_stack(uint8_t stack_id, tmp_pair_t *out);

#endif /* TEMP_TMP117_H_ */

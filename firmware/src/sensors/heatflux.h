/**
 * ============================================================================
 *  File:    heatflux.h
 *  Purpose: Fourier's-law core-temperature estimation from a TMP117 pair.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Pure maths, no hardware. Given the skin-side and ambient-side temperature
 *    of a heat-flux stack and the known thermal resistance of the Poron
 *    insulator between them, compute the heat flux and back out an estimated
 *    body-core temperature.
 * ============================================================================
 */

#ifndef HEATFLUX_H_
#define HEATFLUX_H_

#include "app_data.h"

/**
 * @brief  Estimate core temperature for one heat-flux stack.
 * @param  pair  Validated skin/ambient temperature pair for the stack.
 * @param  out   Filled with heat flux (W/m^2) and core temp (deg C).
 * @return 0 on success, negative errno if the input pair is invalid.
 *
 * If pair->valid is false the result is marked invalid and -EINVAL returned;
 * the caller should not propagate stale numbers downstream.
 */
int heatflux_estimate_core(const tmp_pair_t *pair, heatflux_result_t *out);

#endif /* HEATFLUX_H_ */

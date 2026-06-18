/**
 * ============================================================================
 *  File:    heatflux.c
 *  Purpose: Core-temperature estimate from a dual-TMP117 heat-flux stack.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Implements the dual-heat-flux core-temperature model. Two temperature
 *    sensors sandwich a Poron insulator of known thermal resistance. The
 *    temperature drop across that insulator gives the heat flux leaving the
 *    body (Fourier's law). Extrapolating that same flux back through the
 *    tissue between core and skin gives an estimate of core temperature.
 *
 *    All calibration constants live in app_config.h and are PLACEHOLDER values
 *    for the proof-of-concept; this file only contains the relationships, not
 *    the tuning.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "heatflux.h"
#include "app_config.h"
#include "util/log_cfg.h"

LOG_MODULE_REGISTER(heatflux, APP_LOG_LEVEL);

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Estimate core temperature for one heat-flux stack.
 * @param  pair  Validated skin/ambient temperature pair for the stack.
 * @param  out   Filled with heat flux (W/m^2) and core temp (deg C).
 * @return 0 on success, negative errno if the input pair is invalid.
 */
int heatflux_estimate_core(const tmp_pair_t *pair, heatflux_result_t *out)
{
	if (pair == NULL || out == NULL) {
		return -EINVAL;
	}

	if (!pair->valid) {
		out->valid = false;
		out->heat_flux_w_m2 = 0.0f;
		out->core_temp_c = 0.0f;
		return -EINVAL;
	}

	/*
	 * Fourier's law across the Poron layer:
	 *   q = dT / R_poron   [ (K) / (K*m^2/W) = W/m^2 ]
	 * Positive flux means heat leaving the body (skin warmer than ambient
	 * side), which is the normal case for a worn strap.
	 */
	float dT = pair->skin_temp_c - pair->ambient_temp_c;
	float q  = dT / APP_R_PORON_K_M2_PER_W;

	/*
	 * Same flux is assumed to flow through the tissue between core and skin,
	 * so the core sits R_body worth of temperature rise above the skin:
	 *   T_core = T_skin + q * R_body
	 * This is the classic dual-heat-flux extrapolation; accuracy depends
	 * entirely on the PLACEHOLDER resistances until calibrated.
	 */
	float core = pair->skin_temp_c + q * APP_R_BODY_K_M2_PER_W;

	out->heat_flux_w_m2 = q;
	out->core_temp_c = core;
	out->valid = true;

	LOG_DBG("dT=%.3f q=%.2f W/m^2 core=%.3f C",
		(double)dT, (double)q, (double)core);
	return 0;
}

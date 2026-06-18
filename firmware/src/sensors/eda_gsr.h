/**
 * ============================================================================
 *  File:    eda_gsr.h
 *  Purpose: Public API for the EDA / GSR analog front-end (SAADC).
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Reads the MCP6001 transimpedance-amplifier output on one nRF SAADC
 *    channel while gating the skin-excitation drive through a GPIO. Returns a
 *    calibrated skin-conductance value plus the raw code for debugging.
 * ============================================================================
 */

#ifndef EDA_GSR_H_
#define EDA_GSR_H_

#include "app_data.h"

/**
 * @brief  Initialise the SAADC channel and the excitation gate GPIO.
 * @return 0 on success, negative errno on ADC or GPIO setup failure.
 */
int eda_gsr_init(void);

/**
 * @brief  Take one EDA sample: excite, settle, read, optionally gate off.
 * @param  out  Filled with raw counts, calibrated mV, and conductance.
 * @return 0 on success, negative errno on ADC read failure.
 */
int eda_gsr_sample(eda_sample_t *out);

#endif /* EDA_GSR_H_ */

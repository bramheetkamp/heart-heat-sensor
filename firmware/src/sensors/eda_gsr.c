/**
 * ============================================================================
 *  File:    eda_gsr.c
 *  Purpose: Electrodermal-activity (GSR) front-end: SAADC + excitation gate.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    The EDA signal is the voltage at the output of an MCP6001 transimpedance
 *    amplifier (U5). To read skin conductance we briefly energise the
 *    electrodes through a GPIO-controlled excitation gate, wait a short settle
 *    time so the electrode/skin interface stops polarising, sample the SAADC,
 *    then (optionally) switch the excitation back off to save current and
 *    limit long-term electrode drift.
 *
 *    The ADC channel and the excitation GPIO both come from devicetree (the
 *    `zephyr,user` node and a gpio property), so pin choices stay in the board
 *    overlay, not in this file.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "eda_gsr.h"
#include "app_config.h"
#include "util/log_cfg.h"

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/drivers/gpio.h>

LOG_MODULE_REGISTER(eda_gsr, APP_LOG_LEVEL);

/* ============================================================
 *  DEVICETREE BINDING
 * ============================================================ */

/*
 * The SAADC channel for the GSR signal is declared as the first io-channel of
 * the `zephyr,user` node in the board overlay. ADC_DT_SPEC_GET_BY_IDX pulls
 * the controller, channel id, gain, reference and resolution from devicetree.
 */
static const struct adc_dt_spec m_adc =
	ADC_DT_SPEC_GET_BY_IDX(DT_PATH(zephyr_user), 0);

/*
 * Excitation gate: a GPIO that powers the electrode drive. Declared as
 * `eda-gate-gpios` on the same `zephyr,user` node.
 */
static const struct gpio_dt_spec m_gate =
	GPIO_DT_SPEC_GET(DT_PATH(zephyr_user), eda_gate_gpios);

/* ============================================================
 *  STATIC GLOBALS
 * ============================================================ */
static int16_t  m_sample_buf;   /* SAADC landing buffer (12-bit -> int16) */
static bool     m_ready;        /* init succeeded                          */

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Initialise the SAADC channel and the excitation gate GPIO.
 * @return 0 on success, negative errno on ADC or GPIO setup failure.
 */
int eda_gsr_init(void)
{
	int rc;

	if (!adc_is_ready_dt(&m_adc)) {
		LOG_ERR("SAADC device not ready");
		return -ENODEV;
	}

	rc = adc_channel_setup_dt(&m_adc);
	if (rc != 0) {
		LOG_ERR("SAADC channel setup failed (%d)", rc);
		return rc;
	}

	if (!gpio_is_ready_dt(&m_gate)) {
		LOG_ERR("EDA gate GPIO not ready");
		return -ENODEV;
	}

	/* Start with excitation off; each sample turns it on just long enough. */
	rc = gpio_pin_configure_dt(&m_gate, GPIO_OUTPUT_INACTIVE);
	if (rc != 0) {
		LOG_ERR("EDA gate config failed (%d)", rc);
		return rc;
	}

	m_ready = true;
	LOG_INF("EDA/GSR ready (%d-bit, gain 1/2, VDD ref)",
		APP_EDA_ADC_RESOLUTION_BITS);
	return 0;
}

/**
 * @brief  Take one EDA sample: excite, settle, read, optionally gate off.
 * @param  out  Filled with raw counts, calibrated mV, and conductance.
 * @return 0 on success, negative errno on ADC read failure.
 */
int eda_gsr_sample(eda_sample_t *out)
{
	if (out == NULL) {
		return -EINVAL;
	}
	if (!m_ready) {
		out->valid = false;
		return -ENODEV;
	}

	struct adc_sequence seq = {
		.buffer      = &m_sample_buf,
		.buffer_size = sizeof(m_sample_buf),
	};
	(void)adc_sequence_init_dt(&m_adc, &seq);

	/*
	 * 1) Energise the electrodes. 2) Wait APP_EDA_SETTLE_US: the skin/gel
	 *    interface behaves like a slow RC and polarises right after drive is
	 *    applied; sampling too early reads the transient, not the conductance.
	 *    k_busy_wait keeps the ~200 us delay tight without a context switch.
	 */
	gpio_pin_set_dt(&m_gate, 1);
	k_busy_wait(APP_EDA_SETTLE_US);

	int rc = adc_read_dt(&m_adc, &seq);

	/*
	 * 3) Duty-cycle the excitation off again. Leaving it on continuously both
	 *    wastes battery and drives slow electrode polarization that corrupts
	 *    later samples; gating between reads keeps the baseline stable.
	 */
	if (APP_EDA_GATE_OFF_AFTER_SAMPLE) {
		gpio_pin_set_dt(&m_gate, 0);
	}

	if (rc != 0) {
		LOG_WRN("SAADC read failed (%d)", rc);
		out->valid = false;
		return rc;
	}

	/* Raw code (clamp any negative offset code to zero for the unsigned field). */
	int32_t raw = m_sample_buf;
	out->raw_counts = (raw < 0) ? 0U : (uint16_t)raw;

	/*
	 * Convert the raw code to input millivolts using the devicetree gain and
	 * reference via Zephyr's helper, then scale to microsiemens with the
	 * PLACEHOLDER calibration constant.
	 */
	int32_t mv = raw;
	rc = adc_raw_to_millivolts_dt(&m_adc, &mv);
	if (rc != 0) {
		LOG_WRN("ADC mV conversion failed (%d)", rc);
		out->valid = false;
		return rc;
	}

	out->input_mv = mv;
	out->conductance_us = (float)mv * APP_EDA_US_PER_MV;
	out->valid = true;

	LOG_DBG("EDA raw=%u mv=%d G=%.2f uS",
		out->raw_counts, mv, (double)out->conductance_us);
	return 0;
}

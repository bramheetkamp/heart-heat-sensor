/**
 * ============================================================================
 *  File:    app_state.c
 *  Purpose: Collect, fuse, and cache the biometric frame.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Owns the data-aggregation step described in the spec. Each collect()
 *    walks the two heat-flux stacks (TMP117 pair -> Fourier's-law core temp),
 *    takes one EDA sample, folds in the battery charge flag, stamps the
 *    uptime, and records fault bits. The assembled frame is both returned to
 *    the caller (for immediate radio hand-off) and cached under a mutex for
 *    any asynchronous reader.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "app_state.h"
#include "app_config.h"
#include "util/log_cfg.h"

#include "sensors/temp_tmp117.h"
#include "sensors/heatflux.h"
#include "sensors/eda_gsr.h"
#include "util/battery.h"

#include <zephyr/kernel.h>
#include <string.h>

LOG_MODULE_REGISTER(app_state, APP_LOG_LEVEL);

/* ============================================================
 *  STATIC GLOBALS
 * ============================================================ */
static struct k_mutex     m_lock;          /* guards m_latest          */
static biometric_frame_t  m_latest;        /* cached newest frame      */

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Initialise the shared-state mutex.
 * @return 0 always.
 */
int app_state_init(void)
{
	k_mutex_init(&m_lock);
	memset(&m_latest, 0, sizeof(m_latest));
	return 0;
}

/**
 * @brief  Sample every sensor, fuse, and produce one biometric frame.
 * @param  out  Filled with the freshly collected, timestamped frame.
 * @return 0 if the frame is usable, negative errno if every sensor faulted.
 */
int app_state_collect(biometric_frame_t *out)
{
	if (out == NULL) {
		return -EINVAL;
	}

	memset(out, 0, sizeof(*out));
	out->timestamp_ms = k_uptime_get_32();

	unsigned int good = 0U;

	/* --- Heat-flux stacks: read pair, then estimate core temperature. --- */
	for (uint8_t i = 0; i < APP_NUM_HEATFLUX_STACKS; i++) {
		int rc = temp_tmp117_read_stack(i, &out->stack[i]);
		if (rc == 0 && out->stack[i].valid) {
			(void)heatflux_estimate_core(&out->stack[i], &out->core[i]);
			good++;
		} else {
			out->flags |= (i == 0) ? APP_FLAG_STACK0_FAULT
					       : APP_FLAG_STACK1_FAULT;
			out->core[i].valid = false;
		}
	}

	/* --- EDA / GSR --- */
	if (eda_gsr_sample(&out->eda) == 0 && out->eda.valid) {
		good++;
	} else {
		out->flags |= APP_FLAG_EDA_FAULT;
	}

	/* --- Battery charge flag (best-effort; UNKNOWN leaves the bit clear). */
	if (battery_get_state() == BATTERY_CHARGING) {
		out->flags |= APP_FLAG_BATT_CHARGING;
	}

	/* Cache the snapshot for asynchronous consumers (BLE notify/read). */
	k_mutex_lock(&m_lock, K_FOREVER);
	memcpy(&m_latest, out, sizeof(m_latest));
	k_mutex_unlock(&m_lock);

	if (good == 0U) {
		LOG_WRN("All sensors faulted this tick (flags=0x%02x)", out->flags);
		return -EIO;
	}
	return 0;
}

/**
 * @brief  Copy the most recently collected frame.
 * @param  out  Destination for the cached snapshot.
 */
void app_state_get_latest(biometric_frame_t *out)
{
	if (out == NULL) {
		return;
	}
	k_mutex_lock(&m_lock, K_FOREVER);
	memcpy(out, &m_latest, sizeof(*out));
	k_mutex_unlock(&m_lock);
}

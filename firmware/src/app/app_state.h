/**
 * ============================================================================
 *  File:    app_state.h
 *  Purpose: App-level data aggregation and sensor-fusion glue.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    The seam between the sensor layer and the radios. app_state collects one
 *    reading from every sensor, runs the heat-flux maths, and assembles a
 *    single biometric_frame_t. It also caches the most recent frame behind a
 *    mutex so asynchronous consumers (a BLE read or notify timer) get a
 *    consistent snapshot without racing the sensor thread.
 * ============================================================================
 */

#ifndef APP_STATE_H_
#define APP_STATE_H_

#include "app_data.h"

/**
 * @brief  Initialise the shared-state mutex.
 * @return 0 always (kept as int for call-site symmetry with other inits).
 */
int app_state_init(void);

/**
 * @brief  Sample every sensor, fuse, and produce one biometric frame.
 * @param  out  Filled with the freshly collected, timestamped frame.
 * @return 0 if the frame is usable, negative errno if every sensor faulted.
 *
 * Partial faults do not fail the call: faulted sub-readings set their fault
 * flag in out->flags and leave their fields invalid, but a usable frame is
 * still produced and cached.
 */
int app_state_collect(biometric_frame_t *out);

/**
 * @brief  Copy the most recently collected frame.
 * @param  out  Destination for the cached snapshot.
 *
 * Safe to call from any thread; takes the state mutex internally.
 */
void app_state_get_latest(biometric_frame_t *out);

#endif /* APP_STATE_H_ */

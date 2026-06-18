/**
 * ============================================================================
 *  File:    app_data.h
 *  Purpose: Shared data types passed between sensors, fusion, and radios.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    The "contract" of the firmware. Every module speaks in these structs so
 *    the sensor layer, the heat-flux maths, and the two radio back-ends never
 *    need to know each other's internals. A biometric_frame_t is the single
 *    unit of data the device produces each sample tick and ships over both
 *    ANT+ and BLE.
 * ============================================================================
 */

#ifndef APP_DATA_H_
#define APP_DATA_H_

#include <stdint.h>
#include <stdbool.h>
#include "app_config.h"

/* ============================================================
 *  FAULT FLAGS  (bitmask in biometric_frame_t.flags)
 * ============================================================ */

#define APP_FLAG_STACK0_FAULT   (1U << 0) /* TMP117 pair 0 unreadable     */
#define APP_FLAG_STACK1_FAULT   (1U << 1) /* TMP117 pair 1 unreadable     */
#define APP_FLAG_EDA_FAULT      (1U << 2) /* SAADC / GSR read failed      */
#define APP_FLAG_BATT_CHARGING  (1U << 3) /* charger STAT = charging      */

/* ============================================================
 *  PER-SENSOR / PER-STACK TYPES
 * ============================================================ */

/**
 * @brief One heat-flux stack's raw temperature pair.
 *
 * skin_temp_c is the body-facing TMP117, ambient_temp_c the outward-facing
 * one. valid is false if either sensor faulted on this sample.
 */
typedef struct {
	float skin_temp_c;
	float ambient_temp_c;
	bool  valid;
} tmp_pair_t;

/**
 * @brief Result of the Fourier's-law core-temperature estimate for a stack.
 */
typedef struct {
	float heat_flux_w_m2;  /* heat flux through the Poron layer   */
	float core_temp_c;     /* estimated body core temperature     */
	bool  valid;
} heatflux_result_t;

/**
 * @brief One electrodermal-activity (GSR) sample.
 */
typedef struct {
	uint16_t raw_counts;     /* unscaled SAADC code                 */
	int32_t  input_mv;       /* calibrated input voltage in mV      */
	float    conductance_us; /* skin conductance in microsiemens    */
	bool     valid;
} eda_sample_t;

/* ============================================================
 *  AGGREGATE FRAME
 * ============================================================ */

/**
 * @brief The complete biometric snapshot produced each sample tick.
 *
 * This is what the aggregation step assembles and what both radio modules
 * serialise. Keep it POD and self-describing so it maps cleanly onto an ANT
 * data page and a BLE characteristic payload.
 */
typedef struct {
	uint32_t          timestamp_ms;                  /* uptime at capture   */
	tmp_pair_t        stack[APP_NUM_HEATFLUX_STACKS];
	heatflux_result_t core[APP_NUM_HEATFLUX_STACKS];
	eda_sample_t      eda;
	uint8_t           flags;                         /* APP_FLAG_* bitmask  */
} biometric_frame_t;

#endif /* APP_DATA_H_ */

/**
 * ============================================================================
 *  File:    app_config.h
 *  Purpose: Central tunables for the biometric chest-strap firmware.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    One place for every number a bring-up engineer might want to turn:
 *    sample rates, heat-flux calibration constants, EDA timing, BLE/ANT
 *    cadence and identifiers. Nothing here touches hardware directly; the
 *    modules read these macros so behaviour can be retuned without hunting
 *    through .c files. Anything marked PLACEHOLDER is calibration that the
 *    proof-of-concept defers (see the TODO list in README.md).
 * ============================================================================
 */

#ifndef APP_CONFIG_H_
#define APP_CONFIG_H_

/* ============================================================
 *  SAMPLING CADENCE
 * ============================================================ */

/*
 * Master sensor-loop period. Skin/core temperature changes slowly, EDA a
 * little faster, so a single 4 Hz loop is plenty for a PoC and lines up
 * neatly with the ANT broadcast period below (one fresh frame per TX).
 */
#define APP_SENSOR_SAMPLE_PERIOD_MS   250U

/* Number of heat-flux stacks on the strap (two TMP117 pairs). */
#define APP_NUM_HEATFLUX_STACKS       2U

/* Sensors per stack: skin-side + ambient-side. */
#define APP_SENSORS_PER_STACK         2U

/* ============================================================
 *  HEAT-FLUX / CORE-TEMP MODEL  (Fourier's law)
 * ============================================================ */

/*
 * Thermal resistance of the Poron insulator layer that separates the
 * skin-side and ambient-side TMP117 of one stack. Heat flux through the
 * stack is q = (T_skin - T_ambient) / R_PORON  [W/m^2].
 *
 * PLACEHOLDER: this value must be characterised per build (insulator
 * thickness, contact pressure). The number below is a rough first guess
 * for a ~1.5 mm Poron pad and only exists so the maths produces sane
 * magnitudes during bring-up.
 */
#define APP_R_PORON_K_M2_PER_W        0.045f

/*
 * Effective tissue thermal resistance between the body core and the skin
 * surface. Core estimate is T_core = T_skin + q * R_BODY. Also PLACEHOLDER
 * pending a clinical calibration pass.
 */
#define APP_R_BODY_K_M2_PER_W         0.075f

/* Reject obviously broken readings before they reach the model. */
#define APP_TEMP_MIN_VALID_C          (-10.0f)
#define APP_TEMP_MAX_VALID_C          (60.0f)

/* ============================================================
 *  EDA / GSR FRONT-END  (SAADC + excitation gate)
 * ============================================================ */

/*
 * Settle time after enabling the excitation gate before we sample. The skin
 * electrode interface polarises quickly; ~200 us lets the MCP6001 TIA output
 * stabilise without driving the electrodes long enough to cause drift.
 */
#define APP_EDA_SETTLE_US             200U

/*
 * Gate the excitation off again after each sample. Duty-cycling the drive
 * saves current and limits electrode polarization over a long session.
 * Set to 0 to leave excitation always on (useful when scoping the signal).
 */
#define APP_EDA_GATE_OFF_AFTER_SAMPLE 1

/* SAADC: VDD reference (3.3 V), gain 1/2, 12-bit -> full scale 6.6 V. */
#define APP_EDA_ADC_RESOLUTION_BITS   12
#define APP_EDA_ADC_VREF_MV           3300
#define APP_EDA_ADC_GAIN_NUM          1   /* gain = NUM/DEN = 1/2 */
#define APP_EDA_ADC_GAIN_DEN          2

/*
 * PLACEHOLDER conductance scaling. Converts the calibrated input millivolts
 * into microsiemens for the chosen TIA feedback resistor and excitation
 * voltage. Replace after a two-point resistor calibration.
 */
#define APP_EDA_US_PER_MV             0.10f

/* ============================================================
 *  BLE  (custom GATT biometric service)
 * ============================================================ */

/* How often connected notifications are pushed, independent of sampling. */
#define APP_BLE_NOTIFY_PERIOD_MS      1000U

/* Advertised device name (also set via CONFIG_BT_DEVICE_NAME in prj.conf). */
#define APP_BLE_DEVICE_NAME           "BodyTempPoC"

/* ============================================================
 *  ANT+  (primary protocol — custom broadcast page)
 * ============================================================ */

/*
 * ANT channel identity. Device number 0 lets the receiver pair to any unit;
 * pick a fixed non-zero number for a specific strap. Device type and
 * transmission type are custom for this PoC page (not a standard ANT+
 * profile), so the Forerunner is paired via a generic/dev data field.
 */
#define APP_ANT_DEVICE_NUMBER         0x3031U  /* arbitrary PoC serial */
#define APP_ANT_DEVICE_TYPE           0x78U    /* custom device type    */
#define APP_ANT_TRANSMISSION_TYPE     0x05U    /* incl. device-num MSN  */

/*
 * RF frequency offset from 2400 MHz. 57 -> 2457 MHz is the ANT+ network
 * frequency; use it so off-the-shelf ANT+ receivers can hear the strap.
 */
#define APP_ANT_RF_FREQ               57U

/*
 * Channel period in 32768 Hz counts. 8192 -> 4 messages/second, matching the
 * sensor loop so each broadcast carries a fresh frame.
 */
#define APP_ANT_CHANNEL_PERIOD        8192U

/* ANT data page number stamped in byte 0 of every broadcast frame. */
#define APP_ANT_DATA_PAGE             0x10U

#endif /* APP_CONFIG_H_ */

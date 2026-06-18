/**
 * ============================================================================
 *  File:    main.c
 *  Purpose: Entry point — initialise subsystems, start the sensor thread.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    The project's table of contents. main() brings the hardware up in a
 *    deliberate order, spawns the periodic sensor-sampling thread, and then
 *    drops out — Zephyr idles the CPU between thread wakeups, so there is no
 *    busy-wait here. All business logic lives in the modules; main() only
 *    wires them together and owns the high-level status policy (LEDs).
 *
 *    Init order rationale (each step depends on the previous):
 *      1. GPIO LEDs/buttons/EDA-gate  - cheap, gives us a visible heartbeat.
 *      2. WS2812 status pixel         - so later failures can be shown in red.
 *      3. I2C + TMP117 sensors        - the core measurement chain.
 *      4. SAADC (EDA/GSR)             - the second measurement chain.
 *      5. BLE stack + service         - radios come AFTER sensors so the very
 *      6. ANT+ broadcast                first transmitted frame carries real
 *                                       data, not zeros.
 *      7. Sensor thread               - starts sampling once everything is up.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "app/app_config.h"
#include "app/app_data.h"
#include "app/app_state.h"

#include "sensors/temp_tmp117.h"
#include "sensors/eda_gsr.h"

#include "radio/ble_service.h"
#include "radio/ant_profile.h"

#include "hmi/buttons.h"
#include "hmi/leds.h"
#include "hmi/status_led.h"

#include "util/battery.h"
#include "util/log_cfg.h"

#include <zephyr/kernel.h>

LOG_MODULE_REGISTER(main, APP_LOG_LEVEL);

/* ============================================================
 *  DEFINES
 * ============================================================ */
#define SENSOR_THREAD_STACK_SIZE  2048
#define SENSOR_THREAD_PRIO        5

/* ============================================================
 *  STATIC GLOBALS
 * ============================================================ */
static K_THREAD_STACK_DEFINE(m_sensor_stack, SENSOR_THREAD_STACK_SIZE);
static struct k_thread m_sensor_thread;

/* Latches once any sensor faults so the status LED stays red until reboot. */
static bool m_sensor_fault_latched;

/* ============================================================
 *  PRIVATE FUNCTION PROTOTYPES
 * ============================================================ */
static void sensor_thread_fn(void *p1, void *p2, void *p3);
static void on_button_event(uint8_t index, button_event_t evt);
static void on_ble_conn(bool connected);
static void refresh_status_led(uint8_t frame_flags);

/* ============================================================
 *  PUBLIC FUNCTION (entry point)
 * ============================================================ */

/**
 * @brief  Firmware entry point: init subsystems then start sampling.
 * @return 0 (never reached in practice; Zephyr keeps the kernel running).
 */
int main(void)
{
	int rc;

	LOG_INF("Biometric chest-strap PoC starting (nRF54L15)");

	/* Shared-state mutex first — every later module may cache into it. */
	(void)app_state_init();

	/* 1. Discrete GPIO: LEDs, buttons, and the EDA excitation gate (in eda). */
	rc = leds_init();
	if (rc) {
		LOG_WRN("leds_init rc=%d", rc);
	}
	leds_set(LED_ROLE_POWER, true); /* visible heartbeat: we are alive */

	rc = buttons_init(on_button_event);
	if (rc) {
		LOG_WRN("buttons_init rc=%d", rc);
	}

	/* 2. Status pixel up early so any later fault can be shown in red. */
	rc = status_led_init();
	if (rc) {
		LOG_WRN("status_led_init rc=%d", rc);
	}

	/* 3. I2C + TMP117 heat-flux sensors. */
	rc = temp_tmp117_init();
	if (rc) {
		LOG_ERR("temp_tmp117_init rc=%d", rc);
		m_sensor_fault_latched = true;
	}

	/* 4. SAADC + excitation gate for the EDA/GSR channel. */
	rc = eda_gsr_init();
	if (rc) {
		LOG_ERR("eda_gsr_init rc=%d", rc);
		m_sensor_fault_latched = true;
	}

	/* Optional charger status inputs. */
	(void)battery_init();

	/* 5. BLE (secondary): enable stack, register service, advertise. */
	ble_service_set_conn_cb(on_ble_conn);
	rc = ble_service_init();
	if (rc) {
		LOG_ERR("ble_service_init rc=%d", rc);
	}

	/* 6. ANT+ (primary): open the broadcast channel. */
	rc = ant_profile_init();
	if (rc) {
		LOG_WRN("ant_profile_init rc=%d", rc);
	}

	/* Show advertising/transmitting unless a sensor already faulted. */
	refresh_status_led(m_sensor_fault_latched ? APP_FLAG_STACK0_FAULT : 0);

	/* 7. Start the periodic sampling thread now that the chain is up. */
	k_thread_create(&m_sensor_thread, m_sensor_stack,
			K_THREAD_STACK_SIZEOF(m_sensor_stack),
			sensor_thread_fn, NULL, NULL, NULL,
			SENSOR_THREAD_PRIO, 0, K_NO_WAIT);
	k_thread_name_set(&m_sensor_thread, "sensors");

	/*
	 * main() returns to the idle thread. Do NOT busy-wait here: the kernel
	 * idles the CPU (and the nRF54L enters low-power) between thread wakeups.
	 */
	return 0;
}

/* ============================================================
 *  PRIVATE FUNCTIONS
 * ============================================================ */

/**
 * @brief  Periodic sensor loop: collect a frame and hand it to both radios.
 * @param  p1  Unused thread arg.
 * @param  p2  Unused thread arg.
 * @param  p3  Unused thread arg.
 *
 * Runs forever at APP_SENSOR_SAMPLE_PERIOD_MS. Each tick builds one frame
 * (TMP117 -> heat flux -> core temp, plus EDA), pushes it to ANT+ (primary)
 * and BLE (secondary), and updates the status LED from the frame's fault bits.
 */
static void sensor_thread_fn(void *p1, void *p2, void *p3)
{
	ARG_UNUSED(p1);
	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	while (1) {
		biometric_frame_t frame;
		(void)app_state_collect(&frame);

		/* Primary protocol first, then the secondary link. */
		ant_profile_update(&frame);
		ble_service_update(&frame);

		refresh_status_led(frame.flags);

		k_sleep(K_MSEC(APP_SENSOR_SAMPLE_PERIOD_MS));
	}
}

/**
 * @brief  Handle a debounced button event.
 * @param  index  Button index (devicetree order).
 * @param  evt    Short or long press.
 *
 * PoC behaviour: a short press toggles the power LED as a liveness check; a
 * long press is logged for future use (e.g. start/stop a logging session).
 */
static void on_button_event(uint8_t index, button_event_t evt)
{
	static bool toggle;

	if (evt == BUTTON_EVT_SHORT_PRESS) {
		toggle = !toggle;
		leds_set(LED_ROLE_POWER, toggle);
		LOG_INF("Button %u short press", index);
	} else {
		/* TODO(PoC): map long-press to a session start/stop action. */
		LOG_INF("Button %u long press", index);
	}
}

/**
 * @brief  BLE connection-state hook from the service layer.
 * @param  connected  true on connect, false on disconnect.
 *
 * Keeps LED policy in main() (the HMI owner) rather than in the radio module.
 */
static void on_ble_conn(bool connected)
{
	/* A live fault always wins over link colour. */
	if (m_sensor_fault_latched) {
		return;
	}
	status_led_set(connected ? STATUS_CONNECTED : STATUS_ADVERTISING);
}

/**
 * @brief  Map frame fault flags onto the status LED and the fault LED.
 * @param  frame_flags  APP_FLAG_* bitmask from the latest frame.
 *
 * Any sensor fault latches red until reboot — for a PoC a sticky fault is more
 * useful than a flickering indicator. Otherwise the colour reflects link
 * state (green connected, blue advertising).
 */
static void refresh_status_led(uint8_t frame_flags)
{
	const uint8_t sensor_faults =
		APP_FLAG_STACK0_FAULT | APP_FLAG_STACK1_FAULT | APP_FLAG_EDA_FAULT;

	if (frame_flags & sensor_faults) {
		m_sensor_fault_latched = true;
	}

	leds_set(LED_ROLE_CHARGE, (frame_flags & APP_FLAG_BATT_CHARGING) != 0);

	if (m_sensor_fault_latched) {
		leds_set(LED_ROLE_FAULT, true);
		status_led_set(STATUS_SENSOR_FAULT);
		return;
	}

	leds_set(LED_ROLE_FAULT, false);
	status_led_set(ble_service_is_connected() ? STATUS_CONNECTED
						  : STATUS_ADVERTISING);
}

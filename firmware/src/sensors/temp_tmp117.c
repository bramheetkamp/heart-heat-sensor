/**
 * ============================================================================
 *  File:    temp_tmp117.c
 *  Purpose: TMP117 driver wrapper for the two heat-flux stacks.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Maps four physical TMP117 sensors (two per heat-flux stack) onto a small
 *    stack-oriented API. Devices are resolved from devicetree node labels so
 *    nothing here hardcodes a bus or an I2C address — re-strapping the ADD0
 *    pin or moving a sensor to a second I2C controller is purely a devicetree
 *    edit. The Zephyr in-tree "ti,tmp116" driver (which supports the TMP117)
 *    does the register-level work; this layer adds stack grouping, averaging
 *    config, single-retry error handling, and fault marking.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "temp_tmp117.h"
#include "app_config.h"
#include "util/log_cfg.h"

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/sensor.h>

LOG_MODULE_REGISTER(temp_tmp117, APP_LOG_LEVEL);

/* ============================================================
 *  PRIVATE TYPES
 * ============================================================ */

/*
 * One physical TMP117. We keep the resolved device pointer plus a sticky
 * "faulted" flag so a dead sensor is skipped quickly instead of re-probed on
 * every sample (it is cleared again as soon as a read succeeds).
 */
struct tmp117_dev {
	const struct device *dev;
	bool faulted;
};

/* A heat-flux stack is just the skin-side and ambient-side sensor. */
struct tmp117_stack {
	struct tmp117_dev skin;
	struct tmp117_dev ambient;
};

/* ============================================================
 *  DEVICETREE BINDING
 * ============================================================ */

/*
 * Resolve the four sensors from fixed node labels declared in the board
 * overlay/DTS. The labels carry the bus+address; this file only knows the
 * labels. A node that exists but is disabled resolves to NULL and is reported
 * as faulted at runtime, which keeps the DK and the custom board
 * interchangeable. (All four labels must exist in devicetree to compile.)
 */
#define TMP_DEV(label) \
	{ .dev = DEVICE_DT_GET_OR_NULL(DT_NODELABEL(label)), .faulted = false }

static struct tmp117_stack m_stacks[APP_NUM_HEATFLUX_STACKS] = {
	[0] = { .skin = TMP_DEV(tmp117_s0_skin), .ambient = TMP_DEV(tmp117_s0_amb) },
	[1] = { .skin = TMP_DEV(tmp117_s1_skin), .ambient = TMP_DEV(tmp117_s1_amb) },
};

/* ============================================================
 *  PRIVATE FUNCTION PROTOTYPES
 * ============================================================ */
static int  configure_sensor(const struct device *dev);
static int  read_one(struct tmp117_dev *s, float *temp_c);

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Initialise every TMP117 referenced by devicetree.
 * @return 0 if at least one sensor is ready, negative errno if none are.
 */
int temp_tmp117_init(void)
{
	unsigned int ready = 0U;

	for (uint8_t i = 0; i < APP_NUM_HEATFLUX_STACKS; i++) {
		struct tmp117_dev *pair[APP_SENSORS_PER_STACK] = {
			&m_stacks[i].skin, &m_stacks[i].ambient,
		};

		for (uint8_t j = 0; j < APP_SENSORS_PER_STACK; j++) {
			struct tmp117_dev *s = pair[j];

			if (s->dev == NULL || !device_is_ready(s->dev)) {
				/* Missing or not ready: fault it but keep going. */
				LOG_WRN("Stack %u sensor %u not ready", i, j);
				s->faulted = true;
				continue;
			}

			if (configure_sensor(s->dev) != 0) {
				LOG_WRN("Stack %u sensor %u config failed", i, j);
				s->faulted = true;
				continue;
			}

			s->faulted = false;
			ready++;
		}
	}

	if (ready == 0U) {
		LOG_ERR("No TMP117 sensors ready");
		return -ENODEV;
	}

	LOG_INF("TMP117 init: %u/%u sensors ready", ready,
		APP_NUM_HEATFLUX_STACKS * APP_SENSORS_PER_STACK);
	return 0;
}

/**
 * @brief  Read both temperatures of one heat-flux stack.
 * @param  stack_id  Stack index [0 .. APP_NUM_HEATFLUX_STACKS-1].
 * @param  out       Filled with skin/ambient temps; .valid reflects success.
 * @return 0 on success, negative errno on bad arg or full I2C failure.
 */
int temp_tmp117_read_stack(uint8_t stack_id, tmp_pair_t *out)
{
	if (stack_id >= APP_NUM_HEATFLUX_STACKS || out == NULL) {
		return -EINVAL;
	}

	struct tmp117_stack *st = &m_stacks[stack_id];
	int err_skin = read_one(&st->skin, &out->skin_temp_c);
	int err_amb  = read_one(&st->ambient, &out->ambient_temp_c);

	/* The stack is only usable if BOTH sides read — heat flux needs a pair. */
	out->valid = (err_skin == 0 && err_amb == 0);
	if (!out->valid) {
		return (err_skin != 0) ? err_skin : err_amb;
	}
	return 0;
}

/* ============================================================
 *  PRIVATE FUNCTIONS
 * ============================================================ */

/**
 * @brief  Configure a TMP117 for low-noise continuous conversion.
 * @param  dev  Ready Zephyr sensor device for the TMP117.
 * @return 0 on success, negative errno otherwise.
 *
 * We request oversampling for noise averaging. Not every driver revision
 * exposes the attribute, so an -ENOTSUP is treated as "use the driver default"
 * rather than a hard failure — the sensor still reads, just with less
 * averaging.
 */
static int configure_sensor(const struct device *dev)
{
	struct sensor_value os = { .val1 = 8, .val2 = 0 }; /* ~8x averaging */
	int rc = sensor_attr_set(dev, SENSOR_CHAN_AMBIENT_TEMP,
				 SENSOR_ATTR_OVERSAMPLING, &os);
	if (rc == -ENOTSUP || rc == -ENOSYS) {
		LOG_DBG("Oversampling attr unsupported; using driver default");
		return 0;
	}
	return rc;
}

/**
 * @brief  Fetch one temperature, retrying a single transient I2C error.
 * @param  s       Sensor descriptor (carries the sticky fault flag).
 * @param  temp_c  Output temperature in degrees Celsius.
 * @return 0 on success, negative errno after the retry also fails.
 *
 * Why a single retry: the I2C bus on a moving chest strap occasionally NAKs;
 * one immediate retry clears almost all of those without adding latency to the
 * common path. A second failure marks the sensor faulted so the rest of the
 * pipeline (and the WS2812 status colour) can react instead of stalling.
 */
static int read_one(struct tmp117_dev *s, float *temp_c)
{
	if (s->dev == NULL) {
		return -ENODEV;
	}

	for (int attempt = 0; attempt < 2; attempt++) {
		struct sensor_value val;
		int rc = sensor_sample_fetch(s->dev);

		if (rc == 0) {
			rc = sensor_channel_get(s->dev, SENSOR_CHAN_AMBIENT_TEMP, &val);
		}

		if (rc == 0) {
			*temp_c = (float)sensor_value_to_double(&val);
			s->faulted = false; /* recovered */
			return 0;
		}

		LOG_DBG("TMP117 read err %d (attempt %d)", rc, attempt);
	}

	if (!s->faulted) {
		LOG_WRN("TMP117 marked faulted");
		s->faulted = true;
	}
	return -EIO;
}

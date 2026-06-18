/**
 * ============================================================================
 *  File:    buttons.c
 *  Purpose: Debounced gpio-keys button handling with long-press detection.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Generic handler over a devicetree `gpio-keys` node. Every child of that
 *    node becomes a button; the array is built at compile time with
 *    DT_FOREACH_CHILD so the count is whatever the board overlay declares.
 *    Each edge schedules a short debounce; on a confirmed press we start a
 *    timer, and whether the button is still held when it expires decides
 *    short vs long press.
 *
 *  TODO(PoC): The PCB populates a single tactile switch (ACT1). The spec
 *  mentions two buttons; add a second child to the `buttons` gpio-keys node in
 *  the board files to enable it — no change needed here.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "buttons.h"
#include "app_config.h"
#include "util/log_cfg.h"

#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>

LOG_MODULE_REGISTER(buttons, APP_LOG_LEVEL);

/* ============================================================
 *  DEFINES
 * ============================================================ */
#define BUTTONS_NODE        DT_NODELABEL(buttons)
#define DEBOUNCE_MS         30U   /* mechanical bounce settle window      */
#define LONG_PRESS_MS       800U  /* hold beyond this -> long press       */

/* Build a gpio_dt_spec for each child of the gpio-keys node. */
#define BUTTON_SPEC(node_id) GPIO_DT_SPEC_GET(node_id, gpios),

/* ============================================================
 *  PRIVATE TYPES
 * ============================================================ */

/* Per-button runtime state: debounce + long-press bookkeeping. */
struct button_ctx {
	struct gpio_callback   cb_data;
	struct k_work_delayable debounce_work;
	struct k_timer          long_timer;
	uint8_t                 index;
	bool                    long_fired; /* long press already emitted     */
};

/* ============================================================
 *  STATIC GLOBALS
 * ============================================================ */
/* STATUS_OKAY skips children marked status="disabled" (e.g. the stubbed 2nd
 * button), so a disabled child never becomes a phantom input at runtime. */
static const struct gpio_dt_spec m_btn_gpio[] = {
	DT_FOREACH_CHILD_STATUS_OKAY(BUTTONS_NODE, BUTTON_SPEC)
};

#define NUM_BUTTONS ARRAY_SIZE(m_btn_gpio)

static struct button_ctx m_ctx[NUM_BUTTONS];
static button_cb_t        m_user_cb;

/* ============================================================
 *  PRIVATE FUNCTION PROTOTYPES
 * ============================================================ */
static void gpio_isr(const struct device *port, struct gpio_callback *cb,
		     uint32_t pins);
static void debounce_handler(struct k_work *work);
static void long_press_handler(struct k_timer *timer);

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Initialise all devicetree buttons and register the event callback.
 * @param  cb  Callback invoked from a workqueue context on each event.
 * @return 0 on success, negative errno if no button is usable.
 */
int buttons_init(button_cb_t cb)
{
	unsigned int ok = 0U;

	m_user_cb = cb;

	for (uint8_t i = 0; i < NUM_BUTTONS; i++) {
		const struct gpio_dt_spec *g = &m_btn_gpio[i];
		struct button_ctx *c = &m_ctx[i];

		c->index = i;
		c->long_fired = false;

		if (!gpio_is_ready_dt(g)) {
			LOG_WRN("Button %u GPIO not ready", i);
			continue;
		}

		/* Active level + pulls come from the devicetree flags. */
		if (gpio_pin_configure_dt(g, GPIO_INPUT) != 0) {
			LOG_WRN("Button %u config failed", i);
			continue;
		}

		/* Interrupt on both edges so we see press AND release. */
		if (gpio_pin_interrupt_configure_dt(g, GPIO_INT_EDGE_BOTH) != 0) {
			LOG_WRN("Button %u IRQ config failed", i);
			continue;
		}

		k_work_init_delayable(&c->debounce_work, debounce_handler);
		k_timer_init(&c->long_timer, long_press_handler, NULL);
		k_timer_user_data_set(&c->long_timer, c);

		gpio_init_callback(&c->cb_data, gpio_isr, BIT(g->pin));
		gpio_add_callback(g->port, &c->cb_data);
		ok++;
	}

	if (ok == 0U) {
		LOG_ERR("No usable buttons");
		return -ENODEV;
	}

	LOG_INF("Buttons init: %u button(s)", ok);
	return 0;
}

/* ============================================================
 *  PRIVATE FUNCTIONS
 * ============================================================ */

/**
 * @brief  Map a triggering GPIO callback back to its button index.
 * @param  cb  The gpio_callback that fired.
 * @return Pointer to the owning button_ctx, or NULL if not found.
 *
 * gpio_init_callback() embeds cb_data inside button_ctx, so CONTAINER_OF
 * recovers the context without a separate lookup table.
 */
static struct button_ctx *ctx_from_cb(struct gpio_callback *cb)
{
	return CONTAINER_OF(cb, struct button_ctx, cb_data);
}

/**
 * @brief  GPIO edge ISR: defer all work to the debounce handler.
 * @param  port  GPIO port device (unused; spec known from context).
 * @param  cb    The callback structure that fired.
 * @param  pins  Bitmask of pins that triggered (unused; one pin per cb).
 *
 * ISRs must stay short and must not call back into the user; we only schedule
 * the debounce work item after the bounce window.
 */
static void gpio_isr(const struct device *port, struct gpio_callback *cb,
		     uint32_t pins)
{
	ARG_UNUSED(port);
	ARG_UNUSED(pins);

	struct button_ctx *c = ctx_from_cb(cb);
	k_work_reschedule(&c->debounce_work, K_MSEC(DEBOUNCE_MS));
}

/**
 * @brief  Debounced edge handler: decide press vs release and arm timers.
 * @param  work  The delayable work item embedded in button_ctx.
 *
 * Runs on the system workqueue after the bounce window, so the level read here
 * is stable. On a press we arm the long-press timer; on a release we either
 * cancel it (and emit a short press) or do nothing if the long press already
 * fired.
 */
static void debounce_handler(struct k_work *work)
{
	struct k_work_delayable *dwork = k_work_delayable_from_work(work);
	struct button_ctx *c =
		CONTAINER_OF(dwork, struct button_ctx, debounce_work);
	const struct gpio_dt_spec *g = &m_btn_gpio[c->index];

	bool pressed = gpio_pin_get_dt(g) > 0; /* logical level, DT-aware */

	if (pressed) {
		c->long_fired = false;
		k_timer_start(&c->long_timer, K_MSEC(LONG_PRESS_MS), K_NO_WAIT);
	} else {
		k_timer_stop(&c->long_timer);
		if (!c->long_fired && m_user_cb) {
			m_user_cb(c->index, BUTTON_EVT_SHORT_PRESS);
		}
	}
}

/**
 * @brief  Long-press timer expiry: button held past LONG_PRESS_MS.
 * @param  timer  The per-button timer.
 *
 * Emitting here (rather than on release) gives the user immediate feedback at
 * the moment the long press is recognised. The flag suppresses the short-press
 * event that would otherwise follow on release.
 */
static void long_press_handler(struct k_timer *timer)
{
	struct button_ctx *c = k_timer_user_data_get(timer);

	c->long_fired = true;
	if (m_user_cb) {
		m_user_cb(c->index, BUTTON_EVT_LONG_PRESS);
	}
}

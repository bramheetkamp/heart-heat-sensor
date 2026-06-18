/**
 * ============================================================================
 *  File:    buttons.h
 *  Purpose: Debounced, devicetree-driven button events (short / long press).
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Reads N buttons described by a `gpio-keys` node in devicetree and emits
 *    short-press and long-press events through a single callback. The PCB
 *    currently populates one tactile switch (ACT1) but the BOM/spec mentions
 *    two; because the button list comes from devicetree, adding the second is
 *    a devicetree edit, not a code change.
 * ============================================================================
 */

#ifndef BUTTONS_H_
#define BUTTONS_H_

#include <stdint.h>

/** @brief Kinds of button event delivered to the callback. */
typedef enum {
	BUTTON_EVT_SHORT_PRESS = 0,
	BUTTON_EVT_LONG_PRESS,
} button_event_t;

/**
 * @brief  Button event callback type.
 * @param  index  Zero-based button index (order matches devicetree children).
 * @param  evt    Short or long press.
 */
typedef void (*button_cb_t)(uint8_t index, button_event_t evt);

/**
 * @brief  Initialise all devicetree buttons and register the event callback.
 * @param  cb  Callback invoked from a workqueue context on each event.
 * @return 0 on success, negative errno if no button is usable.
 */
int buttons_init(button_cb_t cb);

#endif /* BUTTONS_H_ */

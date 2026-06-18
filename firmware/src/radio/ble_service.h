/**
 * ============================================================================
 *  File:    ble_service.h
 *  Purpose: Custom BLE GATT service exposing the biometric frame (secondary).
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    BLE is the secondary link (ANT+ is primary). This module brings up the
 *    Bluetooth stack, advertises connectably, and serves a custom 128-bit-UUID
 *    service with characteristics for skin temperature, estimated core
 *    temperature, EDA, and a combined notification of the whole frame.
 *    Based on the structure of the NCS peripheral_hr sample.
 * ============================================================================
 */

#ifndef BLE_SERVICE_H_
#define BLE_SERVICE_H_

#include <stdbool.h>
#include "app_data.h"

/**
 * @brief  Connection-state change callback type.
 * @param  connected  true on connect, false on disconnect.
 */
typedef void (*ble_conn_cb_t)(bool connected);

/**
 * @brief  Enable Bluetooth, register the service, and start advertising.
 * @return 0 on success, negative errno on stack or advertising failure.
 */
int ble_service_init(void);

/**
 * @brief  Register a callback for connect/disconnect transitions.
 * @param  cb  Callback (e.g. to drive the status LED). May be NULL.
 *
 * Kept separate from init so the HMI layer owns the LED policy, not the radio.
 */
void ble_service_set_conn_cb(ble_conn_cb_t cb);

/**
 * @brief  Update characteristic values and notify subscribers.
 * @param  frame  Latest biometric frame to publish.
 *
 * No-op (other than caching) if no central is connected/subscribed.
 */
void ble_service_update(const biometric_frame_t *frame);

/**
 * @brief  Query the current link state.
 * @return true if a central is connected.
 */
bool ble_service_is_connected(void);

#endif /* BLE_SERVICE_H_ */

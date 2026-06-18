/**
 * ============================================================================
 *  File:    ble_service.c
 *  Purpose: Custom GATT biometric service + connectable advertising.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Implements the secondary BLE link. One primary service with four
 *    characteristics:
 *        - Skin temperature      (float32, deg C, stack 0)   read + notify
 *        - Core temperature      (float32, deg C, stack 0)   read + notify
 *        - EDA conductance       (float32, microsiemens)     read + notify
 *        - Combined frame        (raw biometric_frame_t)     read + notify
 *
 *    The combined characteristic is the whole biometric_frame_t copied byte
 *    for byte (little-endian, packed by the compiler for this MCU). For a PoC
 *    a host script unpacks it directly; a production build would version and
 *    explicitly serialise it. UUIDs are a custom 128-bit base; see the table
 *    in README.md. The flow mirrors the NCS peripheral_hr sample.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "ble_service.h"
#include "app_config.h"
#include "util/log_cfg.h"

#include <zephyr/kernel.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/uuid.h>
#include <string.h>

LOG_MODULE_REGISTER(ble_service, APP_LOG_LEVEL);

/* ============================================================
 *  UUID DEFINITIONS  (custom 128-bit base a0b4xxxx-...)
 * ============================================================ */

/* Service and characteristic UUIDs share a base; only the 3rd group varies. */
#define BIO_UUID_SVC \
	BT_UUID_128_ENCODE(0xa0b40000, 0x7e9c, 0x4f1a, 0x9a1e, 0x7c0ffeed0001)
#define BIO_UUID_SKIN \
	BT_UUID_128_ENCODE(0xa0b40001, 0x7e9c, 0x4f1a, 0x9a1e, 0x7c0ffeed0001)
#define BIO_UUID_CORE \
	BT_UUID_128_ENCODE(0xa0b40002, 0x7e9c, 0x4f1a, 0x9a1e, 0x7c0ffeed0001)
#define BIO_UUID_EDA \
	BT_UUID_128_ENCODE(0xa0b40003, 0x7e9c, 0x4f1a, 0x9a1e, 0x7c0ffeed0001)
#define BIO_UUID_FRAME \
	BT_UUID_128_ENCODE(0xa0b40004, 0x7e9c, 0x4f1a, 0x9a1e, 0x7c0ffeed0001)

static const struct bt_uuid_128 uuid_svc   = BT_UUID_INIT_128(BIO_UUID_SVC);
static const struct bt_uuid_128 uuid_skin  = BT_UUID_INIT_128(BIO_UUID_SKIN);
static const struct bt_uuid_128 uuid_core  = BT_UUID_INIT_128(BIO_UUID_CORE);
static const struct bt_uuid_128 uuid_eda   = BT_UUID_INIT_128(BIO_UUID_EDA);
static const struct bt_uuid_128 uuid_frame = BT_UUID_INIT_128(BIO_UUID_FRAME);

/* ============================================================
 *  STATIC GLOBALS  (characteristic value backing store)
 * ============================================================ */
static float             m_skin_c;   /* stack 0 skin temp        */
static float             m_core_c;   /* stack 0 core estimate    */
static float             m_eda_us;   /* skin conductance         */
static biometric_frame_t m_frame;    /* combined snapshot        */

static struct bt_conn *m_conn;       /* single active central    */
static ble_conn_cb_t   m_conn_cb;    /* HMI hook                 */

/* Per-characteristic notify-enabled flags, toggled by the CCC callbacks. */
static bool m_ntf_skin, m_ntf_core, m_ntf_eda, m_ntf_frame;

/* ============================================================
 *  PRIVATE FUNCTION PROTOTYPES
 * ============================================================ */
static ssize_t read_skin(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			 void *buf, uint16_t len, uint16_t offset);
static ssize_t read_core(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			 void *buf, uint16_t len, uint16_t offset);
static ssize_t read_eda(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			void *buf, uint16_t len, uint16_t offset);
static ssize_t read_frame(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			  void *buf, uint16_t len, uint16_t offset);
static void skin_ccc(const struct bt_gatt_attr *attr, uint16_t value);
static void core_ccc(const struct bt_gatt_attr *attr, uint16_t value);
static void eda_ccc(const struct bt_gatt_attr *attr, uint16_t value);
static void frame_ccc(const struct bt_gatt_attr *attr, uint16_t value);

/* ============================================================
 *  GATT SERVICE TABLE
 * ============================================================ */

/*
 * Attribute indices used for notifications (value attribute == decl + 1):
 *   [0] primary service
 *   [1] skin decl   [2] skin value   [3] skin CCC
 *   [4] core decl   [5] core value   [6] core CCC
 *   [7] eda decl    [8] eda value    [9] eda CCC
 *   [10] frame decl [11] frame value [12] frame CCC
 */
BT_GATT_SERVICE_DEFINE(bio_svc,
	BT_GATT_PRIMARY_SERVICE(&uuid_svc),

	BT_GATT_CHARACTERISTIC(&uuid_skin.uuid,
			       BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ, read_skin, NULL, &m_skin_c),
	BT_GATT_CCC(skin_ccc, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),

	BT_GATT_CHARACTERISTIC(&uuid_core.uuid,
			       BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ, read_core, NULL, &m_core_c),
	BT_GATT_CCC(core_ccc, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),

	BT_GATT_CHARACTERISTIC(&uuid_eda.uuid,
			       BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ, read_eda, NULL, &m_eda_us),
	BT_GATT_CCC(eda_ccc, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),

	BT_GATT_CHARACTERISTIC(&uuid_frame.uuid,
			       BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ, read_frame, NULL, &m_frame),
	BT_GATT_CCC(frame_ccc, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
);

/* ============================================================
 *  ADVERTISING DATA
 * ============================================================ */
static const struct bt_data ad[] = {
	BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
	BT_DATA(BT_DATA_NAME_COMPLETE, APP_BLE_DEVICE_NAME,
		sizeof(APP_BLE_DEVICE_NAME) - 1),
};

/* ============================================================
 *  CONNECTION CALLBACKS
 * ============================================================ */

/**
 * @brief  Bluetooth "connected" event handler.
 * @param  conn  The new connection.
 * @param  err   0 on success, HCI error code otherwise.
 *
 * Caches the connection so update() knows whom to notify, and forwards the
 * transition to the HMI hook so the status LED can go green.
 */
static void on_connected(struct bt_conn *conn, uint8_t err)
{
	if (err) {
		LOG_WRN("BLE connect failed (0x%02x)", err);
		return;
	}
	m_conn = bt_conn_ref(conn);
	LOG_INF("BLE connected");
	if (m_conn_cb) {
		m_conn_cb(true);
	}
}

/**
 * @brief  Bluetooth "disconnected" event handler.
 * @param  conn    The dropped connection.
 * @param  reason  HCI disconnect reason.
 *
 * Releases the cached connection, clears notify flags, and restarts
 * advertising so the strap is immediately re-discoverable.
 */
static void on_disconnected(struct bt_conn *conn, uint8_t reason)
{
	ARG_UNUSED(conn);
	LOG_INF("BLE disconnected (0x%02x)", reason);

	if (m_conn) {
		bt_conn_unref(m_conn);
		m_conn = NULL;
	}
	m_ntf_skin = m_ntf_core = m_ntf_eda = m_ntf_frame = false;

	if (m_conn_cb) {
		m_conn_cb(false);
	}

	int rc = bt_le_adv_start(BT_LE_ADV_CONN, ad, ARRAY_SIZE(ad), NULL, 0);
	if (rc) {
		LOG_WRN("Advertising restart failed (%d)", rc);
	}
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
	.connected = on_connected,
	.disconnected = on_disconnected,
};

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Enable Bluetooth, register the service, and start advertising.
 * @return 0 on success, negative errno on stack or advertising failure.
 */
int ble_service_init(void)
{
	int rc = bt_enable(NULL);
	if (rc) {
		LOG_ERR("bt_enable failed (%d)", rc);
		return rc;
	}

	/* Service is registered automatically via BT_GATT_SERVICE_DEFINE. */
	rc = bt_le_adv_start(BT_LE_ADV_CONN, ad, ARRAY_SIZE(ad), NULL, 0);
	if (rc) {
		LOG_ERR("Advertising start failed (%d)", rc);
		return rc;
	}

	LOG_INF("BLE service up, advertising as \"%s\"", APP_BLE_DEVICE_NAME);
	return 0;
}

/**
 * @brief  Register a callback for connect/disconnect transitions.
 * @param  cb  Callback (may be NULL).
 */
void ble_service_set_conn_cb(ble_conn_cb_t cb)
{
	m_conn_cb = cb;
}

/**
 * @brief  Update characteristic values and notify subscribers.
 * @param  frame  Latest biometric frame to publish.
 */
void ble_service_update(const biometric_frame_t *frame)
{
	if (frame == NULL) {
		return;
	}

	/* Singletons mirror stack 0; the combined char carries everything. */
	m_skin_c = frame->stack[0].skin_temp_c;
	m_core_c = frame->core[0].core_temp_c;
	m_eda_us = frame->eda.conductance_us;
	memcpy(&m_frame, frame, sizeof(m_frame));

	if (m_conn == NULL) {
		return; /* nobody to notify */
	}

	/* Notify only the characteristics a central actually subscribed to. */
	if (m_ntf_skin) {
		bt_gatt_notify(m_conn, &bio_svc.attrs[2], &m_skin_c,
			       sizeof(m_skin_c));
	}
	if (m_ntf_core) {
		bt_gatt_notify(m_conn, &bio_svc.attrs[5], &m_core_c,
			       sizeof(m_core_c));
	}
	if (m_ntf_eda) {
		bt_gatt_notify(m_conn, &bio_svc.attrs[8], &m_eda_us,
			       sizeof(m_eda_us));
	}
	if (m_ntf_frame) {
		bt_gatt_notify(m_conn, &bio_svc.attrs[11], &m_frame,
			       sizeof(m_frame));
	}
}

/**
 * @brief  Query the current link state.
 * @return true if a central is connected.
 */
bool ble_service_is_connected(void)
{
	return m_conn != NULL;
}

/* ============================================================
 *  PRIVATE FUNCTIONS  (GATT read + CCC handlers)
 * ============================================================ */

/**
 * @brief  Generic attribute read helper.
 * @param  conn    The reading connection (unused).
 * @param  attr    Attribute being read; attr->user_data points to the value.
 * @param  buf     Output buffer supplied by the stack.
 * @param  len     Maximum bytes to copy.
 * @param  offset  Read offset for long reads.
 * @param  size    Size of the backing value.
 * @return Number of bytes placed in buf, or a negative GATT error.
 */
static ssize_t read_value(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			  void *buf, uint16_t len, uint16_t offset, size_t size)
{
	return bt_gatt_attr_read(conn, attr, buf, len, offset,
				 attr->user_data, size);
}

/** @brief Read skin temperature (float32). See read_value(). */
static ssize_t read_skin(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			 void *buf, uint16_t len, uint16_t offset)
{
	return read_value(conn, attr, buf, len, offset, sizeof(m_skin_c));
}

/** @brief Read core temperature estimate (float32). See read_value(). */
static ssize_t read_core(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			 void *buf, uint16_t len, uint16_t offset)
{
	return read_value(conn, attr, buf, len, offset, sizeof(m_core_c));
}

/** @brief Read EDA conductance (float32, microsiemens). See read_value(). */
static ssize_t read_eda(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			void *buf, uint16_t len, uint16_t offset)
{
	return read_value(conn, attr, buf, len, offset, sizeof(m_eda_us));
}

/** @brief Read the combined biometric frame (raw struct). See read_value(). */
static ssize_t read_frame(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			  void *buf, uint16_t len, uint16_t offset)
{
	return read_value(conn, attr, buf, len, offset, sizeof(m_frame));
}

/**
 * @brief  CCC change handler for the skin characteristic.
 * @param  attr   The CCC attribute (unused).
 * @param  value  New CCC value; bit set means notifications enabled.
 */
static void skin_ccc(const struct bt_gatt_attr *attr, uint16_t value)
{
	ARG_UNUSED(attr);
	m_ntf_skin = (value == BT_GATT_CCC_NOTIFY);
}

/** @brief CCC change handler for the core characteristic. See skin_ccc(). */
static void core_ccc(const struct bt_gatt_attr *attr, uint16_t value)
{
	ARG_UNUSED(attr);
	m_ntf_core = (value == BT_GATT_CCC_NOTIFY);
}

/** @brief CCC change handler for the EDA characteristic. See skin_ccc(). */
static void eda_ccc(const struct bt_gatt_attr *attr, uint16_t value)
{
	ARG_UNUSED(attr);
	m_ntf_eda = (value == BT_GATT_CCC_NOTIFY);
}

/** @brief CCC change handler for the combined-frame characteristic. */
static void frame_ccc(const struct bt_gatt_attr *attr, uint16_t value)
{
	ARG_UNUSED(attr);
	m_ntf_frame = (value == BT_GATT_CCC_NOTIFY);
}

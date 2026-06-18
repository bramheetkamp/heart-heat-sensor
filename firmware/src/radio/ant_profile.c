/**
 * ============================================================================
 *  File:    ant_profile.c
 *  Purpose: ANT+ master broadcast of the custom biometric data page.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Opens a single ANT master channel and broadcasts the 8-byte biometric
 *    page (layout documented in ant_profile.h) at APP_ANT_CHANNEL_PERIOD. The
 *    SoftDevice-style ANT API from the NCS ANT add-on does the heavy lifting
 *    (sd_ant_*); we configure the channel once, then on every EVENT_TX swap in
 *    the most recent payload so the air data tracks the sensor loop.
 *
 *    All add-on-specific code is compiled only when CONFIG_ANT is enabled.
 *    When it is not, the module degrades to logged stubs so the rest of the
 *    firmware (and a BLE-only bring-up) still builds and runs.
 *
 *  Assumptions / TODO(PoC):
 *    - Exact add-on symbol names and headers track the installed ANT add-on
 *      release; verify against its version (see README assumptions).
 *    - ANT+ uses a managed network key from thisisant.com. A placeholder key
 *      is referenced below and MUST be replaced with the real key before the
 *      Forerunner will accept the broadcast on the ANT+ network frequency.
 * ============================================================================
 */

/* ============================================================
 *  INCLUDES
 * ============================================================ */
#include "ant_profile.h"
#include "app_config.h"
#include "util/log_cfg.h"

#include <zephyr/kernel.h>
#include <string.h>

LOG_MODULE_REGISTER(ant_profile, APP_LOG_LEVEL);

#if defined(CONFIG_ANT)
/* Headers provided by the NCS ANT add-on. */
#include <ant_interface.h>
#include <ant_parameters.h>
#include <nrf_sdh_ant.h>

/* ============================================================
 *  DEFINES
 * ============================================================ */
#define ANT_CHANNEL_NUM     0       /* single master channel            */
#define ANT_PAGE_LEN        8       /* ANT payload is always 8 bytes    */

/*
 * Placeholder ANT+ network key. Replace with the managed ANT+ key issued by
 * thisisant.com. Using zeros here keeps us on the public network for bench
 * testing between two of our own nodes.
 */
static const uint8_t m_network_key[8] = {0};

/* ============================================================
 *  STATIC GLOBALS
 * ============================================================ */
static uint8_t m_tx_buf[ANT_PAGE_LEN];  /* current broadcast payload    */
static bool    m_open;                  /* channel successfully opened  */

/* ============================================================
 *  PRIVATE FUNCTION PROTOTYPES
 * ============================================================ */
static void ant_evt_handler(ant_evt_t *evt, void *context);
static void pack_page(const biometric_frame_t *frame, uint8_t *buf);

/* Register this module as an ANT event observer with the add-on dispatcher. */
NRF_SDH_ANT_OBSERVER(m_ant_obs, 1, ant_evt_handler, NULL);
#endif /* CONFIG_ANT */

/* ============================================================
 *  PUBLIC FUNCTIONS
 * ============================================================ */

/**
 * @brief  Configure and open the ANT master broadcast channel.
 * @return 0 on success, negative errno on stack/channel failure.
 */
int ant_profile_init(void)
{
#if defined(CONFIG_ANT)
	uint32_t rc;

	/* Enable the ANT stack via the add-on's SoftDevice handler glue. */
	rc = nrf_sdh_ant_enable();
	if (rc != NRF_SUCCESS) {
		LOG_ERR("nrf_sdh_ant_enable failed (0x%lx)", (unsigned long)rc);
		return -EIO;
	}

	/* Program the network key the channel will transmit on. */
	rc = sd_ant_network_address_set(0, m_network_key);
	if (rc != NRF_SUCCESS) {
		LOG_ERR("network key set failed (0x%lx)", (unsigned long)rc);
		return -EIO;
	}

	/*
	 * Assign channel 0 as a bidirectional master on network 0. Master = we
	 * transmit; the receiver is the slave. The order below follows the ANT
	 * add-on broadcast-TX sample: assign -> id -> rf freq -> period -> open.
	 */
	rc = sd_ant_channel_assign(ANT_CHANNEL_NUM, CHANNEL_TYPE_MASTER, 0, 0);
	if (rc != NRF_SUCCESS) {
		LOG_ERR("channel assign failed (0x%lx)", (unsigned long)rc);
		return -EIO;
	}

	rc = sd_ant_channel_id_set(ANT_CHANNEL_NUM, APP_ANT_DEVICE_NUMBER,
				   APP_ANT_DEVICE_TYPE, APP_ANT_TRANSMISSION_TYPE);
	if (rc != NRF_SUCCESS) {
		LOG_ERR("channel id set failed (0x%lx)", (unsigned long)rc);
		return -EIO;
	}

	rc = sd_ant_channel_radio_freq_set(ANT_CHANNEL_NUM, APP_ANT_RF_FREQ);
	if (rc != NRF_SUCCESS) {
		LOG_ERR("rf freq set failed (0x%lx)", (unsigned long)rc);
		return -EIO;
	}

	rc = sd_ant_channel_period_set(ANT_CHANNEL_NUM, APP_ANT_CHANNEL_PERIOD);
	if (rc != NRF_SUCCESS) {
		LOG_ERR("period set failed (0x%lx)", (unsigned long)rc);
		return -EIO;
	}

	/* Seed an all-zero page so the first TX is valid before any sensor data. */
	m_tx_buf[0] = APP_ANT_DATA_PAGE;
	(void)sd_ant_broadcast_message_tx(ANT_CHANNEL_NUM, ANT_PAGE_LEN, m_tx_buf);

	rc = sd_ant_channel_open(ANT_CHANNEL_NUM);
	if (rc != NRF_SUCCESS) {
		LOG_ERR("channel open failed (0x%lx)", (unsigned long)rc);
		return -EIO;
	}

	m_open = true;
	LOG_INF("ANT master open: dev=%u type=%u freq=2%uMHz period=%u",
		APP_ANT_DEVICE_NUMBER, APP_ANT_DEVICE_TYPE,
		400U + APP_ANT_RF_FREQ, APP_ANT_CHANNEL_PERIOD);
	return 0;
#else
	LOG_WRN("CONFIG_ANT disabled; ANT broadcast not started");
	return -ENOTSUP;
#endif
}

/**
 * @brief  Refresh the broadcast payload with the latest frame.
 * @param  frame  Latest biometric frame to transmit.
 */
void ant_profile_update(const biometric_frame_t *frame)
{
#if defined(CONFIG_ANT)
	if (!m_open || frame == NULL) {
		return;
	}
	pack_page(frame, m_tx_buf);

	/*
	 * Hand the new bytes to the stack. It keeps re-broadcasting this buffer
	 * every channel period until replaced, so a single call per sample tick
	 * is enough; the EVENT_TX handler also re-arms it defensively.
	 */
	uint32_t rc = sd_ant_broadcast_message_tx(ANT_CHANNEL_NUM, ANT_PAGE_LEN,
						  m_tx_buf);
	if (rc != NRF_SUCCESS) {
		LOG_DBG("broadcast_tx update rc=0x%lx", (unsigned long)rc);
	}
#else
	ARG_UNUSED(frame);
#endif
}

/* ============================================================
 *  PRIVATE FUNCTIONS
 * ============================================================ */
#if defined(CONFIG_ANT)

/**
 * @brief  ANT stack event handler (registered via NRF_SDH_ANT_OBSERVER).
 * @param  evt      The ANT event from the stack.
 * @param  context  Unused observer context.
 *
 * On each EVENT_TX (a page just went out) we re-load the buffer with the most
 * recent payload. This guarantees the very next slot carries current data even
 * if ant_profile_update() has not been called since the last transmission.
 */
static void ant_evt_handler(ant_evt_t *evt, void *context)
{
	ARG_UNUSED(context);

	if (evt->channel != ANT_CHANNEL_NUM) {
		return;
	}

	if (evt->event == EVENT_TX) {
		(void)sd_ant_broadcast_message_tx(ANT_CHANNEL_NUM, ANT_PAGE_LEN,
						  m_tx_buf);
	}
}

/**
 * @brief  Serialise a biometric frame into the 8-byte ANT page.
 * @param  frame  Source frame.
 * @param  buf    Destination 8-byte page buffer.
 *
 * Layout matches the table in ant_profile.h. Temperatures are scaled to
 * 0.01 deg C signed; EDA to 0.1 microsiemens unsigned. All little-endian to
 * match the host-side unpacker and the BLE payload.
 */
static void pack_page(const biometric_frame_t *frame, uint8_t *buf)
{
	int16_t  core = (int16_t)(frame->core[0].core_temp_c * 100.0f);
	int16_t  skin = (int16_t)(frame->stack[0].skin_temp_c * 100.0f);
	uint16_t eda  = (uint16_t)(frame->eda.conductance_us * 10.0f);

	buf[0] = APP_ANT_DATA_PAGE;
	buf[1] = frame->flags;
	buf[2] = (uint8_t)(core & 0xFF);
	buf[3] = (uint8_t)((core >> 8) & 0xFF);
	buf[4] = (uint8_t)(skin & 0xFF);
	buf[5] = (uint8_t)((skin >> 8) & 0xFF);
	buf[6] = (uint8_t)(eda & 0xFF);
	buf[7] = (uint8_t)((eda >> 8) & 0xFF);
}

#endif /* CONFIG_ANT */

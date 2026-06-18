/**
 * ============================================================================
 *  File:    ant_profile.h
 *  Purpose: ANT+ broadcast of the biometric frame (primary protocol).
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    ANT+ is the primary link. This module opens one ANT master channel and
 *    broadcasts a custom 8-byte data page at a fixed period so an ANT+
 *    receiver (e.g. a Garmin Forerunner 955) can pick up the strap's data.
 *    Built on the NCS ANT add-on broadcast-TX sample.
 *
 *    ANT data page layout (page number = APP_ANT_DATA_PAGE):
 *        Byte 0 : page number
 *        Byte 1 : fault/status flags (mirrors biometric_frame_t.flags)
 *        Byte 2 : core temp  LSB \  int16, 0.01 deg C, stack 0
 *        Byte 3 : core temp  MSB /
 *        Byte 4 : skin temp  LSB \  int16, 0.01 deg C, stack 0
 *        Byte 5 : skin temp  MSB /
 *        Byte 6 : EDA        LSB \  uint16, 0.1 microsiemens
 *        Byte 7 : EDA        MSB /
 * ============================================================================
 */

#ifndef ANT_PROFILE_H_
#define ANT_PROFILE_H_

#include "app_data.h"

/**
 * @brief  Configure and open the ANT master broadcast channel.
 * @return 0 on success, negative errno on stack/channel failure.
 *
 * When CONFIG_ANT is not enabled this is a logged no-op returning -ENOTSUP,
 * so the build still links and BLE-only bring-up is possible.
 */
int ant_profile_init(void);

/**
 * @brief  Refresh the broadcast payload with the latest frame.
 * @param  frame  Latest biometric frame to transmit.
 *
 * The ANT stack repeats the buffered page automatically at the channel period;
 * this only swaps in fresh bytes for the next transmission.
 */
void ant_profile_update(const biometric_frame_t *frame);

#endif /* ANT_PROFILE_H_ */

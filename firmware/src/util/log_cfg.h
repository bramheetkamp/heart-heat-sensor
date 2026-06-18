/**
 * ============================================================================
 *  File:    log_cfg.h
 *  Purpose: Common logging conventions for the firmware modules.
 *  Author:  Daan
 *  Date:    2026-06-14
 *
 *  Description:
 *    Zephyr's logging is per-module: each .c calls LOG_MODULE_REGISTER() with
 *    its own name and level. This header just centralises the default level
 *    and a couple of conventions so every module logs consistently. It does
 *    not register a module itself.
 * ============================================================================
 */

#ifndef LOG_CFG_H_
#define LOG_CFG_H_

#include <zephyr/logging/log.h>

/*
 * Default per-module log level when a module does not override it. During
 * bring-up INF is a good balance; drop to WRN for a quiet field unit. Set the
 * subsystem level in prj.conf (CONFIG_LOG_DEFAULT_LEVEL).
 */
#ifndef APP_LOG_LEVEL
#define APP_LOG_LEVEL LOG_LEVEL_INF
#endif

#endif /* LOG_CFG_H_ */

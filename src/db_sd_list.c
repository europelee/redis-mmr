/* db_sd_list.c - Selective sync and persist functionality (database level)
 *
 * Copyright (c) 2009-Present, Redis Ltd.
 * All rights reserved.
 *
 * Licensed under your choice of (a) the Redis Source Available License 2.0
 * (RSALv2); or (b) the Server Side Public License v1 (SSPLv1); or (c) the
 * GNU Affero General Public License v3 (AGPLv3).
 */

#include "server.h"

/* Check if a database index is in the db_sd_list
 * Returns:
 *   1: db is in the list (should sync/persist)
 *   0: db is not in the list (should NOT sync/persist)
 *   1: list is empty or NULL (allow all databases, backward compatible)
 */
int dbIndexInSdList(int dbid) {
    /* If bitmap is NULL, allow all databases (backward compatible) */
    if (server.db_sd_bitmap == NULL) {
        return 1;
    }

    /* Check bounds */
    if (dbid < 0 || dbid >= server.dbnum) {
        return 0;
    }

    /* Check bit in bitmap */
    return (server.db_sd_bitmap[dbid / 8] & (1 << (dbid % 8))) != 0;
}

/* Free the db_sd_list configuration */
void freeDbSdList(void) {
    /* Free the bitmap */
    if (server.db_sd_bitmap) {
        zfree(server.db_sd_bitmap);
        server.db_sd_bitmap = NULL;
        server.db_sd_bitmap_size = 0;
    }
    /* Note: server.db_sd_list_str is managed by the config system */
}

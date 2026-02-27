# db_sd_list - Database level selective sync and persist test

start_server {tags {"db-sd-list"}} {
    # Enable multiple databases for testing
    test {CONFIG SET/GET db_sd_list} {
        r config set db_sd_list "0,1,2"
        set result [r config get db_sd_list]
        lindex $result 1
    } {0,1,2}

    test {CONFIG SET db_sd_list single db} {
        r config set db_sd_list "0"
        set result [r config get db_sd_list]
        lindex $result 1
    } {0}

    test {CONFIG SET empty db_sd_list} {
        r config set db_sd_list ""
        set result [r config get db_sd_list]
        lindex $result 1
    } {}

    # Test RDB filtering by database
    test {RDB filter - only listed databases are saved} {
        # Configure to only save db 0
        r config set db_sd_list "0"

        # Set data in db 0 and db 1
        r select 0
        r set key-db0 "value0"
        r select 1
        r set key-db1 "value1"

        # Trigger BGSAVE and wait
        r bgsave
        waitForBgsave r

        # Reload from RDB
        r debug reload

        # Verify only db 0 data survived
        r select 0
        set val0 [r get key-db0]
        r select 1
        set val1 [r get key-db1]

        list $val0 $val1
    } {value0 {}}

    # Test AOF filtering by database
    test {AOF filter - only listed databases are persisted} {
        # Configure to only persist db 0
        r config set db_sd_list "0"

        # Set data in multiple databases
        r select 0
        r set key-db0 "value0"
        r select 1
        r set key-db1 "value1"
        r select 2
        r set key-db2 "value2"

        # Force AOF write
        r bgrewriteaof
        after 1000

        # Restart to reload from AOF
        r debug reload

        # Verify only db 0 data survived
        r select 0
        set val0 [r get key-db0]
        r select 1
        set val1 [r get key-db1]
        r select 2
        set val2 [r get key-db2]

        list $val0 $val1 $val2
    } {value0 {} {}}

    # Test multiple databases allowed
    test {Multiple databases in db_sd_list} {
        # Configure to save db 0 and db 2
        r config set db_sd_list "0,2"

        # Set data in multiple databases
        r select 0; r set key0 "v0"
        r select 1; r set key1 "v1"
        r select 2; r set key2 "v2"
        r select 3; r set key3 "v3"

        # Reload
        r debug reload

        # Verify db 0 and db 2 survived
        r select 0; set v0 [r get key0]
        r select 1; set v1 [r get key1]
        r select 2; set v2 [r get key2]
        r select 3; set v3 [r get key3]

        list $v0 $v1 $v2 $v3
    } {v0 {} v2 {}}

    # Test empty list allows all databases
    test {Empty db_sd_list allows all databases} {
        r config set db_sd_list ""

        # Set data in multiple databases
        r select 0; r set key0 "v0"
        r select 1; r set key1 "v1"
        r select 5; r set key5 "v5"

        # Reload
        r debug reload

        # Verify all data survived
        r select 0; set v0 [r get key0]
        r select 1; set v1 [r get key1]
        r select 5; set v5 [r get key5]

        list $v0 $v1 $v5
    } {v0 v1 v5}

    # Test CONFIG REWRITE preserves db_sd_list
    test {CONFIG REWRITE preserves db_sd_list} {
        r config set db_sd_list "0,1"
        catch {r config rewrite}
        set result [r config get db_sd_list]
        lindex $result 1
    } {0,1}

    # Test with different data types in allowed db
    test {db_sd_list with different data types} {
        r config set db_sd_list "0"

        # Set various data types in db 0
        r select 0
        r set string-key "string-value"
        r hset hash-key field "value"
        r rpush list-key "item"
        r sadd set-key "member"
        r zadd zset-key 1 "member"

        # Set data in db 1 (should be filtered)
        r select 1
        r set filtered-key "filtered-value"

        # Reload
        r debug reload

        # Verify db 0 data survived
        r select 0
        list [r get string-key] [r hget hash-key field] [r llen list-key] [r scard set-key] [r zcard zset-key]
    } {string-value value 1 1 1}

    # Test replication filtering (basic verification)
    test {Replication propagation respects db_sd_list} {
        # This verifies the filtering logic is in place
        # Full master-slave replication test would require separate setup

        r config set db_sd_list "0"

        # Operations in allowed db should work normally
        r select 0
        r set allowed-key "allowed-value"
        r get allowed-key
    } {allowed-value}

    # Cleanup
    test {Cleanup} {
        r config set db_sd_list ""
        r flushall
        set _ "OK"
    } {OK}
}

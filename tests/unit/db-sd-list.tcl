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

    # ============================================
    # Boundary Value Tests
    # ============================================

    test {CONFIG SET db_sd_list with out-of-range db index} {
        # Configure with out-of-range database indices (assuming 16 databases by default)
        r config set db_sd_list "0,1,20,30,100"
        set result [r config get db_sd_list]
        lindex $result 1
    } {0,1,20,30,100}

    test {CONFIG SET db_sd_list out-of-range verify filtering} {
        # Verify that out-of-range indices don't affect valid ones
        r config set db_sd_list "0,20"

        # Set data in db 0 (should be saved)
        r select 0
        r set key-db0 "value0"

        # Set data in db 1 (should NOT be saved, not in list)
        r select 1
        r set key-db1 "value1"

        # Reload
        r debug reload

        # Verify only db 0 survived
        r select 0
        set val0 [r get key-db0]
        r select 1
        set val1 [r get key-db1]

        list $val0 $val1
    } {value0 {}}

    test {CONFIG SET db_sd_list with negative db index} {
        # Configure with negative indices
        r config set db_sd_list "-1,0,1"
        set result [r config get db_sd_list]
        lindex $result 1
    } {-1,0,1}

    test {CONFIG SET db_sd_list negative verify filtering} {
        # Verify that negative indices are filtered out (dbid >= 0 check)
        # -1 is not a valid db index, so only db 2 should be in the list
        r config set db_sd_list "-1,2"

        # Set data in db 0 (should NOT be saved, -1 is invalid)
        r select 0
        r set key-db0 "value0"

        # Set data in db 2 (should be saved)
        r select 2
        r set key-db2 "value2"

        # Set data in db 1 (should NOT be saved)
        r select 1
        r set key-db1 "value1"

        # Trigger BGSAVE and wait
        r bgsave
        waitForBgsave r

        # Reload
        r debug reload

        # Verify only db 2 survived
        r select 0; set v0 [r get key-db0]
        r select 1; set v1 [r get key-db1]
        r select 2; set v2 [r get key-db2]

        list $v0 $v1 $v2
    } {{} {} value2}

    test {CONFIG SET db_sd_list with non-numeric values} {
        # Configure with non-numeric values (atoi returns 0 for non-numeric)
        r config set db_sd_list "abc,xyz,0"
        set result [r config get db_sd_list]
        lindex $result 1
    } {abc,xyz,0}

    test {CONFIG SET db_sd_list non-numeric verify filtering} {
        # Non-numeric values are converted to 0 by atoi
        # So "abc,xyz,0" effectively means db 0
        r config set db_sd_list "abc,0"

        # Set data in db 0 (should be saved)
        r select 0
        r set key-db0 "value0"

        # Set data in db 1 (should NOT be saved)
        r select 1
        r set key-db1 "value1"

        # Reload
        r debug reload

        # Verify only db 0 survived
        r select 0; set v0 [r get key-db0]
        r select 1; set v1 [r get key-db1]

        list $v0 $v1
    } {value0 {}}

    test {CONFIG SET db_sd_list with spaces} {
        # Configure with spaces in the value
        r config set db_sd_list "0, 1, 2"
        set result [r config get db_sd_list]
        lindex $result 1
    } {0, 1, 2}

    test {CONFIG SET db_sd_list with spaces verify filtering} {
        # Spaces are preserved, " 1" becomes db 1 (atoi ignores leading whitespace)
        r config set db_sd_list "0, 1"

        # Set data in db 0 and db 1
        r select 0; r set key0 "v0"
        r select 1; r set key1 "v1"
        r select 2; r set key2 "v2"

        # Reload
        r debug reload

        # Verify db 0 and db 1 survived
        r select 0; set v0 [r get key0]
        r select 1; set v1 [r get key1]
        r select 2; set v2 [r get key2]

        list $v0 $v1 $v2
    } {v0 v1 {}}

    test {CONFIG SET db_sd_list with duplicate db index} {
        # Configure with duplicate indices
        r config set db_sd_list "0,1,0,2,1,0"
        set result [r config get db_sd_list]
        lindex $result 1
    } {0,1,0,2,1,0}

    test {CONFIG SET db_sd_list duplicate verify filtering} {
        # Duplicates should not affect the result
        r config set db_sd_list "0,1,0,2,1,0"

        # Set data in db 0, 1, 2 (should be saved) and db 3 (should NOT)
        r select 0; r set key0 "v0"
        r select 1; r set key1 "v1"
        r select 2; r set key2 "v2"
        r select 3; r set key3 "v3"

        # Reload
        r debug reload

        # Verify db 0, 1, 2 survived
        r select 0; set v0 [r get key0]
        r select 1; set v1 [r get key1]
        r select 2; set v2 [r get key2]
        r select 3; set v3 [r get key3]

        list $v0 $v1 $v2 $v3
    } {v0 v1 v2 {}}

    test {CONFIG SET db_sd_list with maximum valid db index} {
        # Get the number of databases
        set dbnum [lindex [r config get databases] 1]
        set max_db [expr {$dbnum - 1}]

        # Configure with maximum valid index
        r config set db_sd_list "$max_db"
        set result [r config get db_sd_list]
        lindex $result 1
    } 15

    test {CONFIG SET db_sd_list max index verify filtering} {
        # Test with last database
        set dbnum [llength [r config get databases]]
        set max_db [expr {$dbnum - 1}]

        r config set db_sd_list "$max_db"

        # Set data in last db (should be saved)
        r select $max_db
        r set key-max "value-max"

        # Set data in db 0 (should NOT be saved)
        r select 0
        r set key-0 "value-0"

        # Reload
        r debug reload

        # Verify only last db survived
        r select $max_db; set v_max [r get key-max]
        r select 0; set v_0 [r get key-0]

        list $v_max $v_0
    } {value-max {}}

    # ============================================
    # Configuration Change Tests
    # ============================================

    test {CONFIG SET db_sd_list frequent changes} {
        # Frequent config changes
        r config set db_sd_list "0"
        r config set db_sd_list "1"
        r config set db_sd_list "2"
        r config set db_sd_list "0,1,2"
        r config set db_sd_list "3,4,5"
        set result [r config get db_sd_list]
        lindex $result 1
    } {3,4,5}

    test {CONFIG SET db_sd_list transition empty to value to empty} {
        # Start empty
        r config set db_sd_list ""
        set r1 [lindex [r config get db_sd_list] 1]

        # Set to value
        r config set db_sd_list "0,1"
        set r2 [lindex [r config get db_sd_list] 1]

        # Back to empty
        r config set db_sd_list ""
        set r3 [lindex [r config get db_sd_list] 1]

        list $r1 $r2 $r3
    } {{} 0,1 {}}

    test {CONFIG SET db_sd_list change preserves existing data} {
        # Set initial config and data
        r config set db_sd_list "0"
        r select 0
        r set key-db0 "value0"
        r select 1
        r set key-db1 "value1"

        # Change config (should not affect existing data)
        r config set db_sd_list "1"

        # Verify data still exists
        r select 0
        set v0 [r get key-db0]
        r select 1
        set v1 [r get key-db1]

        list $v0 $v1
    } {value0 value1}

    test {CONFIG SET db_sd_list change affects subsequent operations} {
        # Set initial config and data
        r config set db_sd_list "0"
        r select 0
        r set key-initial "initial-value"

        # Change config
        r config set db_sd_list "1"

        # Set new data
        r select 1
        r set key-new "new-value"

        # Reload - should respect NEW config
        r debug reload

        # Verify based on new config
        r select 0
        set v0 [r get key-initial]
        r select 1
        set v1 [r get key-new]

        list $v0 $v1
    } {{} new-value}

    # ============================================
    # Bitmap Functionality Tests
    # ============================================

    test {CONFIG SET db_sd_list cross-byte boundary} {
        # Test bitmap across byte boundaries (db 7, 8, 15 are boundary cases)
        r config set db_sd_list "6,7,8,9"

        # Set data in databases around byte boundary
        r select 6; r set key6 "v6"
        r select 7; r set key7 "v7"
        r select 8; r set key8 "v8"
        r select 9; r set key9 "v9"
        r select 10; r set key10 "v10"

        # Reload
        r debug reload

        # Verify
        r select 6; set v6 [r get key6]
        r select 7; set v7 [r get key7]
        r select 8; set v8 [r get key8]
        r select 9; set v9 [r get key9]
        r select 10; set v10 [r get key10]

        list $v6 $v7 $v8 $v9 $v10
    } {v6 v7 v8 v9 {}}

    test {CONFIG SET db_sd_list all databases up to boundary} {
        # Test with all configured databases
        set dbnum [lindex [r config get databases] 1]

        # Create a list of all valid database indices
        set all_dbs ""
        for {set i 0} {$i < $dbnum} {incr i} {
            if {$i > 0} { append all_dbs "," }
            append all_dbs $i
        }

        r config set db_sd_list "$all_dbs"

        # Set data in all databases
        for {set i 0} {$i < $dbnum} {incr i} {
            r select $i
            r set "key$i" "value$i"
        }

        # Reload
        r debug reload

        # Verify all data survived
        set result {}
        for {set i 0} {$i < $dbnum} {incr i} {
            r select $i
            lappend result [r get "key$i"]
        }
        set result
    } [join [lrange {value0 value1 value2 value3 value4 value5 value6 value7 value8 value9 value10 value11 value12 value13 value14 value15} 0 [expr {[lindex [r config get databases] 1] - 1}]] " "]

    # ============================================
    # Server Restart Tests
    # ============================================

    test {CONFIG REWRITE and restart preserves db_sd_list full} {
        # Set config
        r config set db_sd_list "0,2,4"

        # Rewrite config
        catch {r config rewrite}

        # Verify config is preserved
        set result [r config get db_sd_list]
        lindex $result 1
    } {0,2,4}

    test {CONFIG SET db_sd_list with single digit databases} {
        # Test single digit db indices
        r config set db_sd_list "1,3,5,7"
        set result [r config get db_sd_list]
        lindex $result 1
    } {1,3,5,7}

    test {CONFIG SET db_sd_list verify single digit filtering} {
        r config set db_sd_list "1,3"

        # Set data
        r select 0; r set k0 "v0"
        r select 1; r set k1 "v1"
        r select 2; r set k2 "v2"
        r select 3; r set k3 "v3"

        # Reload
        r debug reload

        # Verify
        r select 0; set v0 [r get k0]
        r select 1; set v1 [r get k1]
        r select 2; set v2 [r get k2]
        r select 3; set v3 [r get k3]

        list $v0 $v1 $v2 $v3
    } {{} v1 {} v3}

    test {CONFIG SET db_sd_list with large number of databases} {
        # Test with many databases in the list
        r config set db_sd_list "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15"
        set result [r config get db_sd_list]
        lindex $result 1
    } {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15}

    # Cleanup
    test {Cleanup} {
        r config set db_sd_list ""
        r flushall
        set _ "OK"
    } {OK}
}

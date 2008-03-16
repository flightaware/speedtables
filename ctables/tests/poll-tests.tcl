#
#
#
#
#
# $Id$
#

source test_common.tcl

source top-brands-nokey-def.tcl

proc suck_in_top_brands {args} {
    set fp [open top-brands.tsv]
    set result [eval t read_tabsep $fp $args]
    close $fp
    return $result
}

global error_count
set error_count 0
global expected_error
proc ::bgerror {error} {
    global error_count
    global expected_error
    incr error_count
    if {[info exists expected_error] && "$error" != "$expected_error"} {
	error "Expected '$expected_error' got '$error'"
    }
}

puts "Load up the database"
if {[set k [suck_in_top_brands -nokeys]] != 99} {
    error "expected autokey of 99 got $k"
}
if {[set k [suck_in_top_brands -nokeys]] != 199} {
    error "expected autokey of 199 got $k"
}
if {[set k [suck_in_top_brands -nokeys]] != 299} {
    error "expected autokey of 299 got $k"
}

if {[t count] != 300} {
    error "expected count of 300 but got [t count]"
}

puts "Scan database, poll every 10 rows"
set polls 0
set count [t search -compare {{= id aol}} -poll_interval 10 -poll_code {incr polls}]
if {$count != 3} {
    error "expected count of 3 but got $count"
}
if {$polls != 30} {
    error "expected 30 polls but got $polls"
}

puts "Check errors"
set expected_error {invalid command name "booyah"}
set count [t search -compare {{= id aol}} -poll_interval 10 -poll_code {booyah}]
if {$count != 3} {
    error "expected count of 3 but got $count"
}
update
if {$error_count != 30} {
    error "expected 30 errors but got $error_count"
}


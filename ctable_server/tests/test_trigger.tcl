# $Id$

package require ctable_client

remote_ctable sttp://localhost:1984/test c_test

set status 0

if [catch {
    puts "version=[c_test info]"

    # Provide a test trigger
    c_test eval {
	proc set_proc {url ctable command args} {
	    puts "@@@@@@@@@@@@ [info level 0]"
	    array set tmp [lassign $args key]
	    if {"$key" == "*"} {
		if [info exists tmp(id)] {
		    set key $tmp(id)
		    return -code return [
			$ctable set $tmp(id) [array get tmp]
		    ]
		}
	    }
	}
    }
    c_test trigger set set_proc

    c_test set * name pizza value pepperoni id 101
    c_test set * name tea value "earl grey, hot" id 45

    c_test search -key k -array_get _a -code {
	puts "$k: $_a"
    }
} err] {
   puts "Test failed - $err"
   puts $::errorInfo
   set status 1
}

c_test shutdown

exit $status

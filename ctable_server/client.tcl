#
#
#
#
#
#

proc remote_ctable {host tableName} {
    proc $tableName {args} "remote_ctable_invoke $tableName $host \$args"
}

proc remote_ctable_invoke {tableName host command} {
    variable hostSockets

    if {![info exists hostSockets($host)]} {
	set hostSockets($host) [socket $host 11111]
    }

    puts $hostSockets($host) [list $tableName $command]
    flush $hostSockets($host)

    gets $hostSockets($host) line

    switch [lindex $line 0] {
	"e" {
	    error [lindex $line 1] [lindex $line 2] [lindex $line 3]
	}

	"k" {
	    return [lindex $line 1]
	}

	default {
	    error "unknown command response"
	}
    }
}



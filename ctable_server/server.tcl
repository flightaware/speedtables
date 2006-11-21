#
#
#
#
#
#

package require Tclx

namespace eval ::ctable_server {
  variable registeredCtables

proc register {table} {
    variable registeredCtables

    set registeredCtables($table) ""
}

proc register_instantiator {cTable} {
    variable registeredCtableCreators

    set registeredCtableCreators($cTable) ""
}

proc setup {} {
    socket -server ::ctable_server::accept_connection 11111
}

proc accept_connection {sock ip port} {
    puts "connect from $sock $ip $port"

    fconfigure $sock -blocking 0 -translation binary
    fileevent $sock readable [list ::ctable_server::remote_receive $sock]
}

proc remote_receive {sock} {
    global errorCode errorInfo

    if {[eof $sock]} {
	puts stderr "EOF on $sock, closing"
	close $sock
	return
    }

    if {[gets $sock line] >= 0} {
	if {[catch {remote_invoke $line} result] == 1} {
	    puts $sock [list e $result $errorInfo $errorCode]
	} else {
	    puts $sock [list k $result]
	}
	flush $sock
    }
}

#
# instantiate - create an instance of a ctable and register it
#
proc instantiate {ctableCreator ctable} {
    variable registeredCtables
    variable registeredCtableCreators

    if {![info exists registeredCtableCreators($ctableCreator)]} {
	error "unregistered ctable creator: $ctableCreator"
    }

    if {[info exists registeredCtables($ctable)]} {
	error "ctable '$ctable' of creator '$ctableCreator' already exists"
    }

    register $ctable
    return [$ctableCreator create $ctable]
}

proc remote_invoke {line} {
    variable registeredCtables

    set args [lassign $line ctable command]

    if {$command == "instantiate"} {
	return [instantiate $ctable [lindex $args 0]]
    }

    if {![info exists registeredCtables($ctable)]} {
	error "ctable $ctable not registered on this server"
    }

    switch $command {
	destroy {
	    error "forbidden"
	}

	instantiate {
	    error "should not get herre"
	}

	foreach {
	    $ctable foreach ZZ
	}

	default {
	    eval $ctable $command $args
	}
    }
}

}

#get, set, array_get, array_get_with_nulls, exists, delete, count, foreach, sort, type, import, import_postgres_result, export, fields, fieldtype, needs_quoting, names, reset, destroy, statistics, write_tabsep, or read_tabsep

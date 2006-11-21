#
# Ctable Server 
#
# $Id$
#

package require Tclx

namespace eval ::ctable_server {
  variable registeredCtables
  variable evalEnabled

  set evalEnabled 1

#
# register - register a table for remote access
#
proc register {table {type ""}} {
    variable registeredCtables

    set registeredCtables($table) $type
}

#
# register_instantiator - register a ctable creator
#
proc register_instantiator {cTable} {
    variable registeredCtableCreators

    set registeredCtableCreators($cTable) ""
}

#
# setup - setup our server socket
#
proc setup {} {
    set serverSock [socket -server ::ctable_server::accept_connection 11111]
}

#
# accept_connection - accept a client connection
#
proc accept_connection {sock ip port} {
    puts "connect from $sock $ip $port"

    fconfigure $sock -blocking 0 -translation auto
    fileevent $sock readable [list ::ctable_server::remote_receive $sock]
}

#
# remote_receive - receive data from the remote side
#
proc remote_receive {sock} {
    global errorCode errorInfo

    if {[eof $sock]} {
	puts stderr "EOF on $sock, closing"
	close $sock
	return
    }

    if {[gets $sock line] >= 0} {
	if {[catch {remote_invoke $sock $line} result] == 1} {
	    puts "got '$result' processing '$line' from $sock"
	    # look at errorInfo if you want to know more, don't send it
	    # back to them -- it exposes stuff about us they don't care
	    # about
	    if {$errorCode == "ctable_quit"} return
	    puts $sock [list e $result "" $errorCode]
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
	error "unregistered ctable creator: $ctableCreator" "" CTABLE
    }

    if {[info exists registeredCtables($ctable)]} {
	#error "ctable '$ctable' of creator '$ctableCreator' already exists" "" CTABLE
	return ""
    }

    register $ctable
    return [$ctableCreator create $ctable]
}

proc remote_invoke {sock line} {
    variable registeredCtables
    variable registeredCtableCreators
    variable evalEnabled

    puts "remote_invoke '$sock' '$line'"

    set remoteArgs [lassign $line command ctable]
    puts "command '$command' ctable '$ctable' args '$remoteArgs'"

    switch $command {
	"quit" {
	    close $sock
	    error "quit" "" ctable_quit
	}

	"create" {
	    return [instantiate $ctable [lindex $remoteArgs 0]]
	}

	"tablemakers" {
	    return [lsort [array names registeredCtableCreators]]
	}

	"tables" {
	    set result ""
	    foreach table [array names registeredCtables] {
		lappend result $table $registeredCtables($table)
	    }
	    return $result
	}

	"eval" {
	    if {!$evalEnabled} {
		error "not permitted"
	    }

	    return [uplevel #0 $ctable $remoteArgs]
	}

	"help" {
	    return "quit; create tableCreator tableName; tablemakers; tables; or a ctable name"
	}
    }

    if {![info exists registeredCtables($ctable)]} {
	error "ctable $ctable not registered on this server" "" CTABLE
    }

    switch $command {
	foreach {
	    $ctable foreach ZZ
	}

	get_tabsep {
	    set cmd [linsert $remoteArgs 0 $ctable write_tabsep $sock]
	    puts '$cmd'
	    puts $sock "m"
	    set result [eval $cmd]
	    puts $sock ""
	    return $result
	}

	default {
	    set cmd [linsert $remoteArgs 0 $ctable $command]
	    puts '$cmd'
	    return [eval $cmd]
	}
    }
}

}

#get, set, array_get, array_get_with_nulls, exists, delete, count, foreach, sort, type, import, import_postgres_result, export, fields, fieldtype, needs_quoting, names, reset, destroy, statistics, write_tabsep, or read_tabsep

#
# Ctable Server 
#
# $Id$
#

package require Tclx
package require ctable_net

namespace eval ::ctable_server {
  variable registeredCtables
  variable evalEnabled 1
  variable serverVersion 1.0
  variable serverCommands {
    shutdown		""
    redirect		{remoteURL [-shutdown]}
    quit		""
    info		{[-verbose]}
    create		ctableName
    sequence		{{field *} {initial 0} {format %d}}
    sequenced		""
    tablemakers		""
    tables		""
    help		""
  }

#
# serverInfo - list of information about this ctable server
#
# returns the version followed by a list of extended commands
#
proc serverInfo {verbose} {
    variable serverVersion
    variable serverCommands
    variable evalEnabled

    lappend result $serverVersion
    foreach {command args} $serverCommands {
	if {$verbose && [llength $args]} {
	    lappend result [list $command $args]
	} else {
	    lappend result $command
	}
    }

    if $evalEnabled {
	if $verbose {
	    lappend result [list eval code]
	} else {
	    lappend result eval
	}
    }
    return $result
}


#
# Variables for "shutdown" command
#
  variable shuttingDown 0
  variable clientList {}

#
# register - register a table for remote access
#
proc register {ctableUrl localTableName {type ""}} {
    variable registeredCtables

    lassign [::ctable_net::split_ctable_url $ctableUrl] host port dir exportedTableName options

    serverlog "register $ctableUrl $exportedTableName $type"
    set registeredCtables($exportedTableName) $localTableName

    start_server $port
}

#
# sequence - specify a sequence key for a ctable
#
proc sequence {ctableURL {initial 0} {format %d}} {
    sequenceField $ctableURL * $initial $format
}

#
# sequence - specify a sequence field for a ctable
#
proc sequenceField {ctableURL {field *} {initial 0} {format %d}} {
    variable seqFld
    variable seqVal
    variable seqFmt

    serverlog [info level 0]
    if {"$field" != "*"} {
	set seqFld($ctableURL) $field
    }
    set seqVal($ctableURL) $initial
    set seqFmt($ctableURL) $format
}

#
# register_instantiator - register a ctable creator
#
proc register_instantiator {cTable} {
    variable registeredCtableCreators

    set registeredCtableCreators($cTable) ""
}

proc register_redirect {ctableUrl redirectedToCtableUrl} {
    lassign [::ctable_net::split_ctable_url $ctableUrl] host port dir table options

    register_redirect_ctable $table $port $redirectedToCtableUrl
}

proc register_redirect_ctable {table port redirectedToCtableUrl} {
    variable registeredCtableRedirects
    variable ctableUrlCache
    start_server $port

    serverlog "register_redirect_ctable $table:$port $redirectedToCtableUrl"
    set registeredCtableRedirects($table:$port) $redirectedToCtableUrl

    # Uncache all URLs that refer to the table we're redirecting - this
    # is possibly overkill but the cost of a one-time cache revocation
    # is minimal. We could probably trash the whole cache here and be OK.
    foreach name [array names ctableUrlCache "*/$table*"] {
	unset ctableUrlCache($name)
    }
}

#
# start_server - setup  server socket
#
proc start_server {{port 11111}} {
    variable portSockets

    if {[info exists portSockets($port)]} {
	return
    }
    set serverSock [socket -server ::ctable_server::accept_connection $port]

    set portSockets($port) $serverSock
}

#
# shutdown_servers - close server sockets and flag the system to shut down
#
proc shutdown_servers {} {
    variable portSockets
    variable shuttingDown

    foreach {port sock} [array get portSockets] {
	serverlog "Closing $sock on $port"
	close $sock
	unset portSockets($port)
    }
    serverlog "Requesting shutdown"
    set shuttingDown 1
}

#
# accept_connection - accept a client connection
#
proc accept_connection {sock ip port} {
    variable clientList
    lappend clientList $sock $ip $port
    serverlog "connect from $sock $ip $port"

    set theirPort [lindex [fconfigure $sock -sockname] 2]

    fconfigure $sock -blocking 0 -translation auto
    fileevent $sock readable [list ::ctable_server::remote_receive $sock $theirPort]

    remote_send $sock [list ctable_server 1.0 ready] 0
}

#
# remote_receive - receive data from the remote side
#
proc remote_receive {sock myPort} {
    global errorCode errorInfo
    variable registeredCtableRedirects
    variable ctableUrlCache

    if {[eof $sock]} {
	variable clientList
	variable shuttingDown
	set i [lsearch $clientList $sock]
	if {$i >= 0} {
	    set j [expr $i + 2]
	    set clientList [lreplace $clientList $i $j]
	}
	serverlog "EOF on $sock, closing"
	close $sock
	if {$shuttingDown} {
	    if {[llength $clientList] == 0} {
	        serverlog "All client sockets closed, shutting down"
	        exit 0
	    } else {
		serverlog "Waiting on [expr [llength $clientList] / 3] clients."
	    }
	}
	return
    }

    if {[gets $sock line] >= 0} {
	# "# NNNN" means a multi-line request NNNN bytes long
	if {"[lindex $line 0]" == "#"} {
	    set line [read $sock [lindex $line 1]]
	}
	lassign $line ctableUrl line 

	if {![info exists ctableUrlCache($ctableUrl)]} {
	    if [catch {
	      lassign [::ctable_net::split_ctable_url $ctableUrl] host port dir table options
	    } err] {
	      serverlog "$ctableUrl: $err" $::errorInfo
	      remote_send $sock [list e $err "" $::errorCode]
	      return
	    }

	    if {[info exists registeredCtableRedirects($table:$myPort)]} {
#puts "sending redirect to $sock, $ctableUrl -> $registeredCtableRedirects($table:$myPort)"
		remote_send $sock [list r $registeredCtableRedirects($table:$myPort)]
		return
	    }
#puts "setting ctable url cache $ctableUrl -> $table"
	    set ctableUrlCache($ctableUrl) $table
	} else {
	    set table $ctableUrlCache($ctableUrl)
	}

	if {[catch {remote_invoke $sock $table $line $myPort} result] == 1} {
	    serverlog "$table: $result" \
		"In ($sock) $ctableUrl $line" $::errorInfo
	    # look at errorInfo if you want to know more, don't send it
	    # back to them -- it exposes stuff about us they don't care
	    # about
	    if {$errorCode == "ctable_quit"} return
	    ### puts stdout [list e $result "" $errorCode]
	    remote_send $sock [list e $result "" $errorCode]
	} else {
	    ### puts stdout [list k $result]
	    remote_send $sock [list k $result]
	}
    }
}

#
# Send a response, and flush. If the response is multi-line send
# as "# NNNN" followed by the NNNN-byte response.
#
proc remote_send {sock line {multi 1}} {
    if {$multi && [string match "*\n*" $line]} {
	puts $sock "# [expr [string length $line] + 1]"
    }
    puts $sock $line
    flush $sock
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

proc remote_invoke {sock ctable line port} {
    variable registeredCtables
    variable registeredCtableCreators
    variable evalEnabled
    variable seqVal

    ### puts "remote_invoke '$sock' '$line'"

    set remoteArgs [lassign $line command]

    ### puts "command '$command' ctable '$ctable' args '$remoteArgs'"

    switch $command {
	"shutdown" {
	    return [shutdown_servers]
	}

	"redirect" {
	    register_redirect_ctable $ctable $port [lindex $remoteArgs 0]
            if {[info exists registeredCtables($ctable)]} {
		set old_ctable $registeredCtables($ctable)
		unset registeredCtables($ctable)
	    }
	    # If shutting down, don't bother to destroy the old ctable, it
	    # will go away soon anyway when we exit.
	    if {[string match "-shut*" [lindex $remoteArgs 1]]} {
		return [shutdown_servers]
	    } elseif {[info exists old_ctable]} {
		serverlog "Destroying $old_ctable"
	        $old_ctable destroy
	    }
	    serverlog "remotely redirected to [lindex $remoteArgs 0]"
	    return 1
	}

	"quit" {
	    close $sock
	    error "quit" "" ctable_quit
	}

	"create" {
	    return [instantiate $ctable [lindex $remoteArgs 0]]
	}

	"info" {
	    return [serverInfo [string match "-v*" [lindex $remoteArgs 0]]]
	}

	"sequence" {
	    eval [
		linsert $remoteArgs 0 sequenceField $ctable
	    ]
	    return 1
	}
	"sequenced" {
    	    if {[info exists seqVal($ctable)]} {
		variable seqFld
		variable seqFmt
		lappend result 1 [format $seqFmt($ctable) $seqVal($ctable)]
		if [info exists seqFld($ctable)] {
		    lappend result $seqFld($ctable)
		}
		return $result
	    }
	    return 0
	}

	"tablemakers" {
	    return [lsort [array names registeredCtableCreators]]
	}

	"tables" {
	    return [array names registeredCtables]
	}

	"eval" {
	    if {!$evalEnabled} {
		error "not permitted"
	    }

	    return [uplevel #0 [linsert $remoteArgs 0 $ctable]]
	}

	"help" {
	    return "shutdown; redirect new_url ?-shutdown?; quit; create tableCreator tableName; tablemakers; tables; or a ctable command"
	}
    }

    if {![info exists registeredCtables($ctable)]} {
	error "ctable $ctable not registered on this server" "" CTABLE
    }

    set myCtable $registeredCtables($ctable)

    set simpleCommand 1
    if [string match "search*" $command] {
	if {[lsearch -exact $remoteArgs "-countOnly"] == -1} {
	    set simpleCommand 0
	}
    }

    if {[info exists seqVal($ctable)] && "$command" == "set"} {
	variable seqFld
	variable seqFmt

	set pairs [lassign $remoteArgs key]

	if {[info exists seqFld($ctable)]} {
	    # Only sequence new rows
	    if ![$myCtable exists $key] {
		array set tmp $pairs
		if ![info exists tmp($seqFld($ctable))] {
		    lappend remoteArgs $seqFld($ctable) [
			format $seqFmt($ctable) [incr seqVal($ctable)]
		    ]
		}
	    }
	} else {
	    if {"[lindex $remoteArgs 0]" == "*"} {
		set remoteArgs [
		    linsert $pairs 0 [
			format $seqFmt($ctable) [incr seqVal($ctable)]
		    ]
		]
	    }
	}
    }

    if $simpleCommand {
	set cmd [linsert $remoteArgs 0 $myCtable $command]
#serverlog "simple command '$cmd'"
	return [eval $cmd]
    }

    # else it's a complex search command:
    set cmd [linsert $remoteArgs 0 $myCtable $command -write_tabsep $sock]
#puts "search command '$cmd'"
#puts "start multiline response"
    remote_send $sock "m"
#puts "evaling '$cmd'"
    set code [catch {eval $cmd} result]
    remote_send $sock "\\." 0
    ### puts "start sent multiline terminal response"
    return -code $code $result
}

proc serverlog {args} {
    if [llength $args] {
	set message "[clock format [clock seconds]] [pid]: [join $args "\n"]"
	if {[llength $args] > 1} {
	    set message "\n$message"
	}
	puts $message
    }
}

}

package provide ctable_server 1.0

#get, set, array_get, array_get_with_nulls, exists, delete, count, foreach, sort, type, import, import_postgres_result, export, fields, fieldtype, needs_quoting, names, reset, destroy, statistics, write_tabsep, or read_tabsep

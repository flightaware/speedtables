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
  # eval? command	args
  variable serverCommands {
    0 shutdown		""
    0 redirect		{remoteURL [-shutdown]}
    0 quit		""
    0 info		{[-verbose]}
    0 create		ctableName
    0 tablemakers		""
    0 tables		""
    0 help		""
    1 eval		{code}
    1 trigger		{?command? ?proc?}
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
    foreach {eval command args} $serverCommands {
	if {$eval && !$evalEnabled} {
	    continue
	}
	if {$verbose && [llength $args]} {
	    lappend result [list $command $args]
	} else {
	    lappend result $command
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
proc register {ctableUrl ctable {type ""}} {
    variable registeredCtables

    lassign [::ctable_net::split_ctable_url $ctableUrl] host port dir table options

    serverlog "register $ctableUrl $table $type"
    set registeredCtables($table) $ctable

    start_server $port
}

#
# setTrigger - specify trigger code for a ctable
#
# code is assumed to be a single list (or proc) and is called
# as "eval $code [list $ctableURL $ctable $command] $arguments"
#
# eg:
#   myHandler ctable://*:9999/foo ctable0 set key fieldname value...
#
proc setTrigger {ctableURL command code} {
    variable triggerCommands
    variable triggerCode

    lappend triggerCommands($ctableURL) $command
    set triggerCode($command:$ctableURL) $code
}

#
# register_instantiator - register a ctable creator
#
proc register_instantiator {creatorName {creator ""}} {
    variable registeredCtableCreators

    if {"$creator" == ""} {
	set creator $creatorName
    }
    set registeredCtableCreators($creatorName) $creator
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
	if {"$line" == ""} {
	    serverlog "blank line"
	    return
	}
	# "#NNNN" means a multi-line request NNNN bytes long
	if {"[string index $line 0]" == "#"} {
	    set line [read $sock [string trim [string range $line 1 end]]]
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
proc instantiate {creatorName ctableUrl} {
    variable registeredCtables
    variable registeredCtableCreators

    if {![info exists registeredCtableCreators($creatorName)]} {
	error "unregistered ctable creator: $creatorName" "" CTABLE
    }
    set ctableCreator $registeredCtableCreators($creatorName)

    if {[info exists registeredCtables($ctableUrl)]} {
	#error "ctable '$ctableUrl' of creator '$ctableCreator' already exists" "" CTABLE
	return ""
    }

    set ctable [$ctableCreator create $ctableUrl]
    register $ctableUrl $ctable
    return $ctable
}

proc remote_invoke {sock table line port} {
    variable registeredCtables
    variable registeredCtableCreators
    variable evalEnabled
    variable triggerCommands
    variable triggerCode

    ### puts "remote_invoke '$sock' '$line'"

    set remoteArgs [lassign $line command]

    ### puts "command '$command' ctable '$table' args '$remoteArgs'"

    switch $command {
	"shutdown" {
	    return [shutdown_servers]
	}

	"redirect" {
	    register_redirect_ctable $table $port [lindex $remoteArgs 0]
            if {[info exists registeredCtables($table)]} {
		set old_ctable $registeredCtables($table)
		unset registeredCtables($table)
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
	    return [instantiate $table [lindex $remoteArgs 0]]
	}

	"info" {
	    return [serverInfo [string match "-v*" [lindex $remoteArgs 0]]]
	}

	"trigger" {
	    if {!$evalEnabled} {
		error "not permitted"
	    }

	    unset -nocomplain cmd
	    set code [lassign $remoteArgs cmd]
	    if ![info exists cmd] {
		if [info exists triggerCommands($table)] {
		    return $triggerCommands($table)
		} else {
		    return ""
		}
	    }
	    if ![llength $code] {
		if [info exists triggerCode($cmd:$table)] {
		    return $triggerCode($cmd:$table)
		} else {
		    return ""
		}
	    }
	    return [setTrigger $table $cmd $code]
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

	    if [catch {uplevel #0 [lindex $remoteArgs 0]} result] {
	        serverlog $result [list uplevel #0 [lindex $remoteArgs 0]]
		error $result $::errorInfo
	    }
	    return $result
	}

	"help" {
	    set commands [lassign [serverInfo -verbose] version]
	    set text "Server version $version: "
	    foreach c $commands {
		lassign $c cmd args
		append text "$cmd $args; "
	    }
	    append text "or a ctable command"
	    return $text
	}
    }

    if {![info exists registeredCtables($table)]} {
	error "ctable $table not registered on this server" "" CTABLE
    }

    set ctable $registeredCtables($table)

    if [info exists triggerCode($command:$table)] {
	set cmd $triggerCode($command:$table)
	lappend cmd $table $ctable $command
	switch [catch [concat $cmd $remoteArgs] result] {
	    1 { error $result $::errorInfo }
	    2 { return $result }
	}
    }

    set simpleCommand 1
    if [string match "search*" $command] {
	if {[lsearch -exact $remoteArgs "-countOnly"] == -1} {
	    set simpleCommand 0
	}
    }

    if $simpleCommand {
	set cmd [linsert $remoteArgs 0 $ctable $command]
#serverlog "simple command '$cmd'"
	return [eval $cmd]
    }

    # else it's a complex search command:
    set cmd [linsert $remoteArgs 0 $ctable $command -write_tabsep $sock]
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

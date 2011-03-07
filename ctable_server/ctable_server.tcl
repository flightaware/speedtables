#
# Ctable Server 
#
# $Id$
#

package require Tclx
package require ctable_net

namespace eval ::ctable_server {
  variable registeredCtables

  variable bytesNeeded
  variable incompleteLine

  variable serverVersion 1.0
  variable protocolResponse ctable_server

  variable evalEnabled 1

  variable logfile stdout

  variable hideErrorInfo 1

  variable extensions
  variable quoteType
  set extensions(quote) quoteType

  # eval? command	args
  variable serverCommands {
    0 shutdown		{[-nowait]}
    0 redirect		{remoteURL [-shutdown]}
    0 quit		""
    0 info		{[-verbose]}
    0 create		tableName
    0 tablemakers		""
    0 tables		""
    0 help		""
    0 methods		""
    0 enable		"name ?value?"
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
# close_clients - close all open client sockets
#
proc close_clients {} {
    variable clientList

    foreach {sock ip port} $clientList {
	serverlog "Closing $sock on $port from $ip"
	close $sock
    }
    set clientList {}
}

#
# shutdown_servers - close server sockets and flag the system to shut down
#   on a clean shutdown
#
proc shutdown_servers {{clean 1}} {
    variable portSockets
    variable shuttingDown

    foreach {port sock} [array get portSockets] {
	serverlog "Closing $sock on $port"
	close $sock
	unset portSockets($port)
    }
    if {$clean} {
        serverlog "Requesting shutdown"
        set shuttingDown 1
    }
}

#
# accept_connection - accept a client connection
#
proc accept_connection {sock ip port} {
    variable clientList
    variable protocolResponse
    variable serverVersion
    lappend clientList $sock $ip $port
    serverlog "connect from $sock $ip $port"

    set theirPort [lindex [fconfigure $sock -sockname] 2]

    fconfigure $sock -blocking 0 -translation auto
    fileevent $sock readable [list ::ctable_server::remote_receive $sock $theirPort]

    remote_send $sock [list $protocolResponse $serverVersion ready] 0
}

#
# handle_eof - do the various bits of cleanup associated with a socket
#   closing, or the client requesting a socket be closed
#
proc handle_eof {sock {eof EOF}} {
    variable clientList
    variable shuttingDown

    set i [lsearch $clientList $sock]
    if {$i >= 0} {
	set j [expr $i + 2]
	set clientList [lreplace $clientList $i $j]
    }
    serverlog "$eof on $sock, closing"
    close $sock
    if {$shuttingDown} {
	if {[llength $clientList] == 0} {
	    serverdie "All client sockets closed, shutting down"
	} else {
	    serverlog "Waiting on [expr [llength $clientList] / 3] clients."
	}
    }
}

#
# remote_receive - receive data from the remote side
#
proc remote_receive {sock myPort} {
    global errorCode errorInfo
    variable registeredCtableRedirects
    variable ctableUrlCache
    variable incompleteLine
    variable bytesNeeded

### puts stderr "remote_receive '$sock' '$myPort'"; flush stderr

    if {[eof $sock]} {
	handle_eof $sock
        return
    }

    if {[info exists bytesNeeded($sock)] && $bytesNeeded($sock) > 0} {
	set lineRead [read $sock $bytesNeeded($sock)]
	set bytesRead [string length $lineRead]
	incr bytesNeeded($sock) -$bytesRead
	append incompleteLine($sock) $lineRead
	if {$bytesNeeded($sock) > 0} {
	    return
	}
	set line $incompleteLine($sock)
    } else {
        if {[gets $sock line] < 0} {
	    if {[eof $sock]} {
		handle_eof $sock
	    }
	    # if gets returns < 0 and not EOF, we're nonblocking and haven't
	    # gotten a complete line yet... keep waiting
	    return
        }
	if {"$line" == ""} {
	    serverlog "blank line from $sock"
	    return
	}
	# "#NNNN" means a multi-line request NNNN bytes long
	if {"[string index $line 0]" == "#"} {
	    set bytesNeeded($sock) [string trim [string range $line 1 end]]
	    set lineRead [read $sock $bytesNeeded($sock)]
	    set bytesRead [string length $lineRead]
	    incr bytesNeeded($sock) -$bytesRead
	    if {$bytesNeeded($sock) > 0} {
		set incompleteLine($sock) $lineRead
		return
	    }
	    set line $lineRead
	}
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
	set ec $::errorCode
	set ei $::errorInfo

	if {$ec == "ctable_quit"} {
	    serverlog "$table: $result (done)"
	    # We've already closed the socket, done
	    return
	}

	serverlog "$table: $result" \
		"In ($sock) $ctableUrl $line" $ei"

	variable hideErrorInfo
	if {$hideErrorInfo} {
	    # look at errorInfo if you want to know more, don't send it
	    # back to them -- it exposes stuff about us they don't care
	    # about
	    set ei ""
	}

	### puts stdout [list e $result $ei $ec]
	remote_send $sock [list e $result $ei $ec]
    } else {
	### puts stdout [list k $result]
	remote_send $sock [list k $result]
    }
}

#
# Send a response, and flush. If the response is multi-line or long enough
# to be potentially split, send as "# NNNN" followed by the NNNN-byte
# response.
#
proc remote_send {sock line {multi 1}} {
    if {$multi} {
	if {[string length $line] > 8192 || [string match "*\n*" $line]} {
	    puts $sock "# [expr [string length $line] + 1]"
	}
    }
    puts $sock $line
    flush $sock
}

#
# Send an "OK" empty response
#
proc remote_ok {sock} {
    puts $sock [list k ""]
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

    ### puts stderr "remote_invoke '$sock' '$table' '$line' '$port'"

    set remoteArgs [lassign $line command]

    ### puts "command '$command' ctable '$table' args '$remoteArgs'"

    switch $command {
	"shutdown" {
	    if {[string match "-no*" [lindex $remoteArgs 0]]} {
	        # Acknowledge immediately because the socket is going down hard
	        remote_ok $sock
		# No cleanup, we're killing everything
		serverdie "Shutting down immediately"
		# And just in case...
	        error "quit" "" ctable_quit
	    } else {
	        return [shutdown_servers]
	    }
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

	"quit" { # A more polite "eof" :)
	    # Acknowledge immediately because the socket is going down hard
	    remote_ok $sock
	    # Clean up
	    handle_eof $sock quit
	    # And this will keep it from trying to send another OK
	    error "quit" "" ctable_quit
	}

	"create" {
	    return [instantiate $table [lindex $remoteArgs 0]]
	}

	"info" {
	    return [serverInfo [string match "-v*" [lindex $remoteArgs 0]]]
	}

        "enable" {
	    return [enable_extension $sock $remoteArgs]
        }

	"methods" {
    	    variable serverCommands
	    set additional_result {}
	    foreach {evalRequired method _} $serverCommands {
		if {!$evalRequired || $evalEnabled} {
	            lappend additional_result $method
		}
	    }
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
	    append text "or a table command"
	    return $text
	}
    }

    if {![info exists registeredCtables($table)]} {
	error "table $table not registered on this server" "" CTABLE
    }

    set ctable $registeredCtables($table)

    if [info exists triggerCode($command:$table)] {
	set cmd $triggerCode($command:$table)
	lappend cmd $table $ctable $command
	switch [catch [concat $cmd $remoteArgs] result] {
	    1 { 
		error $result $::errorInfo
	    }
	    2 { return $result }
	}
    }

    set simpleCommand 1
    if [string match "search*" $command] {
	set index [lsearch -exact $remoteArgs "-countOnly"]
	if {$index == -1} {
	    set simpleCommand 0
	} else {
	    set remoteArgs [lreplace $remoteArgs $index [expr $index + 1]]
	}
    }

    if $simpleCommand {
	set cmd [linsert $remoteArgs 0 $ctable $command]
#serverlog "simple command '$cmd'"
	set result [eval $cmd]
	if [info exists additional_result] {
	    set result [concat $result $additional_result]
	}
	return $result
    }

    # else it's a complex search command.

    # Check if there's been a request for quoting
    if {[info exists quoteType($sock)] && "$quoteType($sock)" != ""} {
	lappend remoteArgs -quote $quoteType($sock)
    }

    # Set up the command to stream the results back
    set cmd [linsert $remoteArgs 0 $ctable $command -write_tabsep $sock]
    remote_send $sock "m"

    # pull the trigger
    set code [catch {eval $cmd} result]

    remote_send $sock "\\." 0

    # Return the end result
    return -code $code $result
}

#
# Enable extensions by setting the variable specified in the extensions
# array to the value specified in the command, or 1 if no value provided
# returns 1 if the extension exists, 0 otherwise
#
proc enable_extension {sock list} {
    variable extensions
    set name [lindex $list 0]
    if {[llength $list] > 1} {
        set value [lindex $list 1]
    } else {
	set value 1
    }
    if [info exists extensions($name)] {
	variable $extensions($name)
	set $extensions($name)($sock) $value
	return 1
    } else {
	return 0
    }
}

proc serverlog {args} {
    variable logfile
    if [llength $args] {
	set message "[clock format [clock seconds]] [pid]: [join $args "\n"]"
	if {[llength $args] > 1} {
	    set message "\n$message"
	}
	puts $logfile $message
    }
}

proc serverwait {{var ""}} {
    variable waitvar
    if {"$var" != ""} {
	uplevel 1 [list set $var 0]
	set waitvar $var
    } else {
	set waitvar ::ctable_server::Die
    }
    serverlog "Waiting on $waitvar"
    vwait $waitvar
}

proc serverdie {{message ""}} {
    if {"$message" != ""} {
	set message " - $message"
    }
    serverlog "Terminating server$message"
    variable waitvar
    if [info exists waitvar] {
	# Shutdown all the server sockets
	shutdown_servers 0
	# Close all the client sockets
	close_clients
	# And signal done
	serverlog "Signal termination on $waitvar"
	set $waitvar 1
    } else {
	exit 0
    }
}

}

package provide ctable_server 1.8.1

#get, set, array_get, array_get_with_nulls, exists, delete, count, foreach, sort, type, import, import_postgres_result, export, fields, fieldtype, needs_quoting, names, reset, destroy, statistics, write_tabsep, or read_tabsep

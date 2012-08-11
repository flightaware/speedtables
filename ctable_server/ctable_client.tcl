#
# Network CTables
#
# Client-Side
#
#
# $Id$
#

package require ctable_net
package require Tclx
package require ncgi

#
# remote_ctable - declare a ctable as going to a remote host
#
# remote_ctable $url myTable
#
#  myTable is now a command that works like a ctable except it's all
#  client server behind your back.
#
proc remote_ctable {cttpUrl localTableName args} {
    variable ctableUrls
    variable ctableLocalTableUrls
    variable ctableOptions

#puts stderr "define remote ctable: $localTableName -> $cttpUrl"

    set ctableUrls($localTableName) $cttpUrl
    set ctableLocalTableUrls($cttpUrl) $localTableName
    set ctableOptions($cttpUrl) $args

    proc $localTableName {args} "
	set level \[info level]; incr level -1
	remote_ctable_invoke $localTableName \$level \$args
    "
}

#
# remote_ctable_destroy - destroy a remote ctable connection
#
proc remote_ctable_destroy {cttpUrl} {
    variable ctableUrls
    variable ctableLocalTableUrls

    if [info exists ctableLocalTableUrls($cttpUrl)] {
	# puts [list rename $ctableLocalTableUrls($cttpUrl) ""]
	rename $ctableLocalTableUrls($cttpUrl) ""
	if [info exists ctableUrls($ctableLocalTableUrls($cttpUrl))] {
	    unset ctableUrls($ctableLocalTableUrls($cttpUrl))
	}
	unset ctableLocalTableUrls($cttpUrl)
    }
    # puts [list remote_ctable_cache_disconnect $cttpUrl]
    remote_ctable_cache_disconnect $cttpUrl
}

#
# remote_ctable_cache_disconnect - disconnect from a remote ctable server
#
proc remote_ctable_cache_disconnect {cttpUrl} {
    variable ctableSockets
    variable remoteMethods
    variable remoteQuote

    if {[info exists ctableSockets($cttpUrl)]} {
	set oldsock $ctableSockets($cttpUrl)
	unset ctableSockets($cttpUrl)
	catch {close $oldsock}
    }

    unset -nocomplain remoteMethods($cttpUrl)
    unset -nocomplain remoteQuote($cttpUrl)
}

#
# remote_ctable_connect - connect to a remote ctable server
#
proc remote_ctable_cache_connect {cttpUrl} {
    variable ctableSockets

    # If there's a valid open socket
    if {[info exists ctableSockets($cttpUrl)]} {
	set oldsock $ctableSockets($cttpUrl)
	if {![eof $oldsock]} {
            return $oldsock
	}
	unset ctableSockets($cttpUrl)
	catch {close $oldsock}
    }

    lassign [::ctable_net::split_ctable_url $cttpUrl] host port dir remoteTable stuff

    # Don't error out immediately if we can't open the socket
    if [catch {socket $host $port} sock] {
	after 500
	set sock [socket $host $port]
    }

    # Previous code retried this. I don't see any reason to, I think it was
    # trying to handle the "can't open socket" case.
    if {[gets $sock line] < 0} {
	close $sock
	error "unexpected EOF from server on connect"
    }

    if {[lindex $line 0] != "ctable_server" && [lindex $line 0] != "sttp_server"} {
	close $sock
	error "server hello line format error"
    }

    if {[lindex $line 1] != "1.0"} {
	close $sock
	error "server version [lindex $line 1] mismatch"
    }

    if {[lindex $line 2] != "ready"} {
	close $sock
	error "unable to handle server state of unreadiness"
    }

    set ctableSockets($cttpUrl) $sock
    return $sock
}

#
# remote_sock_send - send a command over a socket
#
# Multi-line commands are sent as a line containing "# NNNN" followed by
# NNNN bytes
#
proc remote_sock_send {sock cttpUrl command} {
    set line [list $cttpUrl $command]
    if [string match "*\n*" $line] {
	puts $sock [list # [expr [string length $line] + 1]]
    }
    puts $sock [list $cttpUrl $command]
    flush $sock
}

#
# read a possibly multi-line response from the server
#
proc get_response {sock lineVar} {
    upvar 1 $lineVar line
    while {[set length [gets $sock line]] == 0} { continue }
    if {$length > 0} {
        # Handle "# NNNN" - multi-line request NNNN bytes long
        if {"[string index $line 0]" == "#"} {
	    set length [string trim [string range $line 1 end]]
	    set line [read $sock $length]
	    if {"$line" == ""} {
		set length 0
	    }
        }
    }
    return $length
}

#
# remote_ctable_send - send a command to a remote ctable server
#
proc remote_ctable_send {cttpUrl command {actionData ""} {callerLevel ""} {no_redirect 0}} {
    variable ctableSockets
    variable ctableLocalTableUrls

    check_cttp_timeout $cttpUrl

#puts "actionData '$actionData'"

    set sock [remote_ctable_cache_connect $cttpUrl]

    # Try 5 times to send the data and get a response
    set i 0
    while 1 {
        if {[catch {remote_sock_send $sock $cttpUrl $command} err] != 1} {
	    if {[get_response $sock line] > 0} { break }
	    set err "Unexpected EOF from server on response"
	}
	incr i
	if {$i > 5} {
	    error "$cttpUrl: $err"
	}
        remote_ctable_cache_disconnect $cttpUrl
    
	set sock [remote_ctable_cache_connect $cttpUrl]
    }

    while 1 {
	switch [lindex $line 0] {
	    "e" {
		error [lindex $line 1] [lindex $line 2] [lindex $line 3]
	    }

	    "k" {
		return [lindex $line 1]
	    }

	    "r" {
		if $no_redirect {
		    if {"$command" == "redirect"} {
		        error "Redirected for redirect to [lindex $line 1]"
		    }
		    return ""
		}
# puts "[clock format [clock seconds]] redirect '$line'"
# parray ctableLocalTableUrls
		remote_ctable_cache_disconnect $cttpUrl
		set newCttpUrl [lindex $line 1]
		if {[info exists ctableLocalTableUrls($cttpUrl)]} {
		    set localTable $ctableLocalTableUrls($cttpUrl)
		    unset ctableLocalTableUrls($cttpUrl)
		    remote_ctable $newCttpUrl $localTable
		}
# puts "[clock format [clock seconds]] retry $newCttpUrl '$command'"
		return [remote_ctable_send $newCttpUrl $command $actionData $callerLevel]
	    }

	    "m" {
		array set actions $actionData
		set firstLine 1
	        set dequoting 0
		if [info exists actions(-quote)] {
		    if {"$actions(-quote)" == "uri"} {
			set dequoting 1
		    }
		}

		# This is used by "-into" and "-buffer" to read the response
		# into a local ctable and then IF a -code or -write_tabsep is
		# specified, perform that action.

		if [info exists actions(-into)] {
		    set localTable $actions(-into)
		    set localCommand [list $localTable read_tabsep $sock]
		    unset actions(-into)
		    foreach option {-nokeys -nocomplain} {
			if [info exists actions($option)] {
			    if {$actions($option)} {
			        lappend localCommand $option 
			    }
			    unset actions($option)
			}
		    }
		    if {$dequoting} {
			lappend localCommand -quote $actions(-quote)
		    }
		    lappend localCommand -with_field_names
		    lappend localCommand -term {\\.}
		    set status [catch $localCommand result]
		    if {$status} {
			return -code $status $result
		    }

		    # handle composite actions for buffering
		    if {[info exists actions(-code)] || [info exists actions(-write_tabsep)]} {
			if [info exists actions(action)] {
			    if [info exists actions(keyVar)] {
				set actions(-key) $actions(keyVar)
				unset actions(keyVar)
			    }
			    if [info exists actions(bodyVar)] {
				set actions($actions(action)) $actions(bodyVar)
				unset actions(bodyVar)
			    }
			    unset actions(action)
			}
			set localCommand [linsert [array get actions] 0 $localTable search]

		        #set status [catch $localCommand result]
			namespace eval ::ctable_client [
			    list set code $localCommand
			]
			uplevel #$callerLevel "
			    set ::ctable_client::status \[
				catch \$::ctable_client::code ::ctable_client::result
			    ]
			"
		        if {$::ctable_client::status} {
			    return -code $::ctable_client::status $::ctable_client::result
		        }
		    }

		    # get result from next response
		    if {[get_response $sock line] <= 0} {
			error "$cttpUrl: unexpected EOF from server after multiline response"
		    }
		    continue
		}

		set result ""
		while {[gets $sock line] >= 0} {
		    if {$line == "\\."} {
			break
		    }
#puts "processing line '$line'"

		    if {[info exists actions(-write_tabsep)]} {
			set status [catch {
			    puts $actions(-write_tabsep) $line
			} error]
			if {$status == 1} {
			    set savedInfo $::errorInfo
			    set savedCode $::errorCode
			    remote_ctable_cache_disconnect $cttpUrl
			    error $result $savedInfo $savedCode
			}
		    } elseif {[info exists actions(-code)]} {
			if {$firstLine} {
			    set firstLine 0
			    set fields $line
			    continue
			}

			set codeList {}
			set dataList ""
			foreach var $fields value [split $line "\t"] {
			    if {$dequoting} {
				set value [::ncgi::decode $value]
			    }
			    if {$var == "_key"} {
				if {[info exists actions(keyVar)]} {
				    lappend codeList [list set $actions(keyVar) $value]
				}
#
# TODO - make sure the behavior with -get is consistent
#
				if {$actions(action) != "-get" && [info exists actions(-noKeys)] && $actions(-noKeys) == 1} {
				    continue
				}
			    }

			    if {$actions(action) == "-get"} {
				lappend dataList $value
			    } else {
			        # it's -array_get, -array_get_with_nulls,
				# -array or -array_with_nulls
				lappend dataList $var $value
			    }
			}

			if [info exists actions(bodyVar)] {
			    if {$actions(action) == "-array" || $actions(action) == "-array_with_nulls"} {
			        lappend codeList [list array set $actions(bodyVar) $dataList]
			    } else {
			        lappend codeList [list set $actions(bodyVar) $dataList]
			    }
			}
			lappend codeList $actions(-code)

#puts "executing '$dataCmd'"
#puts "executing '$actions(-code)'"

			namespace eval ::ctable_client:: "
			    variable status {}
			    variable result {}
			    variable code [list [join $codeList "\n"]]
			"
			uplevel #$callerLevel "
			    set ::ctable_client::status \[
				catch \$::ctable_client::code ::ctable_client::result
			    ]
			"
			set status $::ctable_client::status
			set result $::ctable_client::result

			# TCL_ERROR
			if {$status == 1} {
			    set savedInfo $::errorInfo
			    set savedCode $::errorCode
			    remote_ctable_cache_disconnect $cttpUrl
			    error $result $savedInfo $savedCode
			}

 			# TCL_RETURN/TCL_BREAK
			if {$status == 2 || $status == 3} {
			    remote_ctable_cache_disconnect $cttpUrl
			    return $result
			}

			# TCL_OK or TCL_CONTINUE just keep going
		    } else {
			error "no action, need -write_tabsep or -code: $actionData"
		    }
		}
		if {[get_response $sock line] <= 0} {
		    error "$cttpUrl: unexpected EOF from server after multiline response"
		}
		# We don't return here, we take the response from get_response
		# and fall through to the next loop on "line".
	    }

	    default {
		error "unknown command response '$line'"
	    }
	}
    }
}

#
# remote_ctable_create - create on the specified host an instance of the ctable creator creatorName named tableName
#
proc remote_ctable_create {cttpUrl creatorName remoteTableName} {
    return [remote_ctable_send $cttpUrl [list create $creatorName $remoteTableName]]
}

#
# remote_ctable_invoke - object handler for procs generated by remote_ctable
#
proc remote_ctable_invoke {localTableName level command} {
    variable ctableSockets
    variable ctableUrls
    variable ctableLocalTableUrls

    set cttpUrl $ctableUrls($localTableName)

    set cmd [lindex $command 0]
    set body [lrange $command 1 end]

#puts "cmd '$command', pairs '$body'"

    # Have to handle "destroy" specially - don't pass to far end, just
    # close the socket and destroy myself
    if {"$cmd" == "destroy"} {
#puts "command is destroy"
	return [remote_ctable_destroy $cttpUrl]
    }

    # If the comand is "redirect" or "shutdown", don't follow redirects
    set no_redirect [expr {"$cmd" == "redirect" || "$cmd" == "shutdown"}]

    # if it's search, take out args that will freak out the remote side
    if {$cmd == "search" || $cmd == "search+"} {
	array set pairs $body
	if {[info exists pairs(-write_tabsep)]} {
	    set actions(-write_tabsep) $pairs(-write_tabsep)
	    unset pairs(-write_tabsep)
	}

	if {[info exists pairs(-noKeys)]} {
	    set actions(-noKeys) $pairs(-noKeys)
	}

	if {[info exists pairs(-into)]} {
	    set localTable [
		uplevel #$level [list namespace which $pairs(-into)]
	    ]

	    unset pairs(-into)
	    set actions(-into) $localTable

	    set pairs(-with_field_names) 1
	}

	if {[info exists pairs(-buffer)]} {
	    if {"$pairs(-buffer)" == "#auto"} {
		set localTable [maketable $cttpUrl $sock]
	    } else {
	        set localTable [
		    uplevel #$level [list namespace which $pairs(-buffer)]
	        ]
	    }

	    unset pairs(-buffer)
	    set actions(-into) $localTable

	    $localTable reset

	    set pairs(-with_field_names) 1
	}

	if {[info exists pairs(-code)]} {
	    set actions(-code) $pairs(-code)
	    unset pairs(-code)

	    foreach var {-key -array_get -array_get_with_nulls -array -array_with_nulls -get} {
		if {[info exists pairs($var)]} {
		    set actions(action) $var
		    set actions($var) $pairs($var)
		    unset pairs($var)

		    if {$var == "-key"} {
			set actions(keyVar) $actions($var)
		    } else {
			set actions(bodyVar) $actions($var)
		    }
		}
	    }

	    set pairs(-with_field_names) 1
	}

	if {![info exists actions(-into)] && ![info exists actions(-code)] && ![info exists actions(-write_tabsep)]} {
	    set pairs(-countOnly) 1
	} elseif {[remote_quote $cttpUrl uri]} {
	    set actions(-quote) uri
	    set pairs(-quote) uri
	}

	set body [array get pairs]
#puts "new body is '$body'"
#puts "new actions is [array get actions]"
    }

    return [remote_ctable_send $cttpUrl [linsert $body 0 $cmd] [array get actions] $level $no_redirect]
}

#
# local enable for remote options we want to use
#
proc remote_enable {args} {
    variable remoteEnable

    foreach option $args {
        set remoteEnable($option) 1
    }
}

#
# see if remote socket supports quoting, and if so set it
#
proc remote_quote {cttpUrl quoteType} {
    variable remoteMethods
    variable remoteQuote
    variable remoteEnable

    if {![info exists remoteEnable(quote)] || !$remoteEnable(quote)} {
	return 0
    }

    if {![info exists remoteMethods($cttpUrl)]} {
	set remoteMethods($cttpUrl) [remote_ctable_send $cttpUrl methods]
    }

    if {![string match "*enable*" $remoteMethods($cttpUrl)]} {
	return 0
    }

    if {![info exists remoteQuote($cttpUrl)]} {
	set remoteQuote($cttpUrl) ""
    }

    if {"$remoteQuote($cttpUrl)" == "none"} {
	return 0
    }

    if {"$remoteQuote($cttpUrl)" == "$quoteType"} {
	return 1
    }

    if {[remote_ctable_send $cttpUrl [list enable quote $quoteType]]} {
	return 1
    }

    set remoteQuote($cttpUrl) "none"
    return 0
}

#
# Check for timeouts for socket connections in ctable.
#
proc check_cttp_timeout {cttpUrl} {
    variable ctableOptions
    if ![info exists ctableOptions($cttpUrl)] { return }

    array set options $ctableOptions($cttpUrl)
    if {![info exists options(-timeout)]} { return }
    if {$options(-timeout) == 0} { return }

    variable ctableTimeout
    if [info exists ctableTimeout($cttpUrl)] {
	catch {after cancel $ctableTimeout($cttpUrl)}
	unset ctableTimeout($cttpUrl)
    }
    set ctableTimeout($cttpUrl) [
	after $options(-timeout) [list handle_cttp_timeout $cttpUrl]
    ]
}

#
# Handle timeouts for socket connections
#
proc handle_cttp_timeout {cttpUrl} {
    variable ctableTimeout
    unset -nocomplain ctableTimeout($cttpUrl)
    remote_ctable_cache_disconnect $cttpUrl
}

proc maketable {cttpUrl sock} {
  variable lastsocket
  package require sttp_buffer

  if [info exists lastsocket($cttpUrl)] {
    if {"$lastsocket($cttpurl)" != "$sock"} {
      ::sttp_buffer::forget $cttpUrl
    }
  }
  set lastsocket($cttpUrl) $sock

  return [::sttp_buffer::table $cttpUrl]
}

package provide ctable_client 1.8.2


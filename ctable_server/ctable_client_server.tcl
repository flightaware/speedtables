#
# Network CTables
#
# Common code between CTable clients and CTable servers.
#
# $Id$
#

namespace eval ::ctable_net {
    # default port (rarely used)
    variable ctableDefaultPort 11111

    # default protocol for new URLs
    variable ctableDefaultProtocol ctable

proc split_ctable_url {cttpUrl} {
    variable ctableDefaultPort

    # crack out host:port from the rest
    if {![regexp -nocase {^(ctable|sttp)://(.*?)/(.*)$} $cttpUrl dummy proto hostPort theRest]} {
	error "invalid URL syntax, should be proto://host?:port?/?dir/?table??stuff?"
    }

    # crack host:port into host and port and if port is empty set it to 
    # the default
    if {![regexp {^(.*):(.*)$} $hostPort dummy host port]} {
	set host $hostPort
	set port $ctableDefaultPort
    }

    # crack the rest into the rest and options
    if {![regexp {^(.*)\?(.*)$} $theRest dummy theRest options]} {
	set options ""
    }

    # crack what's left of the rest into dir and tableName
    if {![regexp {^(.*)/(.*)$} $theRest dummy dir tableName]} {
	set dir ""
	set tableName $theRest
    }

    return [list $host $port $dir $tableName $options]
}


proc join_ctable_url {host port dir table {extraStuff ""}} {
    variable ctableDefaultProtocol

    set result "$ctableDefaultProtocol://$host"

    if {$port != ""} {
	append result ":$port"
    }

    if {$dir != ""} {
	append result "/$dir"
    }

    append result "/$table"

    if {$extraStuff != ""} {
	append result "?$extraStuff"
    }

    return $result
}

if 0 {
package require Tclx

proc test {url} {
    puts "testing $url"
    lassign [split_ctable_url $url] host port dir table options
    puts "host '$host' port '$port' dir '$dir' table '$table' options '$options'"
    puts "rejoined: [join_ctable_url $host $port $dir $table $options]"
    puts ""
}

test ctable://foo.com/bar

test ctable://foo.com:2345/bar

test ctable://foo.com/bar/snap

test ctable://foo.com:1234/bar/snap

test ctable://foo.com/bar?moreExtraStuff=sure

test ctable://foo.com/bar/snap?moreExtraStuff=sure

test ctable://foo.com:1234/bar/snap?moreExtraStuff=sure

test ctable://foo.stinky.com:23456/pixar/toystory2/stinky_pete_vertices?hijinks
}

namespace export split_ctable_url join_ctable_url


}

package provide ctable_net 1.8.2

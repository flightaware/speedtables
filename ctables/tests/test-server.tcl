#
# demo server
#
#

source dumb-data.tcl

package require ctable_server

::ctable_server::register t

proc doit {} {
    ::ctable_server::setup

puts "running, waiting for connections"
vwait die
}

if !$tcl_interactive doit


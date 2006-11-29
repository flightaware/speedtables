#
# demo server
#
#

source dumb-data.tcl

package require ctable_server

#::ctable_server::register ctable://127.0.0.1:11112/testTable t
::ctable_server::register ctable://127.0.0.1/testTable t

proc doit {} {
    ::ctable_server::setup

puts "running, waiting for connections"
vwait die
}

if !$tcl_interactive doit


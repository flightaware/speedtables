#
# demo server with a redirect
#
#

source dumb-data.tcl

package require ctable_server

::ctable_server::register_redirect ctable://127.0.0.1:11112/testTable ctable://127.0.0.1/testTable

proc doit {} {
    ::ctable_server::setup 11112

puts "running, waiting for connections"
vwait die
}

if !$tcl_interactive doit


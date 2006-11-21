

source demo2.ct
package require Cable

source server.tcl

::ctable_server::register_instantiator cable_info

proc doit {} {
    ::ctable_server::setup

    vwait die
}

if !$tcl_interactive doit




# $Id$

package require ctable_client
package require st_client

namespace eval ::stapi {
  # shared://port/[dir/]table[/stuff][?stuff]
  # options:
  #   -build dir
  #      Specify path to ctable build directory
  #
  variable shared_serial 0
  variable shared_build_dir ""

  proc connect_shared {table_path {address ""} args} {
    variable shared_serial
    variable shared_build_dir

    if {[info exists shared_build_dir] && "$shared_build_dir" != ""} {
      set opts(-build) $shared_build_dir
    }

    array set opts $args

    if {"$address" == ""} {
      set host localhost
      set port ""
    } elseif {![regexp {^(.*):(.*)$} $address _ host port]} {
      set host localhost
      set port $address
    }

    if {"$host" != "localhost" && "$host" != "127.0.0.1"} {
      return -code error "Can not make a shared connection to a remote server"
    }

    if {"$port" == ""} {
      set address $host
    } else {
      set address $host:$port
    }

    set uri ctable://$address/$table_path

    set ns ::stapi::shared[incr shared_serial]

    # insert handler proc (below) into namespace, and create the namespace
    namespace eval $ns [list proc handler {args} [info body shared_handler]]

    remote_ctable $uri ${ns}::master
    set handle [${ns}::master attach [pid]]
    array set prop [${ns}::master getprop]

    if {[info exist opts(-build)]} {
      if {[lsearch $::auto_path $opts(-build)] == -1} {
	lappend ::auto_path $opts(-build)
      }
    }

    namespace eval :: [list package require [string totitle $prop(extension)]]
    $prop(type) create ${ns}::reader reader $handle

    # Everything's been successfully completed, remember that in the created
    # namespace.
    set ${ns}::handle $handle
    set ${ns}::table $prop(type)
    return ${ns}::handler
  }
  register shared connect_shared

  # Simple handler, most commands are passed straight to the master.
  #
  # Note cheesy object model!
  #
  # This executes in the stapi::sharedN namespace created in connect_shared,
  # never in this namespace, so references to "reader" and "master" are
  # the two stapi objects created there.
  proc shared_handler {args} {
    set method [lindex $args 0]
    switch -glob -- [lindex $args 0] {
      search* {
	uplevel 1 [namespace which reader] $args
      }
      destroy {
	master destroy
	reader destroy
      }
      # Insert "detach" case here TODO
      default {
	uplevel 1 [namespace which master] $args
      }
    }
  }
}

package provide st_shared 1.8.2


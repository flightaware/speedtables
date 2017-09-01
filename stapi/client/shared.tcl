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
    set ${ns}::attached 1
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
    variable attached
    switch -glob -- [lindex $args 0] {
      search* {
	#puts "\nrunning shared_handler search, '[namespace which reader] $args'"
	catch {uplevel 1 [namespace which reader] $args} catchResult catchOptions

	#puts "shared_handler search ran, args '$args' result '$catchResult', options $catchOptions\n"
	dict incr catchOptions -level 1
	return -options $catchOptions $catchResult
      }
      destroy {
	if {$attached} {
	  master destroy
	}
	reader destroy
      }
      detach {
	if {$attached} {
	  master destroy
	  set attached 0
	}
      }
      default {
	if {$attached} {
	  #puts "\nrunning shared_handler default case, args '$args'"
	  catch {uplevel 1 [namespace which master] $args} catchResult catchOptions
	  #puts "shared_handler default case ran, args '$args' result '$catchResult', options $catchOptions\n"
	  dict incr catchOptions -level 1
	  return -options $catchOptions $catchResult
	} else {
	  return -code error "Detached shared table can only 'search' and 'destroy'"
	}
      }
    }
  }
}

package provide st_shared 1.13.4

# vim: set ts=8 sw=4 sts=4 noet :

# $Id$

package require ctable_client

namespace eval ::stapi {
  variable transport_handlers

  proc register {transport handler} {
    variable transport_handlers
    set handler [uplevel 1 [list namespace which $handler]]
    set transport_handlers($transport) $handler
  }

  proc connect {uri args} {
    variable transport_handlers
    array set opts $args

    # If "-keys" defined, save them to create a wrapper
    if {[info exists opts(-keys)] || [info exists opts(-key)]} {

      # Check here so if this errors out we haven't done the heavy lifting
      if {![namespace exists ::stapi::extend]} {
	uplevel #0 "package require stapi_extend"
      }

      # Save "-keys" option but don't pass it on downstream
      if {[info exists opts(-keys)]} {
        set keys $opts(-keys)
        unset opts(-keys)
        set keyargs {}

        if {[info exists opts(-keysep)]} {
          lappend keyargs -keysep $opts(-keysep)
          unset opts(-keysep)
        }
      } else {
        set keys [list $opts(-key)]
        set keyargs {}
        unset opts(-key)
      }
      set args [array get opts]
    }

    if {![regexp {^([^:]+)://([^/]*)/*(.*)} $uri _ method address path]} {
      set handle $uri
    } else {
      if {![info exists transport_handlers($method)]} {
	return -code error "No transport registered for method $method"
      }
      set handle [eval [list $transport_handlers($method) $path $address] $args]
    }

    if {[info exists keys]} {
      if {![::stapi::extend::extended $handle $keys]} {
        set handle [eval [list ::stapi::extend::connect $handle $keys] $args $keyargs]
      }
    }
    return $handle
  }

  # sttp://[host:port]/[dir/]table[/stuff][?stuff]
  # ctable://[host:port]/[dir/]table[/stuff][?stuff]
  variable ctable_serial 0
  proc connect_ctable {table_path {address "localhost"} args} {
    variable ctable_serial
    set uri ctable://$address/$table_path
    set local_table ::stapi::ctable[incr ctable_serial]
    remote_ctable $uri $local_table
    return $local_table
  }
  register ctable connect_ctable
  register sttp connect_ctable

  # local:///ctable_name - dummy connector for local tables
  proc connect_local {table {address ""} args} {
    if {"$address" != "*" && "$address" != ""} {
      return -code error "Local connection can not be made to remote host"
    }
    return [uplevel 2 [list namespace which $table]]
  }
  register local connect_local

  # package:///package_name/table[/path]
  proc connect_package {path {address ""} args} {
    if {[regexp {^/*([^/]+)(/.*)} $path _ table path]} {
      if {[file isdirectory $path/$table]} {
        set path $path/$table
      }

      if {[lsearch -exact $::auto_path $path] == -1} {
        lappend auto_path $path
      }
    } else {
      set table $path
    }
    set package [string totitle $table 0 0]
    uplevel 0 [list package require $package]
    return [$table #auto]
  }
  register package connect_package
}

package provide st_client 1.12.2

# vim: set ts=8 sw=4 sts=4 noet :

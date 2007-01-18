# $Id$

package require ctable_client

namespace eval ::scache {
  variable transport_handlers

  proc register {transport handler} {
    variable transport_handlers
    set handler [uplevel 1 [list namespace which $handler]]
    set transport_handlers($transport) $handler
  }

  proc connect {uri args} {
    variable transport_handlers
    if [regexp {^([^:]+)://([^/]+)/(.*)} $uri _ method address path] {
      if ![info exists transport_handlers($method)] {
	return -code error "No transport registered for method $method"
      }
      return [$transport_handlers($method) $path $address $args]
    }
    if ![info exists transport_handlers(*)] {
      return -code error "No default transport method registered"
    }
    return [$transport_handlers(*) $uri "-" $args]
  }

  # ctable://[host:port]/[dir/]table[/stuff][?stuff]
  variable ctable_serial 0
  proc connect_ctable {table_path {address "localhost"} args} {
    variable ctable_serial
    set uri ctable://$address/$table_path
    set local_table ::scache::ctable[incr ctable_serial]
    remote_ctable $uri $local_table
    return $local_table
  }
  register ctable connect_ctable

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
    if [regexp {^/*([^/]+)(/.*)} $path _ table path] {
      if [file isdirectory $path/$table] {
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

package provide scache_client 1.0


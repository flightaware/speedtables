# $Id$

package provide scache_client 1.0

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
  proc connect_ctable {table {address "localhost"} args} {
    variable ctable_serial
    set uri ctable://$address/$table
    set local_table ::scache::ctable[incr ctable_serial]
    remote_ctable $uri $local_table
    return $local_table
  }
  register ctable connect_ctable

  # sql://[user[:password]]@[host:]database/table[/cols][?selector]
  proc connect_sql {table {address "-"} args} {
    return -code error "SQL connector not implemented"
  }
  register sql connect_sql

  # local:///ctable_name - dummy connector for local tables
  proc connect_local {table {address "-"} args} {
    if {"$address" != "*" && "$address" != ""} {
      return -code error "Local connection can not be made to remote host"
    }
    return [uplevel 2 [list namespace which $table]]
  }
  register local connect_local
}


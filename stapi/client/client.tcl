# $Id$

package provide scache_client 1.0

namespace eval ::scache {
  proc connect {uri args} {
    if [regexp {^([^:]+)://([^/]+)/(.*)} $uri _ method address path] {
      return [connect_$method $path $address $args]
    }
    return connect_ctable $uri "-" $args
  }

  # Temporary back-glue to use the existing CA server registry stuff.
  variable registry_open 0
  proc open_registry {} {
    variable registry_open
    if $registry_open { return }
    uplevel #0 { package require sc_ca_cache }
    set registry_open 1
  }

  proc find_registered_ctable {table _uri {hosts ""}} {
    upvar 1 $_uri uri
    open_registry
    return [::sc_ca_cache::find_registered_ctable $table uri $hosts]
  }
  # end of glue

  # ctable://[host:port]/[dir/]table[/stuff][?stuff]
  variable ctable_serial 0
  proc connect_ctable {table {address "-"} args} {
    variable ctable_serial
    if {[llength $args] == 1} { set args [lindex $args 0] }
    set opts(-hosts) {}
    array set opts $args
    if {"$address" == "" || "$address" == "-"} {
      if ![find_registered_ctable $table_name uri $opts(-hosts)] {
	return -code error "Can't find registered ctable $table"
      }
    } else {
      set uri ctable://$address
    }
    set local_table ::scache::ctable[incr ctable_serial]
    remote_ctable $uri $local_table
    return $local_table
  }

  # sql://[user[:password]]@[host:]database/table[/cols][?selector]
  proc connect_sql {table {address "-"} args} {
    return -code error "SQL connector not implemented"
  }

  # local:///ctable_name - dummy connector for local tables
  proc connect_local {table {address "-"} args} {
    if {"$address" != "*" && "$address" != ""} {
      return -code error "Local connection can not be made to remote host"
    }
    return [uplevel 2 [list namespace which $table]]
  }
}


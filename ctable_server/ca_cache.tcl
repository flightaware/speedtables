#
# $Id$
#

package require ctable
package require sc_ca_ctables
package require sc_ca

::sc_ca::init -standalone

variable ca_cache_init 0
proc init_ca_cache {} {
  variable ca_cache_init
  if $ca_cache_init { return }
  ::ctable_server::register_instantiator ca_cache
}

proc init_sc_customer_merged {} {
  server_cached_ctable sc_customer_merged {mac_address i_account_number}
}

variable ca_cache_state
proc server_cached_ctable {table keycols} {
  variable ca_cache_state
  init_ca_cache
  ::sc_ca::setup_table_cache $table $keycols ct_$table
  set ctable [::sc_ca::open_cached_ctable ct_$table]
  rename $ctable $table
  ::ctable_server::register ca_cache $table
  set ca_cache_state($table) 1
}

proc ca_cache {command name} {
  variable ca_cache_state
  if {"$command" != "create"} {
    error "Unknown command $command"
  }
  if ![info exists ca_cache_state($name)] {
    error "Unknown cache $name"
  }
  return $name
}

package provide ::ctable_server_cache 1.0


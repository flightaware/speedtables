# $Id$

package require scache_client

namespace eval ::scache {
  proc connect_sql {table {address "-"} args} {
    return -code error "SQL transport method not implemented"
  }
  register sql connect_sql
}

package provide scache_sql_client 1.0

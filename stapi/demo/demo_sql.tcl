# $Id$

package require sttp_client_postgres

namespace eval ::demo {
    set demo_ctable(sql) sql:///sttp_demo?_key=isbn
    set rowfunctions "Edit Delete"
    set functions "Search Add List"
}

package provide sttp_demo_sql 1.0

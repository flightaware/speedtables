# $Id$

package require st_client_pgtcl

namespace eval ::demo {
    set demo_ctable(sql) sql:///sttp_demo?_key=isbn
    set rowfunctions "Edit Delete"
    set functions "Search Add List"
}

package provide stapi_demo_sql 1.0

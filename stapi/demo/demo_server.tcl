# $Id$

namespace eval ::demo {
    set demo_ctable(server) sttp://localhost:6666/demo
    set rowfunctions "Edit Delete"
    set functions "Search Add List"
}

package provide stapi_demo_server 1.0

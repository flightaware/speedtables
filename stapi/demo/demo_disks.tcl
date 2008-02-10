# $Id$

package require BSD
package require st_client

namespace eval ::demo {
    set uri sttp://localhost:6668/disks

    set rowfunctions ""
    set functions "List Search"
}

package provide stapi_demo_disks 1.0


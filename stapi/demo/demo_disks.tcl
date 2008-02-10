# $Id$

package require BSD
package require sttp_client

namespace eval ::demo {
    set uri ctable://localhost:6668/disks

    set rowfunctions ""
    set functions "List Search"
}

package provide sttp_demo_disks 1.0


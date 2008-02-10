# $Id$

package require BSD
package require ctable
package require fsstat_ctable

namespace eval ::demo {
    c_fsstat create ::demo::fsstat

    foreach row [::bsd::getfsstat] {
	fsstat store $row
    }

    set rowfunctions ""
    set functions "List Search"
}

package provide stapi_demo_bsd 1.0

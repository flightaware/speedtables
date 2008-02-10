# $Id$

package require ctable
package require demo_ctable

namespace eval ::demo {
    c_demo_ctable create ::demo::demo_ctable

    demo_ctable store isbn 0-13-110933-2 title "C: A Reference Manual" author "Harbison and Steele"
    demo_ctable store isbn 0-201-06196-1 title "The Design and Implementation of 4.3BSD" author "Leffler, McKusick, Karels, and Quarterman"
    demo_ctable store isbn 1-56592-124-0 title "Building Internet Firewalls" author "Chapman and Zwicky"

    set rowfunctions ""
    set functions "List Search"

    set demo_ctable(simple) ::demo::demo_ctable
}

package provide stapi_demo_simple 1.0

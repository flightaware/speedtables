# $Id$
namespace eval ::ctable set srcDir $dir

# We'll start out making gentable_stub just package require ctable, then
# switch when all else is kosher. Since the ::ctable namespace isn't
# accessed directly we don't need to worry about namespaces
package ifneeded ctable 1.6 [list source [file join $dir gentable.tcl]]
package ifneeded speedtable 1.6 [list source [file join $dir gentable.tcl]]


#!/bin/sh
# the next line restarts using tclsh -*- tcl -*- \
exec /usr/local/bin/tclsh8.4 "$0" "$@"

# $Id$

lappend auto_path /usr/local/lib/rivet/packages-local

package require ctable_server
package require stapi_demo_simple

::ctable_server::register ctable://*:6666/demo ::demo::demo_ctable

vwait Die

~


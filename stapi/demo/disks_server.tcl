#!/bin/sh
# the next line restarts using tclsh -*- tcl -*- \
exec /usr/local/bin/tclsh8.4 "$0" "$@"

# $Id$

lappend auto_path /usr/local/lib/rivet/packages-local

package require ctable
package require ctable_server

# Load the ctable package for the disks ctable
package require disks_ctable

::c_disks create ::disks

::ctable_server::register ctable://*:6668/disks ::disks

vwait Die

~


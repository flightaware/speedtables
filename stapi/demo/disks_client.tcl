#!/bin/sh
# the next line restarts using tclsh -*- tcl -*- \
exec /usr/local/bin/tclsh8.4 "$0" "$@"

# $Id$

lappend auto_path /usr/local/lib/rivet/packages-local

package require BSD
package require ctable
package require disks_lib
package require st_client

load_disks [::sttp::connect sttp://localhost:6668/disks -key disk]

package provide disks_client 1.0


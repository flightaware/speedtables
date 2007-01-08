#
# $Id$

namespace eval ::scache {
  variable debugging 1
  variable debug_timestamp_format "%Y-%m-%d %H:%M:%S %Z"

  proc debug {args} {
    variable debugging
    variable debug_timestamp_format

    if !$debugging return
    if ![llength $args] {
      if {$debugging < 2} return
      lappend args [info level -1]
    }
    set args [split [join $args "\n"] "\n"]
    set m ""
    if {[llength $args] > 1} { append m "\n" }
    set timestamp [clock format [clock seconds] -format $debug_timestamp_format]
    append m "$timestamp [pid] [join $args "\n\t"]"
    puts stderr $m
  }
}

package provide scache_debug 1.0

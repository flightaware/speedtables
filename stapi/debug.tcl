#
# stapi - speedtables api - debugging
#

namespace eval ::stapi {
  variable debugging 0
  variable debug_timestamp_format "%Y-%m-%d %H:%M:%S %Z"
  variable debug_handler

  #
  # debug - log debugging messages if ::stapi::debugging is nonzero
  #
  # if ::stapi::debug_handler is defined, it is invoked with the arguments
  # to debug as its arguments
  #
  # otherwise log to stderr
  #
  proc debug {args} {
    variable debugging
    variable debug_timestamp_format
    variable debug_handler

    if {!$debugging} {
        return
    }

    if {![llength $args]} {
      if {$debugging < 2} {
          return
	}
      lappend args [info level -1]
    }

    if {[info exists debug_handler]} {
      return [eval $debug_handler $args]
    }

    set args [split [join $args "\n"] "\n"]
    set m ""

    if {[llength $args] > 1} {
        append m "\n"
    }

    set timestamp [clock format [clock seconds] -format $debug_timestamp_format]
    append m "$timestamp [pid] [join $args "\n\t"]"
    puts stderr $m
  }

  proc debug_handler {proc} {
    variable debug_handler

    set debug_handler [uplevel 1 [list namespace which $proc]]
  }
}

package provide st_debug 1.8.2

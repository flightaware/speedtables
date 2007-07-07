#
#
# Copyright (C) 2005-2006 by Superconnect, Ltd.  All Rights Reserved
#
#
# $Id$
#

package require sttp
package require sttp_optimizer

namespace eval ::sttpx {
  variable stapi_cmds
  array set stapi_cmds {
    indexed indexed
    types   types
    destroy destroy
    ctable  ctable
    makekey makekey
    fetch   fetch
    store   store
    clear   clear
    search  search
    perform _perform
  }

  proc indexed {handle} {
    variable indexed
    if ![info exists indexed($handle)] {
      variable ctable
      if ![info exists ctable($handle)] {
        error "No ctable open for $handle"
      }
      set indexed($handle) [$ctable($handle) index indexed]
    }
    return $indexed($handle)
  }

  proc types {handle} {
    variable types
    if ![info exists types($handle)] {
      variable ctable
      if ![info exists ctable($handle)] {
        error "No ctable open for $handle"
      }
      set types($handle) {}
      foreach f [$ctable($handle) fields] {
	lappend types($handle) $f [$ctable($handle) fieldtype $f]
      }
    }
    return $types($handle)
  }

  variable seq -1
  proc connect {handle keys args} {
    variable keyfields
    variable separator
    variable ctable
    variable seq
    variable stable

    # If we're given an already-open table, return it
    if [extended $handle] {
      return $handle
    }
    if [info exists stable($handle)] {
      return $stable($handle)
    }
    set keysep ":"
    array set opts $args
    if [info exists opts(-keysep)] {
      set keysep $opts(-keysep)
      unset opts(-keysep)
      set args [array get opts]
    }

    # debug "[list ::sttp::connect $handle] $args"
    # If URI format, connect, otherwise assume it's already an open ctable
    if [string match "*://*" $handle] {
      set ctable($handle) [eval [list ::sttp::connect $handle] $args]
    } else {
      set ctable($handle) [uplevel 1 [list namespace which $handle]]
    }
    set keyfields($handle) $keys
    set separator($handle) $keysep

    incr seq
    set stable($handle) ::sttpx::_table$seq
    proc $stable($handle) {cmd args} "
	uplevel 1 \[concat \[stapi \$cmd $handle] \$args]
    "
    return $stable($handle)
  }

  # Check if the handle supports minimal sttp extensions:
  # * If it's wrapped, yes, otherwise...
  #   * Handles "method" method.
  #   * Handles "key" command.
  #   * Handles "makekey" command.
  #   * Handles "perform" command.
  #   * If keys required, [$handle keys] matches
  proc extended {handle {keys {}}} {
    if {[string match ::sttpx::_table* $handle]} { return 1 }
    if {[catch {set mlist [$handle methods]}]} { return 0 }
    if {[lsearch $mlist keys] == -1} { return 0 }
    if {[lsearch $mlist makekey] == -1} { return 0 }
    if {[lsearch $mlist perform] == -1} { return 0 }
    if {![llength $keys]} { return 1 }
    if {"$keys" == "[$handle keys]"} { return 1 }
    return 0
  }
  namespace export extended

  proc keys {handle} {
    variable keyfields
    if ![info exists keyfields($handle)] {
      error "No connection for $handle"
    }
    return $keyfields($handle)
  }
  namespace export keys

  proc stapi {cmd handle} {
    variable stapi_cmds
    variable ctable
    if ![info exists ctable($handle)] {
      return -code error "No ctable open for $handle"
    }

    set list {}
    if [info exists stapi_cmds($cmd)] {
      lappend list ::sttpx::$stapi_cmds($cmd) $handle
    } else {
      lappend list $ctable($handle) $cmd
    }
    return $list
  }

  proc destroy {handle} {
    variable ctable
    variable keyfields
    variable indexed
    variable types
    variable stable

    if ![info exists ctable($handle)] {
      error "No ctable open for $handle"
    }

    $ctable($handle) destroy
    rename $stable($handle) ""

    unset ctable($handle)
    unset stable($handle)
    unset keyfields($handle)
    unset -nocomplain indexed($handle)
    unset -nocomplain types($handle)
  }

  proc ctable {handle} {
    variable keyfields
    variable ctable

    if ![info exists ctable($handle)] {
      return -code error "No ctable open for $handle"
    }
    return $ctable($handle)
  }

  proc connected {handle} {
    variable keyfields
    return [expr {[info exists keyfields($handle)] || [extended $handle]}]
  }
  namespace export connected

  proc makekey {handle _k} {
    variable keyfields
    if ![info exists keyfields($handle)] {
      error "No connection for $handle"
    }
    upvar 1 $_k k
    set key {}
    foreach n $keyfields($handle) {
      lappend key $k($n)
    }
    if {[llength $key] == 1} {
      return [lindex $key 0]
    } elseif {"$separator($handle)" == "list"} {
      return $key
    } else {
      return [join $key $separator($handle)]
    }
  }

  proc fetch {handle key _a} {
    variable keyfields
    variable ctable
    if ![info exists keyfields($handle)] {
      error "No connection for $handle"
    }
    upvar 1 $_a a
    if [regexp {^@(.*)} $key _ _k] {
      upvar $_k k
      set key [makekey $handle k]
    } elseif {![string match "*:*" $key]} {
      set key [join $key :]
    }
    if ![$ctable($handle) exists $key] {
      return 0
    }
    set list [$ctable($handle) array_get_with_nulls $key]
    array set a $list
    return 1
  }

  proc store {handle _a} {
    variable keyfields
    variable ctable
    if ![info exists keyfields($handle)] {
      error "No connection for $handle"
    }
    upvar 1 $_a a
    $ctable($handle) set [makekey $handle a] [array get a]
  }

  proc clear {handle key} {
    variable ctable
    variable keyfields
    if ![info exists keyfields($handle)] {
      error "No connection for $handle"
    }
    if [regexp {^@(.*)} $key _ _k] {
      upvar $_k k
      set key [makekey $handle a]
    } elseif {![string match "*:*" $key]} {
      set key [join $key :]
    }
    $ctable($handle) delete $key
  }

  proc debug {args} {
    eval ::sttp::debug $args
  }

  proc search {handle args} {
    variable ctable
    if ![info exists ctable($handle)] {
      error "No ctable open for $handle"
    }
    lappend cmd $ctable($handle)
    array set options $args

    set debug 0
    if [info exists options(-debug)] {
      set debug $options(-debug)
      unset options(-debug)
    }
    if $debug {
      debug [info level 0]
    }

    if ![info exists options(-code)] {
      foreach opt {
	-key -array -array_with_nulls -array_get -array_get_with_nulls
      } {
	if [info exists options($opt)] {
	  set options(-limit) 1
	  set options(-code) break
	}
      }
    }

    if [info exists options(-compare)] {
      set new_compare {}
      foreach list $options(-compare) {
	set op [lindex $list 0]
	if {"$op" == "<>"} {
	  set list [concat {!=} [lrange $list 1 end]]
	} elseif {[regexp {^(-?)(.)match} $op _ not ch]} {
	  set op [lindex {match notmatch} [string length $not]]
	  unset -nocomplain fn
	  switch -exact -- [string tolower $ch] {
	    u { append op _case; set fn toupper }
	    l { append op _case; set fn tolower }
	    x { append op _case }
          }
	  set pat [lindex $list 2]
	  if [info exists fn] {
	    set pat [string $fn $pat]
	  }
	  set list [concat $op [lindex $list 1] [list $pat]]
	}
	lappend new_compare $list
      }
      set options(-compare) $new_compare
    }

    set search search
    if {"[set i [indexed $handle]]" != ""} {
      if [::sttp::optimize_array options $i [types $handle]] {
	set search search+
      }
    }
    lappend cmd $search

    foreach {n v} [array get options] {
      lappend cmd $n $v
    }

    if $debug {
      debug [list uplevel 1 $cmd]
    }
    return [uplevel 1 $cmd]
  }

  proc count {handle} {
    variable ctable
    if ![info exists ctable($handle)] {
      error "No ctable open for $handle"
    }
    return [$ctable($handle) count]
  }

  proc perform {_request args} {
    upvar 1 $_request request
    array set temp [array get request]
    array set temp $args
    if ![info exists temp(-handle)] {
      return -code error "No URI specified in $_request"
    }
    return [uplevel 1 [list ::sttpx::_perform $temp(-handle) $_request] $args]
  }

  proc _perform {handle _request args} {
    upvar 1 $_request request
    array set temp [array get request]
    array set temp $args
    if [info exists temp(-count)] {
      set result_var $temp(-count)
      unset temp(-count)
    }
    # Allow overriding
    if [info exists temp(-handle)] {
      set handle $temp(-handle)
      unset temp(-handle)
    }
    lappend cmd ::sttpx::search $handle
    set cmd [concat $cmd [array get temp]]
    if [info exists result_var] {
      set cmd "set $result_var \[$cmd]"
    }
    uplevel 1 $cmd
  }
}

namespace eval ::sttp {
  namespace import ::sttpx::*
}

package provide sttpx 1.0


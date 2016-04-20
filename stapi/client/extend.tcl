#
#
# Copyright (C) 2005-2006 by Superconnect, Ltd.  All Rights Reserved
#
#
# $Id$
#

package require stapi

namespace eval ::stapi::extend {
  variable stapi_cmds
  array set stapi_cmds {
    indexed indexed
    types   types
    destroy destroy
    ctable  ctable
    table   ctable
    makekey makekey
    keys    keys
    key     key
    store   store
    search  search
  }

  proc indexed {handle} {
    variable indexed

    if {![info exists indexed($handle)]} {
      variable ctable

      if {![info exists ctable($handle)]} {
        error "No table open for $handle"
      }

      set indexed($handle) [$ctable($handle) index indexed]
    }
    return $indexed($handle)
  }

  proc types {handle} {
    variable types

    if {![info exists types($handle)]} {
      variable ctable

      if {![info exists ctable($handle)]} {
        error "No table open for $handle"
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
    if {[extended $handle]} {
      return $handle
    }

    if {[info exists stable($handle)]} {
      return $stable($handle)
    }

    set keysep ":"
    array set opts $args
    if {[info exists opts(-keysep)]} {
      set keysep $opts(-keysep)
      unset opts(-keysep)
      set args [array get opts]
    }

    # debug "[list ::stapi::connect $handle] $args"
    # If URI format, connect, otherwise assume it's already an open ctable
    if {[string match "*://*" $handle]} {
      set ctable($handle) [eval [list ::stapi::connect $handle] $args]
    } else {
      set ctable($handle) [uplevel 1 [list namespace which $handle]]
    }

    set keyfields($handle) $keys
    set separator($handle) $keysep

    incr seq
    set stable($handle) ::stapi::extend::_table$seq

    #proc $stable($handle) {cmd args} "uplevel 1 \[concat \[list stapi \$cmd $handle] \$args]"
	make_springboard_proc $stable($handle) $handle

    return $stable($handle)
  }

variable springboardProcCode
set springboardProcCode {
	proc %s {cmd args} {
		catch {uplevel 1 {stapi $cmd %s $args} catchResult catchOptions
		return -options $catchOptions $catchResult
	}
}

proc make_springboard_proc {procName handle} {
	variable springboardProcCode

	set procBody [format $springboardProcCode $procName $handle]
	eval $procBody
}

  # Check if the handle supports minimal stapi extensions:
  # * If it's wrapped, yes, otherwise...
  #   * Handles "method" method.
  #   * Handles "makekey" command.
  #   * Handles "store" command.
  #   * Handles "key" or "keys" commands.
  #   * If keys required, [$handle key/keys] matches
  proc extended {handle {keys {}}} {
    if {[string match ::stapi::extend::_table* $handle]} {
        return 1
    }

    if {[catch {set mlist [$handle methods]}]} {
        return 0
    }

    if {[lsearch $mlist makekey] == -1} {
        return 0
    }

    if {[lsearch $mlist store] == -1} {
        return 0
    }

    if {[lsearch $mlist keys] != -1} {
        set keyCmd "keys"
    }

    if {[lsearch $mlist key] != -1} {
        set keyCmd "key"
    }

    if {![info exists keyCmd]} {
        return -1
    }

    if {![llength $keys]} {
        return 1
    }

    if {"$keyCmd" == "keys"} {
      if {"$keys" == "[$handle keys]"} {
          return 1
      }
    } else {
      if {[llength $keys] > 1} {
          return 0
      }

      if {"[lindex $keys 0]" == "[$handle key]"} {
          return 1
      }
    }
    return 0
  }
  namespace export extended

  proc keys {handle} {
    variable keyfields

    if {![info exists keyfields($handle)]} {
      error "No connection for $handle"
    }
    return $keyfields($handle)
  }

  namespace export keys

  proc key {handle} {
    variable keyfields

    if {![info exists keyfields($handle)]} {
      error "No connection for $handle"
    }

    if {[llength $keyfields($handle) != 1]} {
      return "_key"
    }
    return [lindex $keyfields($handle) 0]
  }
  namespace export keys

  proc stapi {cmd handle} {
    variable stapi_cmds
    variable ctable

    if {![info exists ctable($handle)]} {
      return -code error "No ctable open for $handle"
    }

    set list {}
    if {[info exists stapi_cmds($cmd)]} {
      lappend list ::stapi::extend::$stapi_cmds($cmd) $handle
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

    if {![info exists ctable($handle)]} {
      error "No table open for $handle"
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

    if {![info exists ctable($handle)]} {
      return -code error "No table open for $handle"
    }
    return $ctable($handle)
  }

  proc connected {handle} {
    variable keyfields
    return [expr {[info exists keyfields($handle)] || [extended $handle]}]
  }
  namespace export connected

  proc makekey {handle args} {
    variable keyfields

    if {![info exists keyfields($handle)]} {
      error "No connection for $handle"
    }

    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }

    array set k $args
    set key {}
    foreach n $keyfields($handle) {
      lappend key $k($n)
    }

    if {[llength $key] == 0} {
      if {[info exists k(_key)]} {
	return $k($key)
      } else {
	return -code error "No key in list"
      }
    } elseif {[llength $key] == 1} {
      return [lindex $key 0]
    } elseif {"$separator($handle)" == "list"} {
      return $key
    } else {
      return [join $key $separator($handle)]
    }
  }

  proc store {handle args} {
    variable keyfields
    variable ctable

    if {![info exists keyfields($handle)]} {
      error "No connection for $handle"
    }
    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }
    $ctable($handle) set [makekey $handle $args] $args
  }

  proc debug {args} {
    eval ::stapi::debug $args
  }

  proc search {handle args} {
    variable ctable

    if {![info exists ctable($handle)]} {
      error "No table open for $handle"
    }

    lappend cmd $ctable($handle)
    array set options $args

    set debug 0
    if {[info exists options(-debug)]} {
      set debug $options(-debug)
      unset options(-debug)
    }

    if {$debug} {
      debug [info level 0]
    }

    if {![info exists options(-code)]} {
      foreach opt {
	-key -array -array_with_nulls -array_get -array_get_with_nulls
      } {
	if {[info exists options($opt)]} {
	  set options(-limit) 1
	  set options(-code) break
	}
      }
    }

    if {[info exists options(-compare)]} {
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
	  if {[info exists fn]} {
	    set pat [string $fn $pat]
	  }

	  set list [concat $op [lindex $list 1] [list $pat]]
	}
	lappend new_compare $list
      }
      set options(-compare) $new_compare
    }

    lappend cmd search

    foreach {n v} [array get options] {
      lappend cmd $n $v
    }

    if {$debug} {
      debug [list uplevel 1 $cmd]
    }
    return [uplevel 1 $cmd]
  }

  proc count {handle} {
    variable ctable

    if {![info exists ctable($handle)]} {
      error "No table open for $handle"
    }
    return [$ctable($handle) count]
  }
}

namespace eval ::stapi {
  namespace import ::stapi::extend::*
}

package provide stapi_extend 1.9.0


#
#
# Copyright (C) 2005-2006 by Superconnect, Ltd.  All Rights Reserved
#
#
# $Id$
#

package require sttp
package require sttp_optimizer

namespace eval ::sttp_display {
  proc indexed {uri} {
    variable indexed
    if ![info exists indexed($uri)] {
      variable ct
      if ![info exists ct($uri)] {
        error "No ctable open for $uri"
      }
      set indexed($uri) [$ct($uri) index indexed]
    }
    return $indexed($uri)
  }

  proc types {uri} {
    variable types
    if ![info exists types($uri)] {
      variable ct
      if ![info exists ct($uri)] {
        error "No ctable open for $uri"
      }
      set types($uri) {}
      foreach f [$ct($uri) fields] {
	lappend types($uri) $f [$ct($uri) fieldtype $f]
      }
    }
    return $types($uri)
  }

  proc connect {uri keyfields args} {
    variable kf
    variable ct

    if [info exists kf($uri)] {
      if [info exists ct($uri)] {
	return $ct($uri)
      } else {
        unset kf($uri)
      }
    }

    # debug "[list ::scache::connect $uri] $args"
    set ct($uri) [eval [list ::scache::connect $uri] $args]
    set kf($uri) $keyfields
    return $ct($uri)
  }

  proc ctable {uri} {
    variable kf
    variable ct

    if ![info exists kf($uri)] {
      return -code error "No connection for $uri"
    }
    if ![info exists ct($uri)] {
      return -code error "No ctable open for $uri"
    }
    return $ct($uri)
  }

  proc connected {uri} {
    variable kf
    return [info exists kf($uri)]
  }

  proc makekey {uri _k} {
    variable kf
    if ![info exists kf($uri)] {
      error "No connection for $uri"
    }
    upvar $_k k
    set key {}
    foreach n $kf($uri) {
      lappend key $k($n)
    }
    return [join $key :]
  }

  proc fetch {uri key _a} {
    variable kf
    variable ct
    if ![info exists kf($uri)] {
      error "No connection for $uri"
    }
    upvar 1 $_a a
    if [regexp {^@(.*)} $key _ _k] {
      upvar $_k k
      set key [makekey $uri k]
    } elseif {![string match "*:*" $key]} {
      set key [join $key :]
    }
    if ![$ct($uri) exists $key] {
      return 0
    }
    set list [$ct($uri) array_get_with_nulls $key]
    array set a $list
    return 1
  }

  proc store {uri _a} {
    variable kf
    variable ct
    if ![info exists kf($uri)] {
      error "No connection for $uri"
    }
    upvar 1 $_a a
    $ct($uri) set [makekey $uri a] [array get a]
  }

  proc delete {uri key} {
    variable ct
    variable kf
    if ![info exists kf($uri)] {
      error "No connection for $uri"
    }
    if [regexp {^@(.*)} $key _ _k] {
      upvar $_k k
      set key [makekey $uri a]
    } elseif {![string match "*:*" $key]} {
      set key [join $key :]
    }
    $ct($uri) delete $key
  }

  proc sync {uri} {
    variable ct
    if ![info exists ct($uri)] {
      error "No ctable open for $uri"
    }
    $ct($uri) sync
  }

  proc debug {args} {
    eval ::scache::debug $args
  }

  proc search {uri args} {
    variable ct
    if ![info exists ct($uri)] {
      error "No ctable open for $uri"
    }
    lappend cmd [namespace which $ct($uri)]
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
      foreach opt {-key -array -array_with_nulls -array_get -array_get_with_nulls} {
	set options(-limit) 1
	set options(-code) break
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
    if {"[set i [indexed $uri]]" != ""} {
      if [::scache::optimize options $i [types $uri]] {
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

  proc count {uri} {
    variable ct
    if ![info exists ct($uri)] {
      error "No ctable open for $uri"
    }
    return [$ct($uri) count]
  }

  proc perform {_request args} {
    upvar 1 $_request request
    array set temp [array get request]
    array set temp $args
    if ![info exists temp(-uri)] {
      return -code error "No URI specified in $_request"
    }
    if [info exists temp(-count)] {
      set result_var $temp(-count)
      unset temp(-count)
    }
    lappend cmd [namespace which search] $temp(-uri)
    unset temp(-uri)
    set cmd [concat $cmd [array get temp]]
    if [info exists result_var] {
      set cmd "set $result_var \[$cmd]"
    }
    uplevel 1 $cmd
  }
}

package provide sttp_display 1.0

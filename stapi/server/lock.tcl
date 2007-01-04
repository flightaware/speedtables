#
# $Id$

namespace eval ::scache {
  variable locking 0
  variable lock_level 0
  proc lockfile {name _err {timeout 120}} {
    variable lock_level
    # debug "LOCK $name $timeout (level $lock_level)"
    if $lock_level {
      incr lock_level
      return 1
    }
    upvar 1 $_err err
    variable locking
    if $locking {
      set err "Recursive lock call for $name"
      return 0
    }
    set locking 1
    set tempfile $name.[pid]
    set lockfile $name.lock
    set fp [open $tempfile w]
    puts $fp [pid]
    close $fp
    set sleep_time [expr {9500 + [pid] % 1000}]
    set retries [expr {$timeout / 10}]
    while {$retries > 0} {
      if ![catch {file rename $tempfile $lockfile} errmsg] {
        if ![file exists $tempfile] {
	  # debug "LOCKED $name"
	  incr lock_level
	  set locking 0
	  return 1
	}
      } elseif {"[lindex $::errorCode 1]" != "EEXIST"} {
        file delete $tempfile
	set err $errmsg
	debug "NOT LOCKED $name $err"
	set locking 0
	return 0
      }
      incr retries -1
      after $sleep_time
    }
    file delete $tempfile
    set err "Timeout creating lock file for $name"
    debug "NOT LOCKED $name $err"
    set locking 0
    return 0
  }

  proc unlockfile {name} {
    variable lock_level
    # debug "UNLOCK $name (level $lock_level)"
    if {$lock_level <= 0} {
      set lock_level 0
      return -code error "Unlocking when not locked!"
    }
    incr lock_level -1
    if $lock_level {
      return
    }
    file delete $name.lock
  }
}

package provide scache_locks 1.0

#
# $Id$

package require Tclx

namespace eval ::stapi {
  variable locking 0
  variable lock_level

  if {![string length [info procs debug]]} {
    proc debug {args} {
      puts stderr "DEBUG: [join $args "\nDEBUG: "]"
    }
  }

  proc lockfile {name _err {timeout 120} {recursing 0}} {
    variable lock_level

    if {![info exists lock_level($name)]} {
      set lock_level($name) 0
    }

    if {$lock_level($name) > 0} {
      incr lock_level($name)
      return 1
    }

    upvar 1 $_err err

    # We allow one level of recursive locking to set a lock around a lockfile
    # while checking for a dead lock
    if {!$recursing} {
      variable locking
      if {$locking} {
        set err "Recursive lock call for $name"
        return 0
      }
      set locking 1
    }

    set lockfile $name.lock

    set sleep_time [expr {4500 + [pid] % 1000}]
    set retries [expr {($timeout * 10000) / $sleep_time}]
    set final_err "Timeout creating lock file for $name"
    set lockfile_locked 0

    while {$retries > 0} {
      # careful! Keep track of whether we're ok and locked separately
      set ok 1

      # First, if we're not already recursing to lock a lockfile, lock it

      if {!$recursing} {
	set ok 0

	if {[lockfile $lockfile errmsg 20 1]} {
	  # And make sure we know we're locked
	  set lockfile_locked 1
	  set ok 1
	}
      }

      # If we're OK (locked or recursing)...
      if {$ok} {
	# If we can't lock, set not OK
        if {[catch {set fp [open $lockfile {CREAT EXCL RDWR}]} errmsg]} {
	  # If we can't lock for some reason than the lockfile exists, break
          if {"[lindex $::errorCode 1]" != "EEXIST"} {
	    set final_err $errmsg
	    break
          }
	  set ok 0
	} else {
	  # Record who we are
	  puts $fp [pid]
	  close $fp
	  unset fp
	}
      }

      # whether OK or not, if we locked the lockfile, we own it, release lock
      if {$lockfile_locked} {
	unlockfile $lockfile
	set lockfile_locked 0
      }

      # If OK, locked file
      if {$ok} {
	# debug "LOCKED $name"
	incr lock_level($name)
        if {!$recursing} {
          set locking 0
        }
	return 1
      }

      # At this point, we've been unable to lock...
      if {!$recursing} {
	# We're not locking the lockfile, so lock the lockfile...
	if {![lockfile $lockfile err 20 1]} {
	  debug "Locks held: [array get lock_level]"
	  debug "This call: [info level 0]"
	  return -code error "PANIC! Can't lock lockfile to check stale lock: $err"
	} else {
	  # It shouldn't be possible for this to break out, but be paranoid
	  set lockfile_locked 1
	  # If the file's older than the sleep time, check if the proc is dead
	  if {[catch {set lock_time [file mtime $lockfile]} err]} {
	    # File probably been deleted behind our back, we'll check that
	    # next time around
	    debug $err
	  } elseif {$lock_time + $sleep_time / 500 < [clock seconds]} {
	    unset -nocomplain pid

            set fp [open $lockfile r]
            if {[gets $fp pid] <= 0} {
	      # empty file, other process is probably still locking it
	      unset pid
	      debug "Empty lockfile"
	    }
            close $fp
	    unset fp

	    if {[info exists pid] && [dead_proc $pid]} {
	      debug "Deleting stale lockfile $lockfile"
	      file delete $lockfile
	    }
          }
	  # Now we've either deleted the lockfile or not, unlock it.
	  unlockfile $lockfile
	  set lockfile_locked 0
	}
      }

      # try again
      incr retries -1
      after $sleep_time
    }

    # If we broke out of the loop with a lock on the lockfile, release it
    if {$lockfile_locked} {
      unlockfile $lockfile
      set lockfile_locked 0
    }

    # Record why we think we failed
    set err $final_err
    debug "NOT LOCKED $name $err"

    # And note that we're out
    if {!$recursing} {
      set locking 0
    }
    return 0
  }

  proc unlockfile {name} {
    variable lock_level

    if {![info exists lock_level($name)]} {
      set lock_level($name) 0
    }

    # debug "UNLOCK $name (level $lock_level($name))"
    if {$lock_level($name) <= 0} {
      set lock_level($name) 0
      return -code error "Unlocking when not locked!"
    }

    incr lock_level($name) -1
    if {$lock_level($name) > 0} {
      return
    }

    set lock_level($name) 0
    file delete $name.lock
  }

  proc dead_proc {pid} {
    if {[catch {kill -0 $pid}]} {
      return [expr {"[lindex $::errorCode 1]" == "ESRCH"}]
    }
    return 0
  }
}

package provide st_locks 1.13.9

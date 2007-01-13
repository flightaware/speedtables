# $Id$

package provide scache_optimizer 1.0

namespace eval ::scache {
  # Ops that can be usefully indexed
  variable index_ops {"<" "=" ">" "<=" ">=" "in" "range"}
  # Ops that strongly limit a search, in ascending quality
  variable range_ops {"range" "=" "in"}

  # query optimizer
  # input - an array containing the arguments to a $ctable search
  #       - a list of indexed fields
  #	  - a name-value pair set of field types
  # output - a possibly optimised search in the array
  #	   - true if optimization was possible and you can use search+

  proc optimize {_request {indices {}} {_types {}}} {
    if ![llength $indices] {
      return 0
    }
    array set types $_types

    variable index_ops
    variable range_ops
    upvar 1 $_request request

    if ![info exists request(-compare)] {
      return 0
    }

    # See if the sort is an ascending sort on a single key
    if {[info exists request(-sort)] && [llength $request(-sort)] == 1} {
      set sort_by [lindex $request(-sort) 0]
      if [string match "-*" $sort_by] {
	unset sort_by
      }
    }

    # We're building four lists, ranged, anchored matches, indexed, and
    # unindexed. 
    set unindexed_tuples {}
    set indexed_tuples {}
    set anchored_tuples {}
    set ranged_tuples {}

    # Sort out unindexed, anchored, and ranged tuples. Sort indexed tuples
    # into an array of indexed tuple lists for later
    foreach tuple $request(-compare) {
      foreach {op field} $tuple {break}

      # hack, if a <> has leaked through from a postgres-compatible
      # expression, squash it
      if {"$op" == "<>"} {
        set op "!="
        set tuple [concat $op [lrange $tuple 1 end]]
      }

      if {[lsearch $indices $field] == -1} {
        lappend unindexed_tuples $tuple
      } else {
        if {[string match "match*" $op]} {
          set pat [lindex $tuple 2]
          if {"$op" == "match_case" && ![string match {[*]*} $pat]} {
            lappend anchored_tuples $tuple
          } elseif {"$op" == "match" && ![string match {[*a-zA-Z?]*} $pat]} {
            lappend anchored_tuples $tuple
          } else {
            lappend unindexed_tuples $tuple
          }
        } elseif {[lsearch $range_ops $op] != -1} {
          lappend ranged_tuples $tuple
        } elseif {[lsearch $index_ops $op] != -1} {
          lappend indexed_lists($field) $tuple
        } else {
          lappend unindexed_tuples $tuple
        }
      }
    }

    # If we don't have any ranged lists yet, try and make some

    # First, if there's an anchored match, use that
    foreach tuple $anchored_tuples {
      # Just treat matches as unindexed if we've already pulled out a
      # range one way or another (may want to change this)
      if [llength $ranged_tuples] {
        lappend unindexed_tuples $tuple
        continue
      }

      foreach {op field pat} $tuple break

      # Don't do match checks if it's not a string.
      if [info exists types($field)] {
	if ![string match "*string*" $types($field)] {
	  lappend unindexed_tuples $tuple
	  continue
	}
      }

      # Try and extract a range condition from the match

      # If an anchored match, insert a range comparison if there's no
      # indexed comparisons yet
      if {"$op" == "match_case"} {
        regexp {^([^*?]*)(.*)} $pat _ prefix suffix
      } elseif {"$op" == "match"} {
        regexp {^([^*?a-zA-Z]*)(.*)} $pat _ prefix suffix
      } else {
	set prefix ""
	set suffix $pat
      }
      if [string length $prefix] {
        set lo $prefix
        set hi [string range $prefix 0 end-1]
        scan [string index $prefix end] "%c" char
        incr char
        append hi [format %c $char]
        lappend ranged_tuples [list range $field $lo $hi]
	if {"$suffix" == "*"} {
	  unset tuple
	}
      }
      if [info exists tuple] {
        lappend unindexed_tuples $tuple
      }
    }

    # Go through the indexed lists
    foreach {field tuples} [array get indexed_lists] {
      # accumulate "high value" and "low value" into lists
      unset -nocomplain lo_list
      unset -nocomplain hi_list
      foreach tuple $tuples {
        # already got a range, just keep accumulating
        if [llength $ranged_tuples] {
          lappend indexed_tuples $tuple
          continue
        }

        foreach {op field val} $tuple break

        # If it's a test that could be turned into part of a range, save it
        if {"$op" == ">="} {
          lappend lo_list $val
        } elseif {"$op" == "<"} {
          lappend hi_list $val
	} elseif {"$op" == ">"} {
	  # Restrict to ">="
	  lappend lo_list $val
	  # Eliminate ">=" that are not also ">"
	  lappend indexed_tuples $tuple
        } else {
          # ... otherwise it's "just" a test
          lappend indexed_tuples $tuple
        }
      }

      # finished twiddling tuples...
      # Look for lo <= field < hi, or reconstruct the tuples we pulled out
      if [info exists lo_list] {
        set lo [lindex [lsort $lo_list] 0] 
        if [info exists hi_list] {
          set hi [lindex [lsort $hi_list] end] 
          lappend ranged_tuples [list range $field $lo $hi]
        } else {
          lappend indexed_tuples [list >= $field $lo]
        }
      } elseif [info exists hi_list] {
        set hi [lindex [lsort $hi_list] end] 
        lappend indexed_tuples [list < $field $hi]
      }
    }

    # Look for "best" ranged tuple and move it to the front
    # The ops in $range_ops are sorted by ascending quality so the
    # index IS the quality
    set best_index -1
    set best_quality -1
    set index -1
    foreach tuple $ranged_tuples {
      incr index
      set op [lindex $tuple 0]
      set quality [lsearch $op $range_ops]
      if {$quality > $best_quality} {
	set best_index $index
        set best_quality $quality
      }
    }
    # if the best quality isn't already at the head, move it up
    if {$best_index > 0} {
      set best_tuples [lrange $ranged_tuples $best_index $best_index]
      set rest_tuples [lreplace $ranged_tuples $best_index $best_index]
      set ranged_tuples [concat $best_tuples $rest_tuples]
    }

    # See if we can make the sort key the search key
    if [info exists sort_by] {
      if [llength $ranged_tuples] {
	# We don't re-order the ranged tuples to do this, just see if we can
        if {"[lindex [lindex $ranged_tuples 0] 1]" == "$sort_by"} {
	  unset request(-sort)
        }
      } else {
	# We can re-order the non-ranged indexed tuples
	set i -1
	set j -1
	foreach tuple $indexed_tuples {
	  incr j
	  if {"[lindex $tuple 1]" == "$sort_by"} {
	    set i $j
	    break
	  }
        }
	if {$i != -1} {
	  unset request(-sort)
	  if {$i > 0} {
	    set indexed_tuples [
	      concat [list $sort_by] [lreplace $indexed_tuples $i $i]
	    ]
	  }
	}
      }
    }

    # Shove any ranged tuples in before other indexed tests
    set indexed_tuples [concat $ranged_tuples $indexed_tuples]

    # then replace the comparison if we had any joy, and let
    # the caller know we've optimized stuff
    if [llength $indexed_tuples] {
      set request(-compare) [concat $indexed_tuples $unindexed_tuples]
      return 1
    }
    return 0
  }
}

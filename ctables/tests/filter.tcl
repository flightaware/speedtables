source test_common.tcl

CExtension Filtertest 1.0 {
  CTable track {
    varstring id indexed 1 notnull 1 unique 1
    double latitude indexed 1 notnull 1 default 1.0
    double longitude indexed 1 notnull 1 default 1.0

    # The Cfilter code fragment is not guaranteed to be a separate c function,
    # but it does allow local variables and the following names are in scope:
    #   interp - Tcl interpeter
    #   ctable - A pointer to this ctable instance
    #   row - A pointer to the row being examined
    #   filter - A TclObj filter argument passed from search
    #   sequence - A unique non-zero integer for each search operation, for
    #		memoization of search parameters in complex searches.
    #
    # Return:
    #   TCL_OK for a match.
    #   TCL_CONTINUE for a miss.
    #   TCL_RETURN or TCL_BREAK to terminate the search without an error.
    #   TCL_ERROR to terminate the search with an error.
    cfilter latorlong code {
      double target;
      if(Tcl_GetDoubleFromObj (interp, filter, &target) != TCL_OK)
        return TCL_ERROR;
      if(row->latitude == target || row->longitude == target) return TCL_OK;
      return TCL_CONTINUE;
    }
    cfilter distance code {
      static double target_lat, target_long, target_range;
      static int lastSequence = 0;

      // Only parse target information if the search ID changes.
      if(sequence != lastSequence) {
        Tcl_Obj **filterList;
        int       filterCount;
        if(Tcl_ListObjGetElements(interp, filter, &filterCount, &filterList) != TCL_OK)
	  return TCL_ERROR;
        if(filterCount != 3) {
	  Tcl_AppendResult(interp, "wrong number of arguments: expected lat long range", NULL);
	  return TCL_ERROR;
        }
        if(Tcl_GetDoubleFromObj (interp, filterList[0], &target_lat) != TCL_OK)
          return TCL_ERROR;
        if(Tcl_GetDoubleFromObj (interp, filterList[1], &target_long) != TCL_OK)
          return TCL_ERROR;
        if(Tcl_GetDoubleFromObj (interp, filterList[2], &target_range) != TCL_OK)
          return TCL_ERROR;
	lastSequence = sequence;
      }

      double dlat = target_lat - row->latitude;
      double dlong = target_long - row->longitude;
      double dsquared = (dlat * dlat) + (dlong * dlong);
      if(dsquared <= (target_range * target_range)) return TCL_OK;
      return TCL_CONTINUE;
    }
  }
}

package require Filtertest

track create t

for {set i 0} {$i < 100} {incr i} {
  t set $i id CO$i latitude $i longitude [expr {100 - $i}]
}

set found [t search -filter {{distance {40 30 40}}} -countOnly 1]
if {$found != 47} {
  error "Should have returned 47 points within 30 units of (40,30) (got $found)"
}

for {set i 0} {$i < 10000} {incr i} {
  set lat [expr {rand() * 100.0}]
  set long [expr {rand() * 100.0}]
  set row [expr {int(rand() * 100.0)}]
  t set $row latitude $lat longitude $long
  if {[t search -filter [list [list distance [list $lat $long 1]]] -countOnly 1] <= 0} {
    error "Should have had at least one point in 1 unit of ($lat, $long)"
  }
}

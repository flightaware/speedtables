package require ctable

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
  }
}

package require Filtertest

track create t

for {set i 0} {$i < 100} {incr i} {
  t set $i id CO$i latitude $i longitude [expr 100 - $i]
}

t search -filter {latorlong 4} -array_get a -code { puts $a }


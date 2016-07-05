# $Id$

if ![info exists ::test::loaded_test_common] {
  namespace eval ::test {
    variable loaded_test_common
    set loaded_test_common 1
  }

  # Force loading the right version of ctables
  set parent [file dirname [pwd]]
  namespace eval ctable [list set srcDir $parent]

  # Cons up a good libpath if there isn't one
  if {[info exists env(TCLLLIBPATH)]} {
      set libpath $env(TCLLLIBPATH)
  } else {
      set grandparent [file dirname $parent]
      set libpath [list $parent $grandparent/ctable_server $grandparent/stapi]
  }

  # Force test environment to be at the beginning of auto_path
  set auto_path [concat $libpath $auto_path]

  # Load ctables by both names
  source ../gentable.tcl

  # Common overrides for ctable config variables, commented out, usual default
  namespace eval ctable {

    # set to 1 to see errorInfo in normal tracebacks
    #set errorDebug 0

    # set to 0 to generate without the "-pipe" in the gcc command
    #variable withPipe 1

    # set to 1 to build with debugging and link to tcl debugging libraries
    #set genCompilerDebug 0
    # set to 1 to link to mem debug libraries
    set memDebug 0

    if {"[info commands memory]" != ""} {
        set memDebug 1
        memory onexit [file join [pwd] memory.log]
    }

    # set to 1 to show compiler commands
    set showCompilerCommands 1

    # set to 1 to run various sanity checks on rows
    #set sanityChecks 0

    # Create and manage the "dirty" flag
    #set withDirty 1

    # Shared Memory config

    #set withSharedTables 1
    #set withSharedTclExtension 0
    # Either -none, -stderr, or the name of a file
    #set sharedTraceFile -none

    # either NULL or an absolute address
    #set sharedBase 0xA0000000

    # approx number of ctable row pools required to fill all shared memory
    #set poolRatio 16
  }

}

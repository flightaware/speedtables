# Common configuration parameters

    # with FlightAware, this overrides later definitions
    #set sysPrefix /usr/fa
    #set pgPrefix /usr/fa

    # set to 1 to see errorInfo in normal tracebacks
    set errorDebug 1

    # set to 0 to generate without the "-pipe" in the gcc command
    variable withPipe 1

    # set to 1 to build with debugging and link to tcl debugging libraries
    set genCompilerDebug 1
    # set to 1 to link to mem debug libraries
    set memDebug 0

    # set to 1 to show compiler commands
    set showCompilerCommands 0

    # set to 1 for pgTcl support
    set withPgtcl 1

# Less common parameters

    # set to 1 to run various sanity checks on rows
    set sanityChecks 0

    set withSharedTables 1
    set withSharedTclExtension 0
    # Either -none, -stderr, or the name of a file
    #set sharedTraceFile sharedebug.out
    set sharedTraceFile -none

    # either NULL or an absolute address
    set sharedBase 0xA0000000
    #set sharedBase NULL

    # approx number of ctable row pools required to fill all shared memory
    set poolRatio 16

    # Create and manage the "dirty" flag
    set withDirty 1

    # create files in a subdirectory
    set withSubdir 1

    variable pgtcl_ver 1.6

# OS-specific defaults - will be replaced by stuff from tclConfig.sh

    if {$tcl_platform(os) == "Darwin"} {
	set withPgtcl 0
	unset -nocomplain pgPrefix

	set sharedLibraryExt .dylib

	if {![info exists sysPrefix]} {
	    set sysPrefix /System/Library/Frameworks/Tcl.framework/Versions/8.4
	}
    } else {
	set sharedLibraryExt .so
	if {![info exists sysPrefix]} {
	    set sysPrefix /usr/local
	}
	if {$withPgtcl && ![info exists pgPrefix]} {
	    set pgPrefix /usr/local
	}
    }


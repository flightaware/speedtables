# Common configuration parameters

    # set to 1 to see errorInfo in normal tracebacks
    set errorDebug 1

    # set to 0 to generate without the "-pipe" in the gcc command
    variable withPipe 1

    # set to 1 to build with debugging and link to tcl debugging libraries
    set genCompilerDebug 0

    # set to 1 to link to mem debug libraries
    set memDebug 0

    # Set to 0 to import some code without inline.
    set fullInline 0

    # Set to 0 to expose internal functions
    set fullStatic 1

    # set to 1 to show compiler commands
    set showCompilerCommands 0

# Less common parameters

    # set to 1 to run various sanity checks on rows
    set sanityChecks 1

    set withSharedTables 1
    set withSharedTclExtension 0
    # Either -none, -stderr, or the name of a file
    #set sharedTraceFile sharedebug.out
    set sharedTraceFile -none
    #set sharedTraceFile -stderr

    set sharedBase 0xA0000000; ### Default (FreeBSD...)
    if { "$tcl_platform(os)" == "Darwin" } {
    	set sharedBase 0xA000000; ## OS X
    }
    #set sharedBase -1 ; # Use this one to probe on first allocation
    #set sharedBase NULL

    # Add guard checks to shared memory code
    set sharedGuard 0

    # Log shared memory allocations
    #set sharedLog shmDebug.log

    # approx number of ctable row pools required to fill all shared memory
    set poolRatio 16

    # Create and manage the "dirty" flag
    set withDirty 1

    # create files in a subdirectory
    set withSubdir 1



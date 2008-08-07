# Common configuration parameters

    # set to 1 to see errorInfo in normal tracebacks
    set errorDebug 1

    # set to 0 to generate without the "-pipe" in the gcc command
    variable withPipe 1

    # set to 1 to build with debugging and link to tcl debugging libraries
    set genCompilerDebug 1
    # set to 1 to link to mem debug libraries
    set memDebug 0
    # Set to 0 to import the skiplist code without inline
    set fullInline 1

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

# OS-specific tweaks
    set sysFlags(Darwin) "-DCTABLE_NO_SYS_LIMITS"

# Last minute safety catch
    if {![info exists sysconfig(pgtclprefix)]} {
	set withPgtcl 0
    }


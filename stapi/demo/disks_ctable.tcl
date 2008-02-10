# $Id$

package require ctable

set workdir /usr/local/lib/rivet/packages-local/sttp_demo/ctables
CTableBuildPath $workdir
lappend auto_path $workdir

CExtension disks_ctable 1.0 {

CTable c_disks {
    int		fundamentalFileSystemBlockSize
    int		optimalTransferBlockSize
    int		totalDataBlocks
    int		freeBlocks 
    int		availableFreeBlocks 
    int		totalFileNodes
    int		freeFileNodes 
    varstring	fileSystemType
    varstring	mountPoint
    varstring	mountedFileSystem
    varstring	flags
    varstring	host
    key		disk
    int		totalMegs
    int		freeMegs
    int		availableFreeMegs
    int		usedMegs
    int		capacity
}

}

package require Disks_ctable

package provide disks_ctable 1.0


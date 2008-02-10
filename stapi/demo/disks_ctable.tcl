# $Id$

package require ctable
package require stapi_demo_config

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


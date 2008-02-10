# $Id$

package require stapi_demo_config

CExtension fsstat_ctable 1.0 {

CTable c_fsstat {
    int		fundamentalFileSystemBlockSize
    int		optimalTransferBlockSize
    int		totalDataBlocks
    int		freeBlocks 
    int		availableFreeBlocks 
    int		totalFileNodes
    int		freeFileNodes 
    varstring	fileSystemType
    varstring	mountPoint
    key		mountedFileSystem
    varstring	flags
}

}

package require Fsstat_ctable

package provide fsstat_ctable 1.0


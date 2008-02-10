# $Id$

proc load_disks {ctable} {
    set host [info hostname]

    foreach disk [::bsd::getfsstat] {
	array unset d
	array set d $disk

	if {$d(fileSystemType) == "devfs"} continue

	set d(host) $host

	set blocksPerMeg [expr {1048576 / $d(fundamentalFileSystemBlockSize)}]

	set d(totalMegs) [expr ($d(totalDataBlocks) / $blocksPerMeg)]
	set d(freeMegs) [expr ($d(freeBlocks) / $blocksPerMeg)]
	set d(availableFreeMegs) [expr ($d(availableFreeBlocks) / $blocksPerMeg)]

        set usedBlocks [expr $d(totalDataBlocks) - $d(freeBlocks)]

	set d(usedMegs) [expr ($usedBlocks / $blocksPerMeg)]

	set d(capacity) [expr int($usedBlocks / ($usedBlocks + $d(availableFreeBlocks) + 0.5) * 100)]

        set d(disk) $d(host):$d(mountPoint)

	$ctable set $d(disk) [array get d]
    }
}

package provide disks_lib 1.0


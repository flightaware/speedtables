#
# program to generate credible user IDs / user names for testing
#
# $Id$
#

set nNamesToGenerate 1000000

#
# try_fake_userid see if the name has already been "taken", i.e. used
#
proc try_fake_userid {name} {
     global fakeIdCache lastFakeId

     if {![info exists fakeIdCache($name)]} {
	 set fakeIdCache($name) ""
	 set lastFakeId $name
	 return 1
     }
     return 0
}

#
# get_last_fake_userid - return the last fake ID
#
proc get_last_fake_userid {} {
    global lastFakeId

    return $lastFakeId
}

#
# fake_id_cleanup - turn all the non-alphanumeric characters in the
# string into an underscore, or something
#
proc fake_id_cleanup {string} {
    return [regsub -all {([^a-zA-Z0-9])} $string {_}]
}

#
# gen_fake_userid - given a first and a last name, try different combinations
# of names and numbers to generate an email name / userid type thing.
#
proc gen_fake_userid {firstName lastName} {
    set firstName [fake_id_cleanup [string tolower $firstName]]
    set lastName [fake_id_cleanup [string tolower $lastName]]
    while 1 {
	set odds [expr rand()]

	if {$odds < 0.1} {
	    if {[try_fake_userid $firstName]} return
	}

	if {$odds > 0.9} {
	    if {[try_fake_userid $lastName]} return
	}

	if {$odds < 0.2} {
	    if {[try_fake_userid ${firstName}_$lastName]} return
	}

	if {$odds < 0.6} {
	    if {[try_fake_userid $firstName[expr int(rand()*1000)]]} return
	}

	if {[try_fake_userid $lastName[expr int(rand()*1000)]]} return
    }
}

#
# read_file - read a file and return its contents
#
proc read_file {fileName} {
    set fp [open $fileName]
    set data [read $fp]
    close $fp
    return $data
}

#
# doit - generate the data
#
# by forcing srand to a fixed integer, we should always generate the same
# data, hence we can expect this data to be standard
#
# to make sure, we check the last name generated -- if it doesn't match what
# we expect, they did not get good test data where by good we mean data that
# will match the results expected by the test software.
#
proc doit {} {
    global nNamesToGenerate mailHost

    puts stderr "generating $nNamesToGenerate rows of test data"

    set firstnames [split [read_file FirstNames.txt] "\n"]
    set lastnames [split [read_file LastNames.txt] "\n"]

    set sizeLast [llength $lastnames]
    set sizeFirst [llength $firstnames]

    #expr srand(71077345)
    expr srand(15302)

    for {set i 0} {$i < $nNamesToGenerate} {incr i} {
        if {$i % 50000 == 0} {
	    puts -nonewline stderr "$i.. "
	    flush stderr
	}

        while 1 {
	    set lastIndex [expr {int(rand()*$sizeLast)}]
	    set lastName [lindex $lastnames $lastIndex]

	    set firstIndex [expr {int(rand()*$sizeFirst)}]
	    set firstName [lindex $firstnames $firstIndex]

	    set name "$firstName $lastName"
	    if {![info exists tracker($name)]} {
	        set tracker($name) ""
		break
	    }
	}
	gen_fake_userid $firstName $lastName
	puts "[get_last_fake_userid]\t$firstName $lastName"
    }
    puts stderr ""

    if {$firstName != "Anthony" || $lastName != "Chemell"} {
        puts stderr "ERROR - name generator did not generate the standard data, TESTS WILL FAIL"
	puts stderr "Something's nonstandard about your Tcl implementation's random number generator or something."
	exit 1
    }

    exit 0
}

if !$tcl_interactive doit

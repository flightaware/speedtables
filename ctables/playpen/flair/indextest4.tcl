#
#
#
#

package require Tclx
source index.tcl

#m index create key
m index create value

#Meow null_value stinkpot
Meow null_value ""

random seed

set seq 0

proc doputs {command} {
    global seq

    puts [format "%5d %s" $seq $command]
    uplevel $command
    incr seq
}

proc dostuff {} {
    for {set i 0} {$i < 1000000} {incr i} {
	set key [random 5]
	set what [random 5]
	switch $what {
	    0 {
		set value [random 10000]
		#doputs "m set $key key $key value $value"
		doputs "m set $key value $value"
	    }

	    1 {
		set value [random 10000]
		doputs "m set $key key {} value $value"
	    }

	    2 {
		#doputs "m set $key key $key value {}"
		doputs "m set $key value {}"
	    }

	    3 {
		doputs "m delete $key"
	    }

	    4 {
		doputs "m set $key value {}"
	    }
	}
    }
}

proc doit {{argv ""}} {
    dostuff
}

if !$tcl_interactive {
    doit $argv
}

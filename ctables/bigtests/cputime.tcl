#
#
#
#
#

package require BSD

proc cputime {code {iterations 1}} {
    set startRusage [::bsd::rusage]

    for {set i 0} {$i < $iterations} {incr i} {
	uplevel $code
    }

    set endRusage [::bsd::rusage]

    array set start $startRusage
    array set end $endRusage

    set text ""
    foreach var "userTimeUsed systemTimeUsed" {
	set val [expr {($end($var) - $start($var)) / $iterations}]

	append text "$val $var per iteration\n"
    }
    return [string range $text 0 end-1]
}


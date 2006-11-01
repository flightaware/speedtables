#
#
#
#
#

while {[gets stdin line] >= 0} {
    set line [string trim $line]
    if {[string index $line 0] == "#"} continue
    puts [join [split $line ":"] "\t"]
}


#
# test ctables search routine
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

CExtension searchtest 1.0 {

CTable testTable {
    varstring name
    varstring address
    int hipness
    int coolness
    double karma
    boolean realness
    boolean aliveness
}

}

package require Searchtest

testTable create t


t set a name "Jimi Hendrix" address "Rock and Roll Heaven" coolness 100 realness 1 aliveness 0 karma 5
t set b name "Brian Jones" address "Rock and Roll Heaven" coolness 60 realness 1 aliveness 0 karma 5
t set c name "Brock Sampson" address "Venture Compound" coolness 50 realness 0 aliveness 1
t set d name "Hank Venture" address "Venture Compound" coolness 0 realness 0 aliveness 1
t set e name "Doctor Jonas Venture" address "Venture Compound" coolness 10 realness 0 aliveness 0
t set f name "Doctor Jonas Venture Junior" address "Spider Skull Island" coolness 90 realness 0 aliveness 1
t set g name "Doctor Orpheus" address "Venture Compound" coolness 0 realness 0 aliveness 1
t set h name "Triana" address "Venture Compound" coolness 50 realness 0 aliveness 1
t set i name "Doctor Girlfriend" address "The Cocoon" coolness 70 realness 0 aliveness 1
t set j name "The Monarch" address "The Cocoon" coolness 20 realness 0 aliveness 1
t set k name "Number 21" address "The Cocoon" coolness 10 realness 0 aliveness 1
t set l name "Meatwad" address "Next-door to Carl" coolness 10 realness 0 aliveness 1
t set m name "Master Shake" address "Next-door to Carl" coolness 15 realness 0 aliveness 1
t set n name "Frylock" address "Next-door to Carl" coolness 5 realness 0 aliveness 1
t set o name "Rusty Venture" address "Venture Compound" coolness 5 realness 0 aliveness 1



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
    varstring home
    varstring show
    varstring dad
    boolean alive 1
    varstring gender male
    int age
    int coolness
}

}

package require Searchtest

testTable create t

set show "Venture Bros"
set home "Venture Compound"

t set brock name "Brock Sampson" show $show home $home age 35 coolness 100
t set hank name "Hank Venture" show $show home $home dad rusty age 16 coolness -6
t set dean name "Dean Venture" show $show home $home dad rusty age 16 coolness -10
t set jonas name "Doctor Jonas Venture" show $show home $home alive 0 age 60 coolness 60
t set orpheus name "Doctor Orpheus" show $show home $home age 55 coolness 30
t set triana name "Triana" show $show home $home gender female dad orpheus age 16 coolness 50
t set rusty name "Rusty Venture" show $show home $home dad jonas age 45 coolness 4
t set jonas_jr name "Doctor Jonas Venture Junior" show $show home "Spider Skull Island" dad jonas age 45 coolness 100

set home "The Cocoon"
t set doctor_girlfriend name "Doctor Girlfriend" show $show home $home gender female age 30 coolness 80
t set the_monarch name "The Monarch" show $show home $home age 40 coolness 30
t set 21 name "Number 21" show $show home $home age 35 coolness 7
t set 28 name "Number 28" show $show home $home age 36 coolness 5

t set phantom_limb name "Phantom Limb" show $show age 44 coolness 40
t set baron name "Baron Unterbheit" show $show age 38 coolness -100

set show "ATHF"
set home "Next To Carl"

t set meatwad name "Meatwad" show $show home $home  age 4 coolness 0
t set shake name "Master Shake" show $show home $home  age 4 coolness 0
t set frylock name "Frylock" show $show home $home age 4 coolness 0
t set carl name "Carl" show $show home "New Jersey" age 43 coolness 5
t set inignot name "Inignot" show $show home "The Moon" age 2 coolness 30
t set ur name "Ur" show $show home "The Moon" age 1 coolness 20

set show "The Brak Show"
t set dad name "Dad" show $show age 44 coolness 37
t set brak name "Brak" show $show dad dad age 15 coolness 4
t set zorak name "Zorak" show $show age 16 coolness 60
t set mom name "Mom" show $show gender female age 41 coolness 100
t set thundercleese name "Thundercleese" show $show age 6 coolness 14
t set clarence name "Clarence" show $show age 15 coolness -6

set show "Stroker and Hoop"
t set stroker name "John Strokmeyer" show $show age 40 coolness 31
t set hoop name "Hoop" show $show age 38 coolness 14
t set angel name "Angel" show $show gender female age 38 coolness 17
t set carr name "C. A. R. R." show $show age 2 coolness 29
t set rick name "Coroner Rock" show $show age 51 coolness 90



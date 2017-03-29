#
# test ctables search routine
#
# $Id$
#

if {![info exists ac_table]} {
  set ac_table t
}

set show "Venture Bros"
set home "Venture Compound"

$ac_table set brock id brock name "Brock Sampson" show $show home $home age 35 coolness 100
$ac_table set hank id hank name "Hank Venture" show $show home $home dad rusty age 16 coolness -6
$ac_table set dean id dean name "Dean Venture" show $show home $home dad rusty age 16 coolness -10
$ac_table set jonas id jonas name "Doctor Jonas Venture" show $show home $home alive 0 age 60 coolness 60
$ac_table set orpheus id orpheus name "Doctor Orpheus" show $show home $home age 55 coolness 30
$ac_table set triana id triana name "Triana" show $show home $home gender female dad orpheus age 16 coolness 50
$ac_table set rusty id rusty name "Rusty Venture" show $show home $home dad jonas age 45 coolness 6
$ac_table set jonas_jr id jonas_jr name "Doctor Jonas Venture Junior" show $show home "Spider Skull Island" dad jonas age 45 coolness 120

set home "The Cocoon"
$ac_table set doctor_girlfriend id doctor_girlfriend name "Doctor Girlfriend" show $show home $home gender female age 30 coolness 80
$ac_table set the_monarch id the_monarch name "The Monarch" show $show home $home age 40 coolness 36
$ac_table set 21 id 21 name "Number 21" show $show home $home age 35 coolness 7
$ac_table set 28 id 28 name "Number 28" show $show home $home age 36 coolness 9

$ac_table set phantom_limb id phantom_limb name "Phantom Limb" show $show age 44 coolness 40
$ac_table set baron id baron name "Baron Unterbheit" show $show age 38 coolness -100

set show "ATHF"
set home "Next To Carl"

$ac_table set meatwad id meatwad name "Meatwad" show $show home $home  age 4 coolness -7
$ac_table set shake id shake name "Master Shake" show $show home $home  age 4 coolness -5
$ac_table set frylock id frylock name "Frylock" show $show home $home age 4 coolness 8
$ac_table set carl id carl name "Carl" show $show home "New Jersey" age 43 coolness 5
$ac_table set inignot id inignot name "Inignot" show $show home "The Moon" age 2 coolness 31
$ac_table set ur id ur name "Ur" show $show home "The Moon" age 1 coolness 26

set show "The Brak Show"
$ac_table set dad id dad name "Dad" show $show age 44 coolness 37
$ac_table set brak id brak name "Brak" show $show dad dad age 15 coolness 4
$ac_table set zorak id zorak name "Zorak" show $show age 16 coolness 64
$ac_table set mom id mom name "Mom" show $show gender female age 41 coolness 101
$ac_table set thundercleese id thundercleese name "Thundercleese" show $show age 6 coolness 16
$ac_table set clarence id clarence name "Clarence" show $show age 15 coolness -11

set show "Stroker and Hoop"
$ac_table set stroker id stroker name "John Strokmeyer" show $show age 40 coolness 33
$ac_table set hoop id hoop name "Hoop" show $show age 38 coolness 14
$ac_table set angel id angel name "Angel" show $show gender female age 38 coolness 17
$ac_table set carr id carr name "C. A. R. R." show $show age 2 coolness 29
$ac_table set rick id rick name "Coroner Rock" show $show age 51 coolness 99



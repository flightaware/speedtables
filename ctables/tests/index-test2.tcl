#
# some tests that actually check their results
#
# $Id$
#

source dumb-data.tcl



t index create name

t set dad2 name "Dad" show "Ozzie and Harriet" age 44 coolness 37
t set dad3 name "Dad" show "Dexters Lab" age 21 coolness 16

t set zorak2 name "Zorak" show "Space Ghost Coast to Coast" age 16 coolness 60

t index dump name


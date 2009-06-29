#
# $Id$
#

# Just making sure you can define multiple ctables in an extension.

source test_common.tcl

source multitable.ct

nameval create nv
nv set fred name fred value 100
if {"[set res [nv get fred]]" != "fred 100"} {
  error "Failed \[nv get fred] was '$res' expected 'fred 100'"
}

elements create pt

foreach {elt nam sym} {
  1 Hydrogen H
  2 Helium He
  3 Lithium Li
  4 Beryllium Be
  5 Boron B
  6 Carbon C
  7 Nitrogen N
  8 Oxygen O
  9 Fluorine F
  10 Neon Ne
} {
  pt set $elt name $nam symbol $sym
}

if {"[set nam [pt get 5 name]]" != "Boron"} {
  error "Failed \[pt get 5 name] was '$nam' expected 'Boron'"
}

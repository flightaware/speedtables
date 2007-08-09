#!/bin/sh

#$Id$

# Run a test until core dump

rm -f tests/tclsh8.4.core

while [ ! -f tests/tclsh8.4.core ]
do
  make ${1:-multitest}
done


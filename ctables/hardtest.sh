#!/bin/sh

#$Id$

# Run a test until core dump

rm -f tests/tclsh8.4.core

PASS=0
while [ ! -f tests/tclsh8.4.core ]
do
  PASS=`expr $PASS + 1`
  echo "`date` $$ $0 ****** start pass $PASS ******"
  make ${1:-multitest}
done


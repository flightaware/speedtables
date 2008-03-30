#!/bin/sh

case $LOGNAME in
  peter) user=quengho;;
  karl) user=karll;;
  *) echo 'You need to edit this script and add your sourceforge name'; exit;;
esac

rm -r sourceforge
./sftag.tcl
cd sourceforge

scp * $user@shell.sf.net:/home/groups/s/sp/speedtables/htdocs


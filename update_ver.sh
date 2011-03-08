#!/bin/sh

# This script simplifies the process of incrementing all version numbers for a new release.

NEWVER="1.8.1"

perl -p -i -e "s/^(AC_INIT\\(\\[ctable\\],) \\[[0-9.]+\\]/\\1 \\[$NEWVER\\]/" ctables/configure.in

perl -p -i -e "s/^(package provide st\S+) [0-9.]+/\\1 $NEWVER/" stapi/client/*.tcl stapi/display/*.tcl stapi/server/*.tcl stapi/*.tcl

perl -p -i -e "s/^(package provide \S+) [0-9.]+/\\1 $NEWVER/" ctable_server/*.tcl

cd ctables && autoconf && cd ..
cd ctable_server && make pkgIndex.tcl && cd ..
cd stapi && make pkgIndex.tcl && cd ..

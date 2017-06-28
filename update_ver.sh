#!/bin/sh

# This script simplifies the process of incrementing all version numbers for a new release.

NEWVER="1.13.1"

perl -p -i -e "s/^(AC_INIT\\(\\[[a-z_]+\\],) \\[[0-9.]+\\]/\\1 \\[$NEWVER\\]/" configure.in ctables/configure.in stapi/configure.in ctable_server/configure.in

perl -p -i -e "s/^(package provide st\S+) [0-9.]+/\\1 $NEWVER/" stapi/client/*.tcl stapi/display/*.tcl stapi/server/*.tcl stapi/*.tcl

perl -p -i -e "s/^(package provide \S+) [0-9.]+/\\1 $NEWVER/" ctable_server/*.tcl

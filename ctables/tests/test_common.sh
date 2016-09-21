# $Id$
#
# Common environment variables
#

. ../sysconfig.sh
P=`cd ../..; pwd`
export TCLLIBPATH="$P/ctables $P/ctable_server $P/stapi"

TCLSH="tclsh$TCLVER"
TCLSHSTAPI="tclsh$TCLVER"

# With FlightAware
#TCLSH=/usr/fa/bin/tclsh8.4


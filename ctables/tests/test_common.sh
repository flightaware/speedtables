# $Id$
#
# Common environment variables
#

. ../sysconfig.sh

# override sysconfig.sh from environment
if test ! -z "$TCL_VERSION"
then
  export TCLVER=$TCL_VERSION
fi

P=`cd ../..; pwd`
export TCLLIBPATH="$P/ctables $P/ctable_server $P/stapi"

TCLSH="tclsh$TCLVER"
TCLSHSTAPI="tclsh$TCLVER"

# With FlightAware
#TCLSH=/usr/fa/bin/tclsh8.4


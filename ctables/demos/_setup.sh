#!/bin/sh
# $Id$

for format in zip html pdf
do
  ln -f -s ../docs/speedtables.$format .
done

for file in _setup.sh getuser_client getuser_direct getuser_shared getuser_sql getuser_sttp passwd_server.tcl populate_sql.tcl shared_server.tcl
do
  chmod +x $file
done


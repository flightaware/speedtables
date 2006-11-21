
$Id$

This is a server for ctables.  What's cool about it is on the server side there
is one piece of code for serving any ctables you want to serve.

When you start the server you load up all of the ctable creators you want to support and then register them.

Clients can then create tables using ctable creators.  The server can also.






I think really there's some stuff you want to do that may not be an exact map.

I want to set values in one row or many.

I want to retrieve values from one row or many, possibly not all the fields.

I want to delete rows.

I want to insert rows.

Here's all the stuff we've got:

get, set, array_get, array_get_with_nulls, exists, delete, count, foreach, sort, type, import, import_postgres_result, export, fields, fieldtype, needs_quoting, names, reset, destroy, statistics, write_tabsep, or read_tabsep, or one of the registered methods:





tclsh8.4 test-server.tcl



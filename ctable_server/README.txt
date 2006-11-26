
$Id$

This is a server for ctables.  What's cool about it is on the server side there
is one piece of code for serving any ctables you want to serve.  On the client
side, once you've declared the ctable, you use it almost exactly as you'd
use a ctable in your own process' address space.

When you start the server you load up all of the ctable creators you want to 
support and then register them.  Clients can then create tables on the server 
using those ctable creators>

Alternatively or simultaneously, you can precreate your ctables on the server,
load them from your database, etc, and register the ctables themselves for 
remote access.

Here's all the ctable methods that work identically:

    get
    set
    array_get
    array_get_with_nulls
    exists
    delete
    count
    type
    fields
    fieldtype
    needs_quoting
    names
    reset
    destroy
    statistics

Here are all the ones that don't work or only partially work or don't work
in quite the same way:

    foreach
    sort
    import
    import_postgres_result
    export
    write_tabsep
    read_tabsep




DESIGN NOTES

client/server searching, here you go. 

one way for search to work is, you will specify a reader proc that will get called with the socket/file to read from, and that proc is expected to read that socket/file until it sees \. and then return, not closing the file/socket

the other way will be like array_get or array_get_with_nulls






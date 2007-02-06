package require sttpx
package require sttp_client_postgres

namespace eval ::sttpx {
  # Helper routine to shortcut the business of creating a URI
  #
  # Eg: ::sttpx::connect_sql my_table {index} -cols {index name value}
  #
  proc connect_sql {table keys args} {
    lappend make ::sttp::make_sql_uri $table -keys $keys
    set uri [eval $make $args]
    return [connect $uri $keys]
  }
}

package provide sttpx_postgres 1.0

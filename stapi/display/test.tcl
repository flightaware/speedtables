package require sttp_display
package require sttp_debug
package require sttp_client_postgres

namespace eval ::sttp_display {
  proc dumper {args} {
    set text [join $args "\n"]
    regsub -all {\<} $text {\&lt;} text
    regsub -all {\>} $text {\&gt;} text
    puts stdout "<PRE>$text</PRE>"
    # flush stdout
  }
  ::sttp::debug_handler dumper

  proc display_test {table keys {cols {}}} {
    set ctable [::sttp::connect_sql $table $keys -cols $cols]
    STTPDisplay test -ctable $ctable -mode List
  
    foreach field [$ctable fields] {
      test field $field
    }
    test show
  }
}

proc sttp_display_test {} {
  if [catch {::sttp_display::display_test sc_ca_ctable_servers {table_name host}} err] {
    ::sttp_display::dumper $::errorInfo
  }
}

package provide sttp_display_test 1.0

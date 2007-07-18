package require st_display
package require st_debug
package require st_client_postgres

namespace eval ::stapi::display {
  proc dumper {args} {
    set text [join $args "\n"]
    regsub -all {\<} $text {\&lt;} text
    regsub -all {\>} $text {\&gt;} text
    puts stdout "<PRE>$text</PRE>"
    # flush stdout
  }
  ::stapi::debug_handler dumper

  proc display_test {table keys {cols {}}} {
    set ctable [::stapi::connect_sql $table $keys -cols $cols]
    STTPDisplay test -ctable $ctable -mode List
  
    foreach field [$ctable fields] {
      test field $field
    }
    test show
  }
}

proc stapi_display_test {} {
  if [catch {::stapi::display::display_test sc_ca_ctable_servers {table_name host}} err] {
    ::stapi::display::dumper $::errorInfo
  }
}

package provide st_display_test 1.0

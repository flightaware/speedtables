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

  proc display_test {sql_table keys {cols {}}} {
    set table [::stapi::connect_sql $sql_table $keys -cols $cols]
    STTPDisplay test -table $table -mode List
  
    foreach field [$table fields] {
      test field $field
    }
    test show
  }
}

proc stapi_display_test {} {
  if [catch {::stapi::display::display_test stapi_test {isbn}} err] {
    ::stapi::display::dumper $::errorInfo
  }
}

package provide st_display_test 1.13.12

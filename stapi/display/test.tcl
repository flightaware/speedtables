package require sttp_display
package require sttpx
package require sttp_debug
package require sttp_client_postgres

namespace eval ::sttp_display {
  proc dumper {args} {
    set text [join $args "\n"]
    regsub -all {\<} $text {\&lt;} text
    regsub -all {\>} $text {\&gt;} text
    puts stdout "<PRE>$text</PRE>"
    flush stdout
  }
  ::sttp::debug_handler dumper

  proc display_test {uri keys} {
    if ![string match *_key* $uri] {
      append uri [lindex {? &} [string match {*\?*} $uri]] _keys=[join $keys :]
    }
    dumper [list ::sttpx::connect $uri $keys]
    set ctable [::sttpx::connect $uri $keys]
    dumper [list STTPDisplay test -ctable $ctable -mode List]
    STTPDisplay test -ctable $ctable -mode List
  
    foreach field [$ctable fields] {
      test field $field
    }
    test show
  }
}

proc sttp_display_test {} {
  if [catch {::sttp_display::display_test sql:///sc_ca_ctable_servers {table_name host}} err] {
    ::sttp_display::dumper $::errorInfo
  }
}

package provide sttp_display_test 1.0

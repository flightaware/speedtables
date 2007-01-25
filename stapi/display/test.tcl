package require sttp_display
package require sttp_debug
package require sttp_client_pgsql
package provide sttp_display_test 1.0

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
    dumper [list STTPDisplay test -uri $uri -keyfields $keys -mode List]
    STTPDisplay test -uri $uri -keyfields $keys -mode List
  
    foreach field [[::sttp_display::ctable $uri] fields] {
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

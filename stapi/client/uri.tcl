# Common routines for handling URIs

package require st_client
namespace eval stapi {

  #
  # uri_esc - escape a string for passing in a URI/URL
  #
  proc uri_esc {string {extra ""}} {
	  if {[catch {escape_string $string} result] == 0} {
		  # we were running under Apache Rivet and could use its existing command.
		  return $result
	  } else {
		  # TODO: this is not very good and is probably missing some cases.
		  foreach c [split "%\"'<> $extra" ""] {
			  scan $c "%c" i
			  regsub -all "\[$c]" $string [format "%%%02X" $i] string
		  }
		  return $string
	  }
  }

  #
  # uri_unesc - unescape a string after passing it through a URI/URL
  #
  proc uri_unesc {string} {
	  if {[catch {unescape_string $string} result] == 0} {
		  # we were running under Apache Rivet and could use its existing command.
		  return $result
	  } else {
		  # TODO: this is not very good and is probably missing some cases.
		  foreach c [split {\\$[} ""] {
			  scan $c "%c" i
			  regsub -all "\\$c" $string [format "%%%02X" $i] string
		  }
		  regsub -all {%([0-9A-Fa-f][0-9A-Fa-f])} $string {[format %c 0x\1]} string
		  return [subst $string]
	  }
  }

}

package provide st_client_uri 1.12.0

# vim: set ts=8 sw=4 sts=4 noet :

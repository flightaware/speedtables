#!/usr/local/bin/tclsh8.4

# $Id$

proc filename {chapter} {
  return [format ch%02d.html $chapter]
}

for {set chapter 1} {$chapter <= 15} {incr chapter} {
  if {$chapter > 1} {set prev [filename [expr $chapter - 1]]}
  set file [filename $chapter]
  if {$chapter < 15} {set next [filename [expr $chapter + 1]]}

  set links "<!-- %BEGIN LINKS% -->\n<div class=links>"
  if [info exists prev] {
    append links "<a href=\"$prev\">Back</a>"
  } else {
    append links "<span class=nolink>\\&nbsp;</span>"
  }
  append links "<a href=index.html>Index</a>"
  if [info exists next] {
    append links "<a href=\"$next\">Next</a>"
  } else {
    append links "<span class=nolink>\\&nbsp;</span>"
  }
  append links "</div>\n<!-- %END LINKS% -->"

  set fp [open $file r]
  set old [read $fp]
  close $fp

  set new $old
  regsub -all {<!-- %BEGIN LINKS% -->[^%]*<!-- %END LINKS% -->} $new $links new
  regsub -all {<!-- INSERT LINKS -->} $new $links new

  if {"$old" == "$new"} continue

  file rename -force $file $file.bak

  set fp [open $file w]
  puts -nonewline $fp $new
  close $fp
}

# sttp/display/display.tcl -- derived from diodisplay.tcl

# Copyright 2006 Superconnect

# diodisplay.tcl --

# Copyright 2002-2004 The Apache Software Foundation

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#	http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# $Id$
#

package require Itcl
package require form
package require sttp_display_util

#
# Only load ::csv:: if it's actually wanted.
#
namespace eval ::sttp_display {
  variable csv_loaded 0
  proc load_csv {} {
    variable csv_loaded
    if $csv_loaded {
      return
    }
    uplevel #0 package require csv
  }
}

catch { ::itcl::delete class STTPDisplay }

::itcl::class ::STTPDisplay {
    constructor {args} {
	eval configure $args
	load_response

	if ![info exists uri] {
	  if ![info exists ctable] {
	    return -code error "No registered ctable name or uri"
	  }
	  if ![info exists hosts] {
	    set hosts ""
	  }
	  set uri "cache://[join $hosts ":"]/$ctable"
	}
	if ![::sttp_display::connected $uri] {
	  if ![info exists keyfields] {
	    return -code error "No uri and no keyfields"
	  }
	  ::sttp_display::connect $uri $keyfields
	}

	if {[lempty $form]} {
	    set form [namespace which [::form #auto -defaults response]]
	}

	set document [env DOCUMENT_NAME]

	if {[info exists response(num)] \
	    && ![lempty $response(num)]} {
	    set pagesize $response(num)
	}

	read_css_file
    }

    destructor {
	if {$cleanup} { do_cleanup }
    }

    method destroy {} {
	::itcl::delete object $this
    }

    method debug {args} {
	set show $debug
	if {"[lindex $args 0]" == "-force"} {
	    set show 1
	    set args [lrange $args 1 end]
	}
	if {$show} {
	    eval ::sttp_display::debug $args
	}
    }

    ## Glue routines for the mismatch between DIO and remote ctables.
    ## The way DIO builds SQL that can be exposed outside DIO in assembling
    ## a request is used by DIODisplay. We have to make that more abstract

    ## New exposed configvars for STTPDisplay
    public variable ctable
    public variable uri
    public variable keyfields
    public variable hosts
    public variable debug 0

    ## Background configvars
    private variable ct_selection
    private variable ct_request

    private variable case

    #
    # configvar - a convenient helper for creating methods that can
    #  set and fetch one of the object's variables
    #
    method configvar {varName string {defval ""}} {
	if {"$string" == "$defval"} { return [set $varName] }
	configure -$varName $string
    }

    #
    # is_function - return true if name is known to be a function
    # such as Search List Add Edit Delete Details Main Save DoDelete Cancel
    # etc.
    #
    method is_function {name} {
	if {[lsearch $functions $name] > -1} { return 1 }
	if {[lsearch $allfunctions $name] > -1} { return 1 }
	return 0
    }

    #
    # do_cleanup - clean up our field subobjects, DIO objects, forms, and the 
    # like.
    #
    method do_cleanup {} {
	## Destroy all the fields created.
	foreach field $allfields { catch { $field destroy } }

	## Destroy the form object.
	catch { $form destroy }
    }

    #
    # handle_error - emit an error message
    #
    method handle_error {error} {
	puts "<B>An error has occurred processing your request</B>"
	puts "<PRE>"
	puts "$error"
	puts "</PRE>"
    }

    #
    # read_css_file - parse and read in a CSS file so we can
    #  recognize CSS info and emit it in appropriate places
    #
    method read_css_file {} {
	if {[lempty $css]} { return }
	if {[catch {open [virtual_filename $css]} fp]} { return }
	set contents [read $fp]
	close $fp
	if {[catch {array set tmpArray $contents}]} { return }
	foreach class [array names tmpArray] {
	    set cssArray([string toupper $class]) $tmpArray($class)
	}
    }

    #
    # get_css_class - figure out which CSS class we want to use.  
    # If class exists, we use that.  If not, we use default.
    #
    method get_css_class {tag default class} {

	# if tag.class exists, use that
	if {[info exists cssArray([string toupper $tag.$class])]} {
	    return $class
	}

	# if .class exists, use that
	if {[info exists cssArray([string toupper .$class])]} { 
	    return $class 
	}

	# use the default
  	return $default
    }

    #
    # parse_css_class - given a class and the name of an array, parse
    # the named CSS class (read from the style sheet) and return it as
    # key-value pairs in the named array.
    #
    method parse_css_class {class arrayName} {

	# if we don't have an entry for the specified class, give up
	if {![info exists cssArray($class)]} { 
	    return
	}

	# split CSS entry on semicolons, for each one...
	upvar 1 $arrayName array
	foreach line [split $cssArray($class) \;] {

	    # trim leading and trailing spaces
	    set line [string trim $line]

	    # split the line on a colon into property and value
	    lassign [split $line :] property value

	    # map the property to space-trimmed lowercase and
	    # space-trim the value, then store in the passed array
	    set property [string trim [string tolower $property]]
	    set value [string trim $value]
	    set array($property) $value
	}
    }

    #
    # button_image_src - return the value of the image-src element in
    # the specified class (from the CSS style sheet), or an empty
    # string if there isn't one.
    #
    method button_image_src {class} {
	set class [string toupper input.$class]
	parse_css_class $class array
	if {![info exists array(image-src)]} { 
	    return 
	}
	return $array(image-src)
    }

    # state - return a list of name-value pairs that represents the current
    # state of the query, which can be used to properly populate links
    # outside STTPDisplay.
    method state {} {
	set state {}
	foreach var {mode query by how sort rev num page} {
	    if [info exists response($var)] {
		lappend state $var $response($var)
	    }
	}
	return $state
    }

    method show {} {
	# if there's a mode in the response array, use that, else leave mode
	# as the default (Main unless caller specified otherwise)
	if {[info exists response(mode)]} {
	    set mode $response(mode)
	    if {[string match "*-*" $mode]} {
		set mode List
	    } elseif {[string match {*[+ ]*} $mode]} {
		set mode List
	        add_search_to_selection
	    }
	    set response(mode) $mode
	}

	# sanitize "by":
	# If it's empty, remove it.
	# If it's a label, change it to a field
	if [info exists response(by)] {
	  if {"$response(by)" == ""} {
	    unset response(by)
	  } elseif {[info exists NameTextMap($response(by))]
	    set response(by) $NameTextMap($response(by))
	  }
	}
  
	# if there was a request to generate a CSV file, generate it
	if {[info exists response(dd_csv)]} {
	    gencsvfile $response(dd_csv)
	    if $csvredirect {
		headers redirect $csvurl
		destroy
	        return
	    }
	}

	# if there is a style sheet defined, emit HTML to reference it
	if {![lempty $css]} {
	    puts "<LINK REL=\"stylesheet\" TYPE=\"text/css\" HREF=\"$css\">"
	}

	# put out the table header
	puts {<TABLE WIDTH="100%" CLASS="DIO">}
	puts "<TR CLASS=DIO>"
	puts {<TD VALIGN="center" CLASS="DIO">}

	# if mode isn't Main and persistentmain is set (the default),
	# use Main
	if {$mode != "Main" && $persistentmain} { 
	    Main 
	}

	if {![is_function $mode]} {
	    puts "<H2>Invalid function '$mode'</H2>"
	    puts "
		<P>This may be due to an error in an external link
		or in this web page. You may be able to use the back
		button in your browser to return to the previous page
		and try this query again. If you continue to get this
		error, please contact the operator of this system.</P>"
	    puts "</TD>"
	    puts "</TR>"
	    puts "</TABLE>"
	    return
	}

	if {[catch [list $this $mode] error]} {
	    global errorInfo
	    if !$trap_errors {
		puts "</TD>"
		puts "</TR>"
		puts "</TABLE>"
		if {$cleanup} { destroy }
		error $error $errorInfo
	    }
	    puts "<H2>Internal Error</H2>"
	    puts "<pre>$errorInfo</pre>"
	    handle_error "$this $mode => $error"
	}

	puts "</TD>"
	puts "</TR>"
	puts "</TABLE>"

	if {$cleanup} { destroy }
    }

    method showview {} {
	puts {<TABLE CLASS="DIOView">}
	set row 0
	foreach field $fields {
	    $field showview [lindex {"" "Alt"} $row]
	    set row [expr 1 - $row]
	}
	puts "</TABLE>"
    }

    protected method hide_hidden_vars {f} {
	foreach var [array names hidden] {
	    $f hidden $var -value $hidden($var)
        }
    }

    protected method hide_selection {f {op ""} {val ""}} {
	if {"$op" == "+"} {
	    set all 1
	} else {
	    set all 0
	}
	set selection [get_selection $all]
	if {"$op" == "-"} {
	    set first [lsearch $selection $val]
	    if {$first != -1} {
		set selection [lreplace $selection $first $first]
	    }
	}
	$f hidden ct_sel -value $selection
    }

    protected method hide_cgi_vars {f args} {
	foreach cgi_var {mode query by how sort rev num} {
	    if {[lsearch $args $cgi_var] == -1} {
	        if [info exists response($cgi_var)] {
		    set val $response($cgi_var)
		    if {"$cgi_var" == "mode"} {
			if {"$val" == "+" || "$val" == "-"} {
			    if [info exists response(query)] {
				set val Search
			    } else {
				set val List
			    }
			}
		    }
	            $f hidden $cgi_var -value $val
	        }
	    }
	}
    }

    #
    # showform - emit a form for inserting a new record
    #
    # response(by) will contain whatever was in the "where" field
    # response(query) will contain whatever was in the "is" field
    #
    method showform {} {
	get_field_values array

	set save [button_image_src DIOFormSaveButton]
	set cancel [button_image_src DIOFormCancelButton]

	$form start -method post
	hide_hidden_vars $form
	hide_selection $form
	$form hidden mode -value Save
	if [info exists response(mode)] {
	    $form hidden DIODfromMode -value $response(mode)
	}
	$form hidden DIODkey -value [::sttp_display::makekey $uri array]
	puts {<TABLE CLASS="DIOForm">}

	# emit the fields for each field using the showform method
	# of the field.  if they've typed something into the
	# search field and it matches one of the fields in the
	# record (and it should), put that in as the default
	foreach field $fields {
	    set name [$field name]
	    if [info exists alias($name)] { continue }
	    if {[info exists response(by)] && $response(by) == $name} {
		if {![$field readonly] && $response(query) != ""} {
		    $field value $response(query)
		}
	    }
	    $field showform
	}
	puts "</TABLE>"

	puts "<TABLE CLASS=DIOFormSaveButton>"
	puts "<TR CLASS=DIOFormSaveButton>"
	puts "<TD CLASS=DIOFormSaveButton>"
	if {![lempty $save]} {
	    $form image save -src $save -class DIOFormSaveButton
	} else {
	    $form submit save.x -value "Save" -class DIOFormSaveButton
	}
	puts "</TD>"
	puts "<TD CLASS=DIOFormSaveButton>"
	if {![lempty $cancel]} {
	    $form image cancel -src $cancel -class DIOFormSaveButton
	} else {
	    $form submit cancel.x -value "Cancel" -class DIOFormCancelButton
	}
	puts "</TD>"
	puts "</TR>"
	puts "</TABLE>"

	$form end
    }

    method page_buttons {end {count 0}} {
	if {$pagesize <= 0} { return }

	if {![info exists response(page)]} { set response(page) 1 }

	set pref DIO$end
	if {!$count} {
	  set count [ct_result -countOnly]
	}

	set pages [expr ($count + $pagesize - 1) / $pagesize]

	if {$pages <= 1} {
	  return
	}

	set first [expr $response(page) - 3]
	if {$first > $pages - 7} {
	  set first [expr $pages - 7]
	}
        if {$first > 1} {
	  lappend pagelist 1 1
	  if {$first > 10} {
	    lappend pagelist ".." 0
	    set mid [expr $first / 2]
	    if {$mid > 20} {
	      set quarter [expr $mid / 2]
	      lappend pagelist $quarter $quarter
	      lappend pagelist ".." 0
	    }
	    lappend pagelist $mid $mid
	    if {$first - $mid > 10} {
	      lappend pagelist ".." 0
	      set quarter [expr ( $first + $mid ) / 2]
	      lappend pagelist $quarter $quarter
	    }
	  }
	  if {$first > 3} {
	    lappend pagelist ".." 0
	  } elseif {$first > 2} {
	    lappend pagelist 2 2
	  }
	} else {
	  set first 1
	}
	set last [expr $response(page) + 3]
	if {$last < 7} {
	  set last 7
	}
	if {$last > $pages} {
	  set last $pages
	}
	for {set i $first} {$i <= $last} {incr i} {
	  lappend pagelist $i $i
	}
	if {$last < $pages} {
	  if {$last < $pages - 2} {
	    lappend pagelist ".." 0
	  } elseif {$last < $pages - 1} {
	    incr last
	    lappend pagelist $last $last
	  }
	  if {$last < $pages - 10} {
	    set mid [expr ( $pages + $last ) / 2]
	    if {$last < $mid - 10} {
	      set quarter [expr ( $mid + $last ) / 2]
	      lappend pagelist $quarter $quarter
	      lappend pagelist ".." 0
	    }
	    lappend pagelist $mid $mid
	    lappend pagelist ".." 0
	    if {$mid < $pages - 20} {
	      set quarter [expr ( $mid + $pages ) / 2]
	      lappend pagelist $quarter $quarter
	      lappend pagelist ".." 0
	    }
	  }
	  lappend pagelist $pages $pages
	}

	foreach {n p} $pagelist {
	  if {$p == 0 || $p == $response(page)} {
	    lappend navbar $n
	  } else {
	    set html {<A HREF="}
	    set list {}
	    foreach var {mode query by how sort rev num} {
	      if {[info exists response($var)]} {
	        lappend list $var $response($var)
	      }
	    }
	    lappend list page $p
	    append html [document $list]
	    append html "\">$n</A>"
	    lappend navbar $html 
	  }
	}

	if {"$end" == "Bottom"} {
	  puts "<BR/>"
	}
	set class [get_css_class TABLE DIONavButtons ${pref}NavButtons]
	puts "<TABLE WIDTH=\"100%\" CLASS=\"$class\">"
	puts "<TR CLASS=\"$class\">"
        puts "<TD CLASS=\"$class\">"
	puts "<FONT SIZE=-1>"
	if {"$end" == "Top"} {
	  puts "$count rows, go to page"
	} else {
	  puts "Go to page"
	}
	foreach link $navbar {
	  puts "$link&nbsp;"
	}
        puts "</FONT>"
	puts "</TD>"
	if {"$end" == "Top" && $pages>10} {
	  set f [::form #auto]
	  $f start -method get
	  hide_hidden_vars $f
	  hide_selection $f
	  hide_cgi_vars $f
	  puts "<TD ALIGN=RIGHT>"
	  puts "<FONT SIZE=-1>"
	  puts "Jump directly to"
	  $f text page -size 4 -value $response(page)
	  $f submit submit -value "Go"
          puts "</FONT>"
	  puts "</TD>"
	  $f end
	}
	puts "</TR>"
	puts "</TABLE>"
	if {"$end" == "Top"} {
	  puts "<BR/>"
	}
    }


    method rowheader {{total 0}} {
	set fieldList $fields
	if {![lempty $rowfields]} { set fieldList $rowfields }

	set rowcount 0

	puts <P>

	if {$topnav} { page_buttons Top $total }

	puts {<TABLE BORDER WIDTH="100%" CLASS="DIORowHeader">}
	puts "<TR CLASS=DIORowHeader>"
        set W [expr {100 / [llength $fieldList]}]
	foreach field $fieldList {
	    set name [$field name]
	    set text [$field text]
	    set sorting $allowsort
	    ## If sorting is turned off, or this field is not in the
	    ## sortfields, we don't display the sort option.
	    if {$sorting && ![lempty $sortfields]} {
		if {[lsearch $sortfields $field] < 0} {
		    set sorting 0
	        }
	    }
if 0 {
	    if {$sorting && [info exists response(sort)]} {
		if {"$response(sort)" == "$name"} {
		    set sorting 0
	        }
	    }
}
	    if {$sorting && [info exists alias($name)]} {
		set sorting 0
	    }

	    regsub -all $labelsplit $text "<BR>" text
	    set ttl ""
	    set ttl_text $text
	    if [info exists hovertext($name)] {
		set ttl " title=\"$hovertext($name)\""
		set ttl_text "<span$ttl>$text</span>"
	    }
	    if {!$sorting} {
		set html $ttl_text
	    } else {
	        set html ""
	        set list {}
		foreach var {mode query by how num} {
		    if {[info exists response($var)]} {
			lappend list $var $response($var)
			set sep "&"
		    }
		}
	        lappend list sort $name
		set a_attr ""
		if {[info exists response(sort)] && "$response(sort)" == "$name"} {
		    set rev 1
		    if {[info exists response(rev)]} {
			set rev [expr 1 - $response(rev)]
		    }
		    lappend list rev $rev
		    append html "$ttl_text&nbsp;"

		    set desc $rev
		    if [info exists order($name)] {
			switch -glob -- [string tolower $order($name)] {
			    desc* {
				set desc [expr 1 - $desc]
			    }
			}
		    }
		    set text [lindex $arrows $desc]
		    set a_attr " class=DIOArrow"
		}
		append html {<A HREF="}
		append html [document $list]
		append html "\"$a_attr$ttl>$text</A>"
	    }
	    set class [get_css_class TH DIORowHeader DIORowHeader-$name]
	    puts "<TH CLASS=\"$class\" WIDTH=$W%>$html</TH>"
	}

	if {![lempty $rowfunctions] && "$rowfunctions" != "-"} {
	  puts {<TH CLASS="DIORowHeaderFunctions" WIDTH=0%>&nbsp;</TH>}
        }
	puts "</TR>"
    }

    method showrow {arrayName} {
	upvar 1 $arrayName a

	incr rowcount
	set alt ""
	if {$alternaterows && ![expr $rowcount % 2]} { set alt Alt }

	set fieldList $fields
	if {![lempty $rowfields]} { set fieldList $rowfields }

	puts "<TR CLASS=\"DIORowField$alt\">"
	foreach field $fieldList {
	    set name [$field name]
	    set column $name
	    if [info exists alias($name)] {
		set column $alias($name)
	    }
	    set class [get_css_class TD DIORowField$alt DIORowField$alt-$name]
	    set text ""
	    if {[info exists a($column)]} {
	        set text $a($column)
	    }
	    if [info exists filters($name)] {
		if {[info exists filtercol($name)]
		 && [info exists a($filtercol($name))]} {
		    set text [$filters($name) $text $a($filtercol($name))]
		} else {
		    set text [$filters($name) $text]
		}
	    }
	    if ![string length $text] {
		set text "&nbsp;"
	    }
	    set attr NOWRAP
	    if [info exists attributes($name)] {
		append attr " $attributes($name) "
	        if [regsub -nocase { +wrap +} " $attr " { } attr] {
		    set attr $attributes($name)
		}
	        set attr [string trim $attr]
	    }
	    puts "<TD CLASS=\"$class\" $attr>$text</TD>"
	}

	if {![lempty $rowfunctions] && "$rowfunctions" != "-"} {
	    set f [::form #auto]
	    $f start -method get
	    puts "<TD NOWRAP CLASS=\"DIORowFunctions$alt\">"
	    hide_hidden_vars $f
	    hide_selection $f
	    $f hidden query -value [::sttp_display::makekey $uri a]
	    if {[llength $rowfunctions] > 2} {
	      $f select mode -values $rowfunctions -class DIORowFunctionSelect$alt
	      $f submit submit -value "Go" -class DIORowFunctionButton$alt
	    } else {
	      foreach func $rowfunctions {
	        $f submit mode -value $func -class DIORowFunctionButton$alt
	      }
	    }
	    puts "</TD>"
	    $f end
	}

	puts "</TR>"
    }

    method rowfooter {{total 0}} {
	puts "</TABLE>"

	if {$bottomnav} { page_buttons Bottom $total }
    }

    ## Define a new function.
    method function {name} {
	lappend allfunctions $name
    }

    ## Define a field in the object.
    method field {name args} {
	import_keyvalue_pairs data $args

	set class STTPDisplayField
	if {[info exists data(type)]} {
	    if {![lempty [::itcl::find classes *STTPDisplayField_$data(type)]]} {
		set class STTPDisplayField_$data(type)
	    }
	}

	set field [
	    eval [
		list $class #auto -name $name -display $this -form $form
	    ] $args
	]
	lappend fields $field
	lappend allfields $field
 	
	set FieldNameMap($name) $field
	set NameTextMap([$field text]) $name
    }

    private method make_limit_selector {values _selector {_array ""}} {
	if ![info exists limit] { return 0 }

	upvar 1 $_selector selector
	if {"$_array" != ""} {
	    upvar 1 $_array array
	}
	
        foreach val $values field [::sttp_display::keyfield $uri] {
	    lappend selector [list = $field $val]
        }
	foreach {key val} $limit {
	    regsub {^-} $key "" key
	    lappend selector [list = $key $val]
	    set array($key) $val
	}
	return 1
    }

    method fetch {key arrayName} {
	upvar 1 $arrayName array
	if [make_limit_selector $key selector] {
	    set result [::sttp_display::search $uri -compare $selector -array_with_nulls array]
	} else {
	    set result [::sttp_display::fetch $uri $key array]
	}
	return $result
    }

    method store {arrayName} {
	upvar 1 $arrayName array
	if [make_limit_selector {} selector array] {
	    if ![::sttp_display::search $uri -compare $selector -key key] {
		return 0
	    }
	}
	return [::sttp_display::store $uri array]
    }

    method delete {key} {
	if [make_limit_selector $key selector] {
	    if ![::sttp_display::search $uri -compare $selector -getkey key] {
		return 0
	    }
	} else {
	    set key [::sttp_display::makekey $uri array]
	}
	return [::sttp_display::delete $uri $key]
    }

    method pretty_fields {list} {
	set fieldList {}
	foreach field $list {
	    lappend fieldList [$field text]
	}
	return $fieldList
    }

    method set_field_values {arrayName} {
	upvar 1 $arrayName array

	# for all the elements in the specified array, try to invoke
	# the element as an object, invoking the method "value" to
	# set the value to the specified value
	foreach name [array names array] {
	    if [info exists FieldNameMap($name)] {
	        $FieldNameMap($name) configure -value $array($name)
	    }
	}
    }

    method get_field_values {arrayName} {
	upvar 1 $arrayName array

	foreach field $allfields {

            # for some reason the method for getting the value doesn't
	    # work for boolean values, which inherit STTPDisplayField,
	    # something to do with configvar
	    #set array($field) [$field value]
	    set t [$field type]
	    set v [$field value]
	    set n [$field name]
	    if {"$v" == "" && [info exists blankval($name)]} {
		if {"$blankval($name)" != "$v"} continue
	    }
	    set array($n) $v
	}
    }

    method make_request {_request} {
	upvar 1 $_request request
	set request(-uri) $uri
    }

    method set_limit {_request {selector {}}} {
	upvar 1 $_request request
	if [info exists request(-compare)] {
	    set request(-compare) [concat $request(-compare) $selector]
	} else {
	    set request(-compare) $selector
	}
	make_limit_selector {} request(-compare)
	if [llength $request(-compare)] {
	    return 1
        }
	unset request(-compare)
	return 0
    }

    method set_order {_request} {
	upvar 1 $_request request
	if {"[set sort [request_to_sort]]" != ""} {
	    set request(-sort) $sort
	}
    }

    method set_page {_request} {
	upvar 1 $_request request
	set recno [get_offset]
	if {$recno > 0} {
	    set request(-offset) $recno
	}
	if {$pagesize > 0} {
	    set request(-limit) $pagesize
	}
    }

    method gencsvfile {selector} {
	if {"$csvfile" == ""} {
	    return
	}

        ::sttp_display::load_csv

	make_request request
	set_limit request
	set_order request

	if [catch {set fp [open $csvfile w]} err] {
	    $r destroy
	    return
	}

	set columns {}

	foreach name $fields {
	    lappend columns $name
	    set label [$name text]
	    regsub -all { *<[^>]*> *} $label " " label
	    lappend textlist $label
	}
        if [info exists textlist] {
	    puts $fp [::csv::join $textlist]
	}

	::sttp_display::perform request -array_with_nulls a -key k -code {
	    if {![llength $columns]} {
		set columns [array names a]
		puts $fp [::csv::join $columns]
	    }
	    set list {}
	    foreach n $columns {
		if [info exists a($n)] {
		    set col $a($n)
		    if [info exists csvfilters($n)] {
			set col [$csvfilters($n) $col]
		    }
		    lappend list $col
		} else {
		    lappend list ""
	        }
	    }
	    puts $fp [::csv::join $list]
	}

	close $fp

	$r destroy
    }

    method showcsvform {query} {
	$form start -method get
	puts "<TR CLASS=DIOForm><TD CLASS=DIOForm VALIGN=MIDDLE WIDTH=100%>"
	# save hidden vars
	hide_hidden_vars $form
	# save form vars so state isn't lost
	foreach {n v} [state] {
	    $form hidden $n -value $v
        }
	# save search
	hide_selection $form
	# save query for generation
	$form hidden ct_csv -value $query
        if $csvredirect {
	    set csvlabel "Download CSV file"
	} else {
	    set csvlabel "Generate CSV file"
	}
	$form submit submit -value $csvlabel \
			-class DIOMainSubmitButton

	if [file exists $csvfile] {
	    if ![catch {file stat $csvfile st}] {
		if $csvredirect {
		    puts "Previous:&nbsp;"
		}
		set filename $csvfile
		regsub {^.*/} $filename "" filename
		puts "<A HREF=\"$csvurl\">$filename</A>:"
		puts "$st(size) bytes,"
		puts [clock format $st(mtime) -format "%d-%b-%Y %H:%M:%S"]
	    }
	}

	puts "</TD></TR>"
	$form end
    }

    method DisplayRequest {selector} {
	make_request request
	set partial [set_limit request $selector]

	if {!$partial} {
	    if {$rows} {
	        set total $rows
	    } else {
	        set total [::sttp_display::count $uri]
	    }
	} else {
	    set total [::sttp_display::perform request -countOnly 1]
	}

	if {$total <= [get_offset]} {
	    puts "Could not find any matching records."
	    return
	}

	rowheader $total

	set_order request
	set_page request
	::sttp_display::perform request -array_with_nulls a -code { showrow a } -debug $debug

	rowfooter $total

	if {"$csvfile" != "" && "$csvurl" != ""} {
	    showcsvform $query
	}
    }

    method Main {} {
	puts "<TABLE BORDER=0 WIDTH=100% CLASS=DIOForm>"

	display_selection {"&nbsp;"} {}

	set skipfunctions {}
	if {[lsearch $functions Search] >= 0} {
	    foreach f "Edit Delete" {
	        if {[lsearch $functions $f] >= 0
		&& [lsearch $rowfunctions $f] >= 0} {
		    lappend skipfunctions $f
		}
	    }
	}

	puts "<TR CLASS=DIOForm>"
	puts "<TD CLASS=DIOForm ALIGN=LEFT VALIGN=MIDDLE WIDTH=1% NOWRAP>"

	set selfunctions {}
	foreach f $functions {
	    if {"$f" != "List"} {
	        if {[lsearch $skipfunctions $f] == -1} {
		    lappend selfunctions $f
		}
	    } else {
	    	set listform [::form #auto]
		puts "<DIV STYLE='display:none'>"
	    	$listform start -method get
		puts "</DIV>"
		hide_hidden_vars $listform
		# hide_selection $listform
	    	$listform hidden mode -value "List"
	    	$listform hidden query -value ""
	    	$listform submit submit -value "Show All" \
			-class DIORowFunctionButton
		puts "<DIV STYLE='display:none'>"
	    	$listform end
		puts "</DIV>"
	    }
	}
	puts "</TD>"
	puts "<TD CLASS=DIOForm ALIGN=LEFT VALIGN=MIDDLE WIDTH=1% NOWRAP>"

	puts "<DIV STYLE='display:none'>"
	$form start -method get
	puts "</DIV>"
	puts "&nbsp;"

	hide_hidden_vars $form
	hide_selection $form

        if {[llength $selfunctions] > 2} {
	  $form select mode -values $selfunctions -class DIOMainFunctionsSelect
          puts "where"
	} else {
	  puts "Select:"
	}

	set useFields $fields
	if {![lempty $searchfields]} { set useFields $searchfields }

	if {![info exists response(mode)] ||
	     "$response(mode)" == "List" ||
	     "$response(mode)" == "Search"} {
	    # filtered fields aren't searchable, because the displayed
	    # value doesn't match the db value
	    # alias fields aren't searchable
	    set searchable {}
	    foreach field $useFields {
	        set name [$field name]
	        if {
		  ![info exists filters($name)] ||
		  [info exists unfilters($name)] ||
		  [string match *_ok $filters($name)]
		} {
	            if ![info exists alias($name)] {
			lappend searchable $field
		    }
		}
            }
        } else {
	    set searchable $useFields
	}
	set field_names [pretty_fields $searchable]
	set field_names [concat "-column-" $field_names]
	$form select by -values $field_names -class DIOMainSearchBy

	puts "</TD>"
	puts "<TD CLASS=DIOForm ALIGN=LEFT VALIGN=MIDDLE WIDTH=1% NOWRAP>"
	if [string match {*[Ss]earch*} $selfunctions] {
	  $form select how -values {"=" "<" "<=" ">" ">=" "<>"}
	} else {
          puts "is"
	}

	puts "</TD>"
	puts "<TD CLASS=DIOForm ALIGN=LEFT VALIGN=MIDDLE WIDTH=1% NOWRAP>"
        if [info exists response(query)] {
	  $form text query -value $response(query) -class DIOMainQuery
	} else {
	  $form text query -value "" -class DIOMainQuery
	}

	puts "</TD>"
	puts "<TD CLASS=DIOForm ALIGN=LEFT VALIGN=MIDDLE WIDTH=100% NOWRAP>"

	if [string match {*[sS]earch*} $selfunctions] {
	  display_add_button $form
	}

        if {[llength $selfunctions] > 2} {
	  $form submit submit -value "GO" -class DIOMainSubmitButton
	} else {
	  foreach f $selfunctions {
	    $form submit mode -value $f -class DIOMainSubmitButton
	  }
	}

	if {![lempty $numresults]} {
	    puts "</TD></TR>"
	    puts "<TR CLASS=DIOForm><TD CLASS=DIOForm>Results per page: "
	    $form select num -values $numresults -class DIOMainNumResults
	}

	puts "</TD></TR>"

	puts "<DIV STYLE='display:none'>"
	$form end
	puts "</DIV>"
	puts "</TABLE>"
    }

    protected method parse_order {name list reverse} {
	set descending 0
	foreach word $list {
	    if [info exists nextvar] {
		set $nextvar $word
		unset nextvar
		continue
	    }
	
	    switch -glob -- $word {
		asc* { set descending 0 }
		desc* { set descending 1 }
		null* { set nextvar null }
	    }
	}

# ctables doesn't handle this yet
#	if [info exists null] {
#	    set field "COALESCE($field,$null)"
#	}

	if {$reverse} {
	    set descending [expr 1 - $descending]
	}
	if $descending {
	    set name -$name
	}

        return $name
    }

    method request_to_sort {} {
	if {[info exists response(sort)] && ![lempty $response(sort)]} {
	    set name $response(sort)
	    if [info exists FieldNameMap($name)] {
		set rev 0
	        if {[info exists response(rev)] && $response(rev)} {
		    set rev 1
		}

	        set ord ascending
	        if [info exists order($name)] {
		    set ord $order($name)
		}

		return [list [parse_order $name $ord $rev]]
	    } else {
		unset response(sort)
	    }
	}

	if {![lempty $defaultsortfield]} {
	    return [list $defaultsortfield]
	}

	return {}
    }

    method get_offset {} {
	if {$pagesize <= 0} { return 0 }
	if {![info exists response(page)]} { return 0 }
	return [expr ($response(page) - 1) * $pagesize]
    }

    protected method display_selection {precells postcells} {
	set selection [get_selection 0]
	if {![llength $selection]} {
	    return
	}
	set span [expr {4 + [llength $precells] + [llength $postcells]}]
	puts "<TR><TD CLASS=DIOFormHeader COLSPAN=$span>"
	puts "<font color=#444444><b>Current filters:</b></font>"
	puts "</TD></TR>"
	foreach search $selection {
	    foreach {how col what} $search { break }
	    if {[lsearch $allfields $col] == -1} {
		continue
	    }
	    puts "<TR CLASS=DIOSelect>"
	    set f [::form #auto]
	    puts "<DIV STYLE='display:none'>"
	    $f start -method get
	    puts "</DIV>"
	    hide_hidden_vars $f
	    hide_cgi_vars $f mode
	    hide_selection $f - $search
	    if {[string match "*-*match*" $how]} {
		set how "is not like"
	    } elseif {[string match "*match*" $how]} {
		set how "is like"
	    }

	    foreach cell $precells {
		puts "<TD CLASS=DIOSelect WIDTH=1%>$cell</TD>"
	    }
	    foreach \
		cell [list [$col text] $how $what] \
		align {right middle left} \
	    {
		puts "<TD CLASS=DIOSelect ALIGN=$align WIDTH=1%>$cell</TD>"
	    }
	    puts "<TD CLASS=DIOSelect WIDTH=100% ALIGN=LEFT>"
	    $f submit mode -value "-" -class DIOForm
	    puts "</TD>"
	    foreach cell $postcells {
		puts "<TD CLASS=DIOSelect>$cell</TD>"
	    }
	    puts "<DIV STYLE='display:none'>"
	    $f end
	    puts "</DIV>"
	    puts "</TR>"
	}
	puts "<TR><TD CLASS=DIOFormHeader COLSPAN=$span>"
	puts ""
	puts "</TD></TR>"
    }

    protected method display_add_button {f} {
	$f submit mode -value "+" -class DIOForm
    }

    protected method add_search_to_selection {} {
	set search_list [get_selection 1]
	array unset ct_selection
    }

    protected method get_selection {searching} {
	if [info exists ct_selection($searching)] {
	    return $ct_selection($searching)
	}

	if ![info exists search_list] {
	    if [info exists response(ct_sel)] {
	        set search_list $response(ct_sel)
		if {[llength $search_list] == 3
		 && [llength [lindex $search_list 0]] == 1} {
		    set search_list [list $search_list]
		}
	    } else {
	        set search_list {}
	    }
	}
	set ct_selection(0) $search_list
	if !$searching {
	    return $search_list
	}
	set new_list $search_list

	if [info exists response(by)] {
	    set name $response(by)

	    set what $response(query)

	    set how "="
	    if {[info exists response(how)] && [string length $response(how)]} {
	        set how $response(how)
	    }

	    if {[string match {*[*?]*} $what]} {
		if {"$how" == "="} {
		    set how "match"
	        } elseif {"$how" == "<>"} {
		    set how "-match"
		}
	    }
	    if {[string match "*like*" $how] || [string match "*match*" $how]} {
		switch -glob -- $how {
		    *not* { set how "-" }
		    -*    { set how "-" }
		    default { set how "" }
	        }
	    	if {[info exists case($name)]} {
		    append how [
			string tolower [string index $case($name) 0]
		    ]
		}
		append how match
	    }

	    set search [list $how $name $what]
	    if {[lsearch $new_list $search] == -1} {
	        lappend new_list [list $how $name $what]
	    }
	}
	set ct_selection(1) $new_list
	return $new_list
    }

    method Search {} {
	display_request_with_selection [get_selection 1]
    }

    method List {} {
	display_request_with_selection [get_selection 0]
    }

    protected method display_request_with_selection {selection} {
	set request {}
	foreach target $selection {
	    foreach {how column what} $target { break }

	    if [info exists unfilters($column)] {
	        set what [$unfilters($column) $what]
	    }

	    lappend request [list $how $column $what]
	}
	DisplayRequest $request
    }

    method Add {} {
	showform
    }

    method Edit {} {
	if {![fetch $response(query) array]} {
	    puts "That record does not exist in the database."
	    return
	}

	set_field_values array

	showform
    }

    ##
    ## When we save, we want to set all the fields' values and then get
    ## them into a new array.  We do this because we want to clean any
    ## unwanted variables out of the array but also because some fields
    ## have special handling for their values, and we want to make sure
    ## we get the right value.
    ##
    method Save {} {
	if {[info exists response(cancel.x)]} {
	    Cancel
	    return
	}

	## We need to see if the key exists.  If they are adding a new
	## entry, we just want to see if the key exists.  If they are
	## editing an entry, we need to see if they changed the keyfield
	## while editing.  If they didn't change the keyfield, there's no
	## reason to check it.
        set adding [expr {$response(DIODfromMode) == "Add"}]
	if {$adding} {
	    set key [::sttp_display::makekey $uri response]
	    ::sttp_display::fetch $uri $key a
	} else {
	    set key $response(DIODkey)
	    set newkey [::sttp_display::makekey $uri response]

	    ## If we have a new key, and the newkey doesn't exist in the
	    ## database, we are moving this record to a new key, so we
	    ## need to delete the old key.
	    if {$key != $newkey} {
		if {![fetch $newkey a]} {
		    delete $key
		}
	    }
	}

	if {[array exists a]} {
	    puts "That record ($key) already exists in the database."
	    return
	}

	set_field_values response
	get_field_values storeArray

	# Don't try and write readonly values.
        foreach field [array names storeArray] {
	  if [$field readonly] {
	    unset storeArray($field)
	  }
        }

	# Because an empty string is not EXACTLY a null value and not always
	# a legal value, if adding a new row and the array element is empty,
	# remove it from the array -- PdS Jul 2006
	if $adding {
	  foreach {n v} [array get storeArray] {
	    if {"$v" == ""} {
	      unset storeArray($n)
	    }
	  }
	}

	store storeArray
	headers redirect [document]
    }

    protected method document {{extra {}}} {
        set url $document
        set ch "?"
	foreach {n v} $extra {
	    append url $ch $n = $v
	    set ch "&"
        }
	foreach {n v} [array get hidden] {
	    append url $ch $n = $v
	    set ch "&"
        }
	set selection [get_selection 0]
	if [llength $selection] {
	    append url $ch ct_sel = $selection
	    set ch "&"
	}
	return $url
    }

    method Delete {} {
	if {![fetch $response(query) array]} {
	    puts "That record does not exist in the database."
	    return
	}

	if {!$confirmdelete} {
	    DoDelete
	    return
	}

	puts "<CENTER>"
	puts {<TABLE CLASS="DIODeleteConfirm">}
	puts "<TR CLASS=DIODeleteConfirm>"
	puts {<TD COLSPAN=2 CLASS="DIODeleteConfirm">}
	puts "Are you sure you want to delete this record from the database?"
	puts "</TD>"
	puts "</TR>"
	puts "<TR CLASS=DIODeleteConfirmYesButton>"
	puts {<TD ALIGN="center" CLASS="DIODeleteConfirmYesButton">}
	set f [::form #auto]
	$f start -method post
	hide_hidden_vars $f
	hide_selection $f
	$f hidden mode -value DoDelete
	$f hidden query -value $response(query)
	$f submit submit -value Yes -class DIODeleteConfirmYesButton
	$f end
	puts "</TD>"
	puts {<TD ALIGN="center" CLASS="DIODeleteConfirmNoButton">}
	set f [::form #auto]
	$f start -method post
	hide_hidden_vars $f
	hide_selection $f
	$f submit submit -value No -class "DIODeleteConfirmNoButton"
	$f end
	puts "</TD>"
	puts "</TR>"
	puts "</TABLE>"
	puts "</CENTER>"
    }

    method DoDelete {} {
	if [catch {delete $response(query)} err] {
	  error "delete $response(query) => $err"
	}

	headers redirect [document]
    }

    method Details {} {
	if {![fetch $response(query) array]} {
	    puts "That record does not exist in the database."
	    return
	}

	set_field_values array

	showview
    }

    method Cancel {} {
	headers redirect [document]
    }

    ###
    ## Define variable functions for each variable.
    ###

    private method names2fields {names} {
	set fields {}
	foreach name $names {
	    if ![info exists FieldNameMap($name)] {
		return -code error "Field $name does not exist."
	    }
	    lappend fields $FieldNameMap($name)
	}
	return $fields
    }

    protected method fields2names {fields} {
	set names {}
	foreach field $fields {
	    lappend names [$field name]
	}
	return $fields
    }

    method fields {{list ""}} {
	if {[lempty $list]} { return [fields2names $fields] }
	set fields [names2fields $list]
    }

    method searchfields {{list ""}} {
	if {[lempty $list]} { return [fields2names $searchfields] }
	set searchfields [names2fields $list]
    }

    method rowfields {{list ""}} {
	if {[lempty $list]} { return [fields2names $rowfields] }
	set rowfields [names2fields $list]
    }

    method alias {name {value ""}} {
	if [string length $value] {
	    set alias($name) $value
	} else {
	    if [info exists alias($name)] {
		set value $alias($name)
	    }
	}
	return $value
    }

    method filter {name {value ""}} {
	if [string length $value] {
	    set f [uplevel 1 [list namespace which $value]]
	    if {"$f" == ""} {   
		return -code error "Unknown filter $value"
	    }
	    set filters($name) $f
	} else {
	    if [info exists filters($name)] {
		set value $filters($name)
	    }
	}
	return $value
    }

    method smartfilter {name filter column} {
	set f [uplevel 1 [list namespace which $filter]]
	if {"$f" == ""} {
	    return -code error "Unknown filter $filter"
	}
	set filters($name) $f
	set filtercol($name) $column
    }

    method csvfilter {name {value ""}} {
	if [string length $value] {
	    set f [uplevel 1 [list namespace which $value]]
	    if {"$f" == ""} {
		return -code error "Unknown filter $value"
	    }
	    set csvfilters($name) $f
	} else {
	    if [info exists csvfilters($name)] {
		set value $csvfilters($name)
	    }
	}
	return $value
    }

    method order {name {value ""}} {
	if [string length $value] {
	    set order($name) $value
	} else {
	    if [info exists order($name)] {
		set value $order($name)
	    }
	}
	return $value
    }

    method case {name {value ""}} {
	if [string length $value] {
	    set case($name) $value
	} else {
	    if [info exists case($name)] {
		set value $case($name)
	    }
	}
	return $value
    }

    method hovertext {name {value ""}} {
	if [string length $value] {
	    set hovertext($name) $value
	} else {
	    if [info exists hovertext($name)] {
		set value $hovertext($name)
	    }
	}
	return $value
    }

    method blankval {name {value ""}} {
	if [string length $value] {
	    set blankval($name) $value
	} else {
	    if [info exists blankval($name)] {
		set value $blankval($name)
	    }
	}
	return $value
    }

    method limit {args} {
	if [string length $args] {
	    set limit $args
	} else {
	    if [info exists limit] {
		return $limit
	    } else {
		return ""
	    }
	}
    }

    method unfilter {name {value ""}} {
	if [string length $value] {
	    set f [uplevel 1 [list namespace which $value]]
	    if {"$f" == ""} {
		return -code error "Unknown filter $value"
	    }
	    set unfilters($name) $f
	} else {
	    if [info exists unfilters($name)] {
		set value $unfilters($name)
	    }
	}
	return $value
    }

    method attributes {name {value ""}} {
	if [string length $value] {
	    set attributes($name) $value
	} else {
	    if [info exists attributes($name)] {
		set value $attributes($name)
	    }
	}
	return $value
    }

    method hidden {name {value ""}} {
	if [string length $value] {
	    set hidden($name) $value
	} else {
	    if [info exists hidden($name)] {
		set value $hidden($name)
	    }
	}
	return $value
    }

    method mode {{string ""}} { configvar mode $string }
    method csvfile {{string ""}} { configvar csvfile $string }

    method title {{string ""}} { configvar title $string }
    method functions {{string ""}} { configvar functions $string }
    method pagesize {{string ""}} { configvar pagesize $string }
    method form {{string ""}} { configvar form $string }
    method cleanup {{string ""}} { configvar cleanup $string }
    method confirmdelete {{string ""}} { configvar confirmdelete $string }

    method css {{string ""}} { configvar css $string }
    method persistentmain {{string ""}} { configvar persistentmain $string }
    method alternaterows {{string ""}} { configvar alternaterows $string }
    method allowsort {{string ""}} { configvar allowsort $string }
    method sortfields {{string ""}} { configvar sortfields $string }
    method topnav {{string ""}} { configvar topnav $string }
    method bottomnav {{string ""}} { configvar bottomnav $string }
    method numresults {{string ""}} { configvar numresults $string }
    method defaultsortfield {{string ""}} { configvar defaultsortfield $string }
    method labelsplit {{string ""}} { configvar labelsplit $string }

    method rowfunctions {{string ""}} { configvar rowfunctions $string }
    method arrows {{string ""}} { configvar arrows $string }

    method rows {{string 0}} { configvar rows $string 0 }

    ## OPTIONS ##

    public variable rows	 0
    public variable title	 ""
    public variable fields	 ""
    public variable searchfields ""
    public variable functions	 "Search List Add Edit Delete Details"
    public variable pagesize	 25
    public variable form	 ""
    public variable cleanup	 1
    public variable confirmdelete 1
    public variable mode	Main
    public variable trap_errors	0

    public variable css			"diodisplay.css" {
	if {![lempty $css]} {
	    catch {unset cssArray}
	    read_css_file
	}
    }

    public variable persistentmain	1
    public variable alternaterows	1
    public variable allowsort		1
    public variable sortfields		""
    public variable topnav		1
    public variable bottomnav		1
    public variable numresults		""
    public variable defaultsortfield	""
    public variable labelsplit		"\n"

    protected variable rowfields	 ""
    public variable rowfunctions "Details Edit Delete"

    public variable response
    public variable cssArray
    public variable document	 ""
    protected variable allfields    ""
    protected variable NameTextMap
    protected variable FieldNameMap
    public variable allfunctions {
	Search
	List
	Add
	Edit
	Delete
	Details
	Main
	Save
	DoDelete
	Cancel
    }

    # -csv, -csvfile, -csvurl
    # If -csvfile is provided and is in the same directory, gen -csvurl
    public variable csv		0 {
	if {$csv && "$csvfile" == ""} {
	    set csvfile "download.csv"
	    set csvurl "download.csv"
	}
    }
    public variable csvfile	"" {
	set csv 1
	if {"$csvurl" == ""} {
	    if ![regexp {^[.]*/} $csvfile] {
		set csvurl $csvfile
	    }
	}
    }
    public variable csvurl ""
    public variable csvredirect	0

    public variable arrows {"&darr;" "&uarr;"}

    private variable blankval
    private variable rowcount
    private variable filters
    private variable alias
    private variable filtercol
    private variable hovertext
    private variable csvfilters
    private variable order
    private variable unfilters
    private variable attributes
    private variable hidden
    private variable limit
    private variable search_list

} ; ## ::itcl::class STTPDisplay

catch { ::itcl::delete class ::STTPDisplayField }

#
# STTPDisplayField object -- defined for each field we're displaying
#
::itcl::class ::STTPDisplayField {

    constructor {args} {
	## We want to simulate Itcl's configure command, but we want to
	## check for arguments that are not variables of our object.  If
	## they're not, we save them as arguments to the form when this
	## field is displayed.
	import_keyvalue_pairs data $args
	foreach var [array names data] {
	    if {![info exists $var]} {
		lappend formargs -$var $data($var)
	    } else {
		set $var $data($var)
	    }
	}

	# if text (field description) isn't set, prettify the actual
	# field name and use that
	if {[lempty $text]} { set text [pretty [split $name _]] }
    }

    destructor {

    }

    method destroy {} {
	::itcl::delete object $this
    }

    #
    # get_css_class - ask the parent DIODIsplay object to look up
    # a CSS class entry
    #
    method get_css_class {tag default class} {
	return [$display get_css_class $tag $default $class]
    }

    #
    # get_css_tag -- set tag to select or textarea if type is select
    # or textarea, else to input
    #
    method get_css_tag {} {
	switch -- $type {
	    "select" {
		set tag select
	    }
	    "textarea" {
		set tag textarea
	    }
	    default {
		set tag input
	    }
	}
    }

    #
    # pretty -- prettify a list of words by uppercasing the first letter
    #  of each word
    #
    method pretty {string} {
	set words ""
	foreach w $string {
	    lappend words \
		[string toupper [string index $w 0]][string range $w 1 end]
	}
	return [join $words " "]
    }

    #
    # configvar - a convenient helper for creating methods that can
    #  set and fetch one of the object's variables
    #
    method configvar {varName string {defval ""}} {
	if {"$string" == "$defval"} { return [set $varName] }
	configure -$varName $string
    }

    #
    # showview - emit a table row of either DIOViewRow, DIOViewRowAlt,
    # DIOViewRow-fieldname (this object's field name), or 
    # DIOViewRowAlt-fieldname, a table data field of either
    # DIOViewHeader or DIOViewHeader-fieldname, and then a
    # value of class DIOViewField or DIOViewField-fieldname
    #
    method showview {{alt ""}} {
	set class [get_css_class TR DIOViewRow$alt DIOViewViewRow$alt-$name]
	puts "<TR CLASS=\"$class\">"

	set class [get_css_class TD DIOViewHeader DIOViewHeader-$name]
	puts "<TD CLASS=\"$class\">$text:</TD>"

	set class [get_css_class TD DIOViewField DIOViewField-$name]
	puts "<TD CLASS=\"$class\">$value</TD>"

	puts "</TR>"
    }

    #
    # showform -- like showview, creates a table row and table data, but
    # if readonly isn't set, emits a form field corresponding to the type
    # of this field
    #
    method showform {} {
	set class [get_css_class TD DIOFormHeader DIOFormHeader-$name]

	puts "<TR CLASS=\"$class\">"
	puts "<TD CLASS=\"$class\">$text:</TD>"

	set class [get_css_class TD DIOFormField DIOFormField-$name]
	puts "<TD CLASS=\"$class\">"
	if {$readonly} {
	    puts "$value"
	} else {
	    set tag [get_css_tag]
	    set class [get_css_class $tag DIOFormField DIOFormField-$name]

	    set text $value
	    regsub -all {"} $text {\&quot;} text
	    if {$type == "select"} {
		$form select $name -values $values -class $class -value $text
	    } else {
		eval $form $type $name -value [list $text] $formargs -class $class
	    }
	}
	puts "</TD>"
	puts "</TR>"
    }

    # methods that give us method-based access to get and set the
    # object's variables...
    method display  {{string ""}} { configvar display $string }
    method form  {{string ""}} { configvar form $string }
    method formargs  {{string ""}} { configvar formargs $string }
    method name  {{string ""}} { configvar name $string }
    method text  {{string ""}} { configvar text $string }
    method type  {{string ""}} { configvar type $string }
    method value {{string ""}} { configvar value $string }
    method readonly {{string ""}} { configvar readonly $string }

    public variable display		""
    public variable form		""
    public variable formargs		""

    # values - for fields of type "select" only, the values that go in
    # the popdown (or whatever) selector
    public variable values              ""

    # name - the field name
    public variable name		""

    # text - the description text for the field. if not specified,
    #  it's constructed from a prettified version of the field name
    public variable text		""

    # value - the default value of the field
    public variable value		""

    # type - the data type of the field
    public variable type		"text"

    # readonly - if 1, we don't allow the value to be changed
    public variable readonly		0

} ; ## ::itcl::class STTPDisplayField

catch { ::itcl::delete class ::STTPDisplayField_boolean }

#
# STTPDisplayField_boolen -- superclass of STTPDisplayField that overrides
# a few methods to specially handle booleans
#
::itcl::class ::STTPDisplayField_boolean {
    inherit ::STTPDisplayField

    constructor {args} {eval configure $args} {
	eval configure $args
    }

    method add_true_value {string} {
	lappend trueValues $string
    }

    #
    # showform -- emit a form field for a boolean
    #
    method showform {} {
	set class [get_css_class TD DIOFormHeader DIOFormHeader-$name]
	puts "<TR CLASS=\"$class\">"
	puts "<TD CLASS=\"$class\">$text:</TD>"

	set class [get_css_class TD DIOFormField DIOFormField-$name]
	puts "<TD CLASS=\"$class\">"
	if {$readonly} {
	    if {[boolean_value]} {
		puts $true
	    } else {
		puts $false
	    }
	} else {
	    if {[boolean_value]} {
		$form default_value $name $true
	    } else {
		$form default_value $name $false
	    }
	    eval $form radiobuttons $name \
		-values [list "$true $false"] $formargs
	}
	puts "</TD>"
	puts "</TR>"
    }

    #
    # showview -- emit a view for a boolean
    #
    method showview {{alt ""}} {
	set class [get_css_class TR DIOViewRow$alt DIOViewRow$alt-$name]
	puts "<TR CLASS=\"$class\">"

	set class [get_css_class TD DIOViewHeader DIOViewHeader-$name]
	puts "<TD CLASS=\"$class\">$text:</TD>"

	set class [get_css_class TD DIOViewField DIOViewField-$name]
	puts "<TD CLASS=\"$class\">"
	if {[boolean_value]} {
	    puts $true
	} else {
	    puts $false
	}
	puts "</TD>"

	puts "</TR>"
    }

    #
    # boolean_value -- return 1 if value is found in the values list, else 0
    #
    method boolean_value {} {
	set val [string tolower $value]
	if {[lsearch -exact $values $val] > -1} { return 1 }
	return 0
    }

    method value {{string ""}} { configvar value $string }

    public variable true	"Yes"
    public variable false	"No"
    public variable values	"1 y yes t true on"

    public variable value "" {
	if {[boolean_value]} {
	    set value $true
	} else {
	    set value $false
	}
    }

} ; ## ::itcl::class ::STTPDisplayField_boolean

package provide sttp_display 1.0


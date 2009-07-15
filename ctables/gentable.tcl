#
# CTables - code to generate Tcl C extensions that implement tables out of
# C structures
#
#
# $Id$
#

namespace eval ctable {
    variable ctablePackageVersion
    variable table
    variable tables
    variable booleans
    variable nonBooleans
    variable fields
    variable fieldList
    variable keyField
    variable keyFieldName
    variable ctableTypes
    variable ctableErrorInfo
    variable withPgtcl
    variable withSharedTables
    variable withSharedTclExtension
    variable sharedTraceFile	;# default none
    variable poolRatio		;# default 16
    variable withDirty
    variable reservedWords
    variable errorDebug

    variable genCompilerDebug
    variable showCompilerCommands
    variable withPipe
    variable memDebug
    variable sanityChecks
    variable keyCompileVariables

    set ctablePackageVersion 1.6

    # If loaded directly, rather than as a package
    if {![info exists srcDir]} {
	set srcDir .
    }

    source [file join $srcDir sysconfig.tcl]

    source [file join $srcDir config.tcl]

    variable leftCurly
    variable rightCurly

    set leftCurly \173
    set rightCurly \175

    # Important compile settings, used in generating the ID
    set keyCompileVariables {
	fullInline
	fullStatic
	withPgtcl
	withSharedTables
	withSharedTclExtension
	sharedTraceFile
	sharedBase
	withDirty
	genCompilerDebug
	memDebug
	sanityChecks
    }

    set ctableErrorInfo ""

    set tables ""

    namespace eval fields {}

    set cvsID {#CTable generator ID: $Id$}

    ## ctableTypes must line up with the enumerated typedef "ctable_types"
    ## in ctable.h
    set ctableTypes "boolean fixedstring varstring char mac short int long wide float double inet tclobj key"

    set reservedWords "bool char short int long wide float double"

set fp [open $srcDir/template.c-subst]
set metaTableSource [read $fp]
close $fp

set fp [open $srcDir/init-exten.c-subst]
set initExtensionSource [read $fp]
close $fp

set fp [open $srcDir/exten-frag.c-subst]
set extensionFragmentSource [read $fp]
close $fp

#
# cmdBodySource - code we run subst over to generate the second chunk of the
#  body that implements the methods that work on the table.
#
set fp [open $srcDir/command-body.c-subst]
set cmdBodySource [read $fp]
close $fp

#
# emit - emit a string to the file being generated
#
proc emit {text} {
    variable ofp

    puts $ofp $text
}

#
# cquote -- quote a string so the C compiler will see the same thing
#  if it occurs inside double-quotes
#
proc cquote {string {meta {"}}} {
  # first, escape the metacharacters (quote) and backslash
  append meta {\\}
  regsub -all "\[$meta]" $string {\\&} string

  # Now loop over the string looking for nonprinting characters
  set quoted ""
  while {
    [regexp {([[:graph:]]*)([^[:graph:]])(.*)} $string _ plain char string]
  } {
    append quoted $plain
    # gratuitously make \n and friends look nice
    set index [string first $char "\r\n\t\b\f "]
    if {$index == -1} {
      scan $char %c decimal
      set plain [format {\%03o} $decimal]
    } else {
      set plain [lindex {{\r} {\n} {\t} {\b} {\f} { }} $index]
    }
    append quoted $plain
  }
  append quoted $string
  return $quoted
}

#
# Special normally-illegal field names
#
variable specialFieldNames {
    _key
    _dirty
}

#
# is_key - is this field a "key" or a normal field
#
proc is_key {fieldName} {
    # If called before special "_key" field is set up.
    if {"$fieldName" == "_key"} {
	return 1
    }

    # Otherwise go by type
    upvar ::ctable::fields::$fieldName field
    if {[info exists field(type)] && "$field(type)" == "key"} {
	return 1
    }

    return 0
}

#
# is_hidden - hidden fields are not returned in arrays or lists by default
#
proc is_hidden {fieldName} {
    return [string match {[._]*} $fieldName]
}

#
# field_to_enum - return a field mapped to the name we'll use when
#  creating or referencing an enumerated list of field names.
#
#  for example, creating table fa_position and field longitude, this
#   routine will return FIELD_FA_POSITION_LONGITUDE
#
proc field_to_enum {fieldName} {
    variable table

    if {[regexp {^[._](.*)$} $fieldName _ pseudoName]} {
	return "SPECIAL_[string toupper $table]_[string toupper $pseudoName]"
    }
    return "FIELD_[string toupper $table]_[string toupper $fieldName]"
}

#
# field_to_var - generate a unique variable name
#
proc field_to_var {table fieldName varName} {
    if [regexp {^[._](.*)} $fieldName _ pseudoName] {
	return "_${table}_${pseudoName}_$varName"
    }
    return "${table}_${fieldName}_$varName"
}
#
# field_to_nameObj - return a field mapped to the Tcl name object we'll
# use to expose the name to Tcl
#
proc field_to_nameObj {table fieldName} {
    return [field_to_var $table $fieldName nameObj]
}

#
# gen_allocate - return the code to allocate memory and assign
#
proc gen_allocate {ctable size {private 0}} {
    variable withSharedTables
    variable table
    set priv "ckalloc($size)"
    set pub "${table}_allocate($ctable, $size)"

    if {!$withSharedTables || "$private" == "1" || "$private" == "TRUE"} {
	return $priv
    }

    if {"$private" == "0" || "$private" == "FALSE"} {
	return $pub
    }

    return "(($private) ? $priv : $pub)"
}

#
# Oposite function for free
#
proc gen_deallocate {ctable pointer {private 0}} {
    variable withSharedTables
    set priv "ckfree((void *)($pointer))"
    set pub "shmfree(($ctable)->share, (void *)($pointer))"

    if {!$withSharedTables || "$private" == "1" || "$private" == "TRUE"} {
	return $priv
    }

    if {"$private" == "0" || "$private" == "FALSE"} {
	return "(($ctable)->share_type == CTABLE_SHARED_MASTER ? $pub : $priv)"
    }

    return "( (($ctable)->share_type != CTABLE_SHARED_MASTER || ($private)) ? $priv : $pub)"
}

#
# Default empty string for table
#
proc gen_defaultEmptyString {ctable lvalue {private 0}} {
    variable withSharedTables
    variable table
    set priv "Tcl_GetStringFromObj (${table}_DefaultEmptyStringObj, &($lvalue))"
    set pub "(($lvalue) = 0, ($ctable)->emptyString)"

    if {!$withSharedTables || "$private" == "1" || "$private" == "TRUE"} {
	return $priv
    }

    if {"$private" == "0" || "$private" == "false"} {
	return $pub
    }

    return "(($private) ? $priv : $pub)"
}

variable allocateSource {
void ${table}_shmpanic(CTable *ctable)
{
    panic (
	"Out of shared memory for \"%s\".", ctable->share_file
    );
}

char *${table}_allocate(CTable *ctable, size_t amount)
{
    if(ctable->share_type == CTABLE_SHARED_MASTER) {
	char *memory = shmalloc(ctable->share, amount);
	if(!memory)
	    ${table}_shmpanic(ctable);
	return memory;
    }
    return (char *)ckalloc(amount);
}
}

proc gen_allocate_function {table} {
    variable withSharedTables
    variable allocateSource
    if {$withSharedTables} {
	emit [string range [subst -nobackslashes -nocommands $allocateSource] 1 end-1]
    }
}

variable sanitySource {
void ${table}_sanity_check_pointer(CTable *ctable, void *ptr, int indexCtl, char *where)
{
#ifdef WITH_SHARED_TABLES
    if(indexCtl != CTABLE_INDEX_NEW) {
	if(ctable->share_type == CTABLE_SHARED_MASTER || ctable->share_type == CTABLE_SHARED_READER) {
	    if(ctable->share == NULL)
		panic("%s: ctable->share_type = %d but ctable->share = NULL", where);
	    if((char *)ptr < (char *)ctable->share->map)
		panic("%s: ctable->share->map = 0x%lX but ptr == 0x%lX", where, (long)ctable->share->map, (long)ptr);
	    if((char *)ptr - (char *)ctable->share->map > ctable->share->size)
		panic("%s: ctable->share->size = %ld but ptr is at %ld offset from map", where, (long)ctable->share->size, (long)((char *)ptr - (char *)ctable->share->map));
	}
    }
#endif
}
}

proc gen_sanity_checks {table} {
    variable sanityChecks
    variable sanitySource
    if {$sanityChecks} {
	emit [string range [subst -nobackslashes -nocommands $sanitySource] 1 end-1]
    }
}

variable insertRowSource {
int ${table}_reinsert_row(Tcl_Interp *interp, CTable *ctable, char *value, struct ${table} *row, int indexCtl)
{
    ctable_HashEntry *new, *old;
    int isNew = 0;
    int flags = KEY_VOLATILE;
    char *key = value;

    // Check for duplicates
    old = ctable_FindHashEntry(ctable->keyTablePtr, value);
    if(old) {
	Tcl_AppendResult (interp, "Duplicate key '", value, "' when setting key field", (char *)NULL);
	return TCL_ERROR;
    }

    // Remove old key.
    if(indexCtl == CTABLE_INDEX_NORMAL) {
	${table}_deleteHashEntry (ctable, row);
#ifdef WITH_SHARED_TABLES
        // Save new key
        if(ctable->share_type == CTABLE_SHARED_MASTER) {
	    key = shmalloc(ctable->share, strlen(value)+1);
	    if(!key)
	        ${table}_shmpanic(ctable);
	    strcpy(key, value);
	    flags = KEY_STATIC;
        }
#endif
    } else {
        // This shouldn't be possible, but just in case
	ckfree(row->hashEntry.key);
	row->hashEntry.key = NULL;
    }

    // Insert existing row with new key
    new = ctable_StoreHashEntry(ctable->keyTablePtr, key, (ctable_HashEntry *)row, flags, &isNew);

#ifdef SANITY_CHECKS
    ${table}_sanity_check_pointer(ctable, (void *)new, CTABLE_INDEX_NORMAL, "${table}_reinsert_row");
#endif

    if(!isNew) {
	Tcl_AppendResult (interp, "Duplicate key '", value, "' after setting key field!", (char *)NULL);
#ifdef WITH_SHARED_TABLES
	if(flags == KEY_STATIC) {
	    /* Don't need to "shmfree" because the key was never made
	     * visible to any readers.
	     */
	    shmdealloc(ctable->share, (char *)key);
	}
#endif
	return TCL_ERROR;
    }

    if(indexCtl == CTABLE_INDEX_NEW) {
	int field;
        // Add to indexes.
        for(field = 0; field < ${TABLE}_NFIELDS; field++) {
	    if (ctable_InsertIntoIndex (interp, ctable, row, field) == TCL_ERROR) {
		return TCL_ERROR;
	    }
	}
    }

    return TCL_OK;
}
}

proc gen_insert_row_function {table} {
    set TABLE [string toupper $table]
    variable insertRowSource
    emit [string range [subst -nobackslashes -nocommands $insertRowSource] 1 end-1]
}

#
# preambleCannedSource -- stuff that goes at the start of the file we generate
#
variable preambleCannedSource {
#include "ctable.h"
}

variable nullIndexDuringSetSource {
	        if (ctable->skipLists[field] != NULL) {
		    if (indexCtl == CTABLE_INDEX_NORMAL) {
		        ctable_RemoveFromIndex (ctable, row, field);
		    }

		    if ((indexCtl != CTABLE_INDEX_PRIVATE) && (ctable_InsertNullIntoIndex (interp, ctable, row, field) == TCL_ERROR)) {
		        return TCL_ERROR;
		    }
		}
}

#
# nullCheckDuringSetSource - standard stuff for handling nulls during set
#
variable nullCheckDuringSetSource {
	int obj_is_null = ${table}_obj_is_null (obj);
	if (obj_is_null) {
	    if (!row->_${fieldName}IsNull) {
$handleNullIndex
	        // field wasn't null but now is
		row->_${fieldName}IsNull = 1;
	    } else {
		// No change, don't do anything
	        return TCL_OK;
	    }
	}
}

#
# gen_null_check_during_set_source - generate standard null checking
#  for a set
#
proc gen_null_check_during_set_source {table fieldName {elseCase ""}} {
    variable nullCheckDuringSetSource
    variable nullIndexDuringSetSource
    variable fields

    upvar ::ctable::fields::$fieldName field

    if {[info exists field(notnull)] && $field(notnull)} {
        return $elseCase
    }

    if {[info exists field(indexed)] && $field(indexed)} {
        set handleNullIndex $nullIndexDuringSetSource
    } else {
        set handleNullIndex ""
    }

    if {"$elseCase" != ""} {
	set elseCase " else $elseCase"
    }

    return [string range [subst -nobackslashes -nocommands $nullCheckDuringSetSource] 1 end-1]$elseCase
}

variable unsetNullDuringSetSource {
	if (!obj_is_null && row->_${fieldName}IsNull) {
	    row->_${fieldName}IsNull = 0;

	    if ((indexCtl == CTABLE_INDEX_NORMAL) && (ctable->skipLists[field] != NULL)) {
	        indexCtl = CTABLE_INDEX_NEW; // inhibit a second removal
		if (ctable_RemoveNullFromIndex (interp, ctable, row, field) == TCL_ERROR) {
		    return TCL_ERROR;
		}
	    }
	}
}

variable unsetNullDuringSetSource_unindexed {
	if (!obj_is_null && row->_${fieldName}IsNull) {
	    row->_${fieldName}IsNull = 0;
	}
}

# gen_if_equal - generate code if $v1 == $v2
proc gen_if_equal {v1 v2 code} {
    if {"$v1" == "$v2"} {return $code}
    return ""
}

#
# gen_unset_null_during_set_source - generate standard null unsetting
#  for a set
#
proc gen_unset_null_during_set_source {table fieldName {elsecode {}}} {
    variable unsetNullDuringSetSource
    variable unsetNullDuringSetSource_unindexed
    variable fields

    upvar ::ctable::fields::$fieldName field

    if {[info exists field(notnull)] && $field(notnull)} {
	if {"$elsecode" == ""} {
	    return ""
	} else {
            return "        $elsecode"
	}
    } else {
	if {"$elsecode" != ""} {
	    set elsecode " else $elsecode"
	}
	if {[info exists field(indexed)] && $field(indexed)} {
	    return "[string range [subst -nobackslashes -nocommands $unsetNullDuringSetSource] 1 end-1]$elsecode"
	} else {
	    return "[string range [subst -nobackslashes -nocommands $unsetNullDuringSetSource_unindexed] 1 end-1]$elsecode"
	}
    }
}

#####
#
# Generating Code To Set Values In Rows
#
#####

variable removeFromIndexSource {
	    if ((indexCtl == CTABLE_INDEX_NORMAL) && (ctable->skipLists[field] != NULL)) {
		ctable_RemoveFromIndex (ctable, row, field);
	    }
}

#
# gen_ctable_remove_from_index - return code to remove the specified field
# from an index, or nothing if the field is not indexable -- requires
# interp, ctable, row and field to be defined and in scope in the C target.
#
proc gen_ctable_remove_from_index {fieldName} { 
    variable fields
    variable removeFromIndexSource

    upvar ::ctable::fields::$fieldName field

    if {[info exists field(indexed)] && $field(indexed)} {
        return $removeFromIndexSource
    } else {
        return ""
    }
}

variable insertIntoIndexSource {
	if ((indexCtl != CTABLE_INDEX_PRIVATE) && (ctable->skipLists[field] != NULL)) {
	    if (ctable_InsertIntoIndex (interp, ctable, row, field) == TCL_ERROR) {
	        return TCL_ERROR;
	    }
	}
}

#
# gen_ctable_insert_into_index - return code to insert the specified field
# into an index, or nothing if the field is not indexable -- requires
# interp, ctable, row and field to be defined and in scope in the C target.
#
proc gen_ctable_insert_into_index {fieldName} { 
    variable fields
    variable insertIntoIndexSource

    upvar ::ctable::fields::$fieldName field

    if {[info exists field(indexed)] && $field(indexed)} {
        return $insertIntoIndexSource
    } else {
        return ""
    }
}

#
# boolSetSource - code we run subst over to generate a set of a boolean (bit)
#
variable boolSetSource {
      case $optname: {
        int boolean = 0;

[gen_null_check_during_set_source $table $fieldName \
        "if (Tcl_GetBooleanFromObj (interp, obj, &boolean) == TCL_ERROR) {
            Tcl_AppendResult (interp, \" while converting $fieldName\", (char *)NULL);
            return TCL_ERROR;
        }"]
[gen_unset_null_during_set_source $table $fieldName \
	"if (row->$fieldName == boolean)
	    return TCL_OK;"]

        row->$fieldName = boolean;
        [gen_if_equal $fieldName _dirty "return TCL_OK; // Don't set dirty for meta-fields"]
	break;
      }
}

#
# numberSetSource - code we run subst over to generate a set of a standard
#  number such as an integer, long, double, and wide integer.  (We have to 
#  handle shorts and floats specially due to type coercion requirements.)
#
variable numberSetSource {
      case $optname: {
        $typeText value;
[gen_null_check_during_set_source $table $fieldName \
	"if ($getObjCmd (interp, obj, &value) == TCL_ERROR) {
	    Tcl_AppendResult (interp, \" while converting $fieldName\", (char *)NULL);
	    return TCL_ERROR;
	}"]
[gen_unset_null_during_set_source $table $fieldName \
	"if (row->$fieldName == value)
	    return TCL_OK;"]
[gen_ctable_remove_from_index $fieldName]
	row->$fieldName = value;
[gen_ctable_insert_into_index $fieldName]
	break;
      }
}
variable keySetSource {
      case $optname: {
        char *value = Tcl_GetString(obj);

        if (row->hashEntry.key != NULL && *value == *row->hashEntry.key && strcmp(value, row->hashEntry.key) == 0)
	    return TCL_OK;

	switch (indexCtl) {
	    case CTABLE_INDEX_PRIVATE: {
		// fake hash entry for search
		if(row->hashEntry.key) [gen_deallocate ctable row->hashEntry.key 1];
		row->hashEntry.key = (char *)[gen_allocate ctable "strlen(value)+1" 1];
		strcpy(row->hashEntry.key, value);
		break;
	    }
	    case CTABLE_INDEX_NORMAL:
	    case CTABLE_INDEX_NEW: {

#ifdef SANITY_CHECKS
		${table}_sanity_check_pointer(ctable, (void *)row, CTABLE_INDEX_NORMAL, "${table}::keySetSource");
#endif
		if (${table}_reinsert_row(interp, ctable, value, row, indexCtl) == TCL_ERROR)
		    return TCL_ERROR;
		break;
	    }
	}
	break;
      }
}

proc gen_check_unchanged_string {fieldName default defaultLength} {
    variable leftCurly
    variable rightCurly

	append code "if (!row->$fieldName) $leftCurly"
	if {"$defaultLength" == "0"} {
	    append code "
            if (!*string)
		return TCL_OK;"
	} else {
	    # For the rare case where the default string is nonprintable,
	    # fudge it.
	    if {[string index $default 0] == "\\"} {
	       set def0 "\"$default\"\[0]"
	    } else {
		set def0 '[string index $default 0]'
	    }
	    append code "
	    if (length == $defaultLength && *string == $def0 && (strncmp (string, \"$default\", $defaultLength) == 0))
	        return TCL_OK;"
	}
	append code "
        $rightCurly else $leftCurly
	    if(length == row->_${fieldName}Length && *string == *row->$fieldName && strcmp(string, row->$fieldName) == 0)
	        return TCL_OK;
	$rightCurly"
	return $code
}

proc gen_default_test {varName lengthName default defaultLength} {
    if {$defaultLength == 0} { return "!*$varName" }

    set def0 '[cquote [string index $default 0] {'}]'

    return "$lengthName == $defaultLength && *$varName == $def0 && strncmp ($varName, \"$default\", $defaultLength) == 0"
}

#
# varstringSetSource - code we run subst over to generate a set of a string.
#
# strings are char *'s that we manage automagically.
#
# Get the string from the passed-in object.  If the length of the string
# matches the length of the default string, see if the length of the
# default string is zero or if obj's string matches the default string.
# If so, set the char * field in the row to NULL.  Upon a fetch of the
# field, we'll provide the default string.
#
# Otherwise allocate space for the new string value and copy it in.
#
variable varstringSetSource {
      case $optname: {
	char *string = NULL;
	int   length;
[gen_null_check_during_set_source $table $fieldName]

	string = Tcl_GetStringFromObj (obj, &length);
[gen_unset_null_during_set_source $table $fieldName \
	[gen_check_unchanged_string $fieldName $default $defaultLength]]

	// we now know it's not the same as the previous value of the string,
	// even if the previous value was default, so if the new value is
	// default we know the old value wasn't.
	if ([gen_default_test string length $default $defaultLength]) {
[gen_ctable_remove_from_index $fieldName]
	    if (row->$fieldName != NULL) {
	        [gen_deallocate ctable row->$fieldName "indexCtl == CTABLE_INDEX_PRIVATE"];
	    }

	    // It's a change to the be default string. If we're
	    // indexed, force the default string in there so the 
	    // compare routine will be happy and then insert it.
	    // can't use our proc here yet because of the
	    // default empty string obj fanciness
	    if ((indexCtl != CTABLE_INDEX_PRIVATE) && (ctable->skipLists\[field] != NULL)) {
		row->$fieldName = \"[cquote $default]\";
		if (ctable_InsertIntoIndex (interp, ctable, row, field) == TCL_ERROR) {
		    return TCL_ERROR;
		}
	    }
	    row->$fieldName = NULL;
	    row->_${fieldName}AllocatedLength = 0;
	    row->_${fieldName}Length = 0;
	    break;
	}

	// previous field isn't null, new field isn't null, isn't
	// the default string, and isn't the same as the previous field
[gen_ctable_remove_from_index $fieldName]

	// new string value
	// if the allocated length is less than what we need, get more,
	// else reuse the previously allocagted space
	if (row->_${fieldName}AllocatedLength <= length) {
	    if (row->$fieldName != NULL) {
		[gen_deallocate ctable "row->$fieldName" "indexCtl == CTABLE_INDEX_PRIVATE"];
	    }
	    row->$fieldName = (char *)[gen_allocate ctable "length + 1" "indexCtl == CTABLE_INDEX_PRIVATE"];
	    row->_${fieldName}AllocatedLength = length + 1;
	}
	strncpy (row->$fieldName, string, length + 1);
	row->_${fieldName}Length = length;

	// if we got here and this field has an index, we've removed
	// the old index either by removing a null index or by
	// removing the prior index, now insert the new index
[gen_ctable_insert_into_index $fieldName]
	break;
      }
}

#
# charSetSource - code we run subst over to generate a set of a single char.
#
variable charSetSource {
      case $optname: {
	char *string;
[gen_null_check_during_set_source $table $fieldName]
	string = Tcl_GetString (obj);
[gen_unset_null_during_set_source $table $fieldName \
	"if(row->$fieldName != string\[0])
	    return TCL_OK;"]
[gen_ctable_remove_from_index $fieldName]
	row->$fieldName = string\[0\];
[gen_ctable_insert_into_index $fieldName]
	break;
      }
}

#
# fixedstringSetSource - code we run subst over to generate a set of a 
# fixed-length string.
#
variable fixedstringSetSource {
      case $optname: {
	char *string;
	int   len;
[gen_null_check_during_set_source $table $fieldName]
	string = Tcl_GetStringFromObj (obj, &len);
[gen_unset_null_during_set_source $table $fieldName \
	"if (len == 0 && [string length default]) string = \"$default\";
	if (*string == *row->$fieldName && strncmp(row->$fieldName, string, $length) == 0)
	    return TCL_OK;"]
[gen_ctable_remove_from_index $fieldName]
	strncpy (row->$fieldName, string, $length);
[gen_ctable_insert_into_index $fieldName]
	break;
      }
}

#
# inetSetSource - code we run subst over to generate a set of an IPv4
# internet address.
#
variable inetSetSource {
      case $optname: {
        struct in_addr value = {INADDR_ANY};
[gen_null_check_during_set_source $table $fieldName \
	"if (!inet_aton (Tcl_GetString (obj), &value)) {
	    Tcl_AppendResult (interp, \"expected IP address but got \\\"\", Tcl_GetString (obj), \"\\\" parsing field \\\"$fieldName\\\"\", (char *)NULL);
	    return TCL_ERROR;
	}"]
[gen_unset_null_during_set_source $table $fieldName \
	"if (memcmp (&row->$fieldName, &value, sizeof (struct in_addr)) == 0)
            return TCL_OK;"]

[gen_ctable_remove_from_index $fieldName]
	row->$fieldName = value;
[gen_ctable_insert_into_index $fieldName]
	break;
      }
}

#
# macSetSource - code we run subst over to generate a set of an ethernet
# MAC address.
#
variable macSetSource {
      case $optname: {
        struct ether_addr *mac = (struct ether_addr *) NULL;
[gen_null_check_during_set_source $table $fieldName \
	"{
	    mac = ether_aton (Tcl_GetString (obj));
	    if (mac == (struct ether_addr *) NULL) {
	        Tcl_AppendResult (interp, \"expected MAC address but got \\\"\", Tcl_GetString (obj), \"\\\" parsing field \\\"$fieldName\\\"\", (char *)NULL);
	        return TCL_ERROR;
	    }
	}"]

[gen_unset_null_during_set_source $table $fieldName \
	"if (memcmp (&row->$fieldName, mac, sizeof (struct ether_addr)) == 0)
            return TCL_OK;"]
[gen_ctable_remove_from_index $fieldName]
	row->$fieldName = *mac;
[gen_ctable_insert_into_index $fieldName]
	break;
      }
}

#
# tclobjSetSource - code we run subst over to generate a set of a tclobj.
#
# tclobjs are Tcl_Obj *'s that we manage automagically.
#
variable tclobjSetSource {
      case $optname: {

	if (row->$fieldName != (Tcl_Obj *) NULL) {
	    Tcl_DecrRefCount (row->$fieldName);
	    row->$fieldName = NULL;
	}
[gen_null_check_during_set_source $table $fieldName \
	"{
	    row->$fieldName = obj;
	    Tcl_IncrRefCount (obj);
	}"]
[gen_unset_null_during_set_source $table $fieldName]
	break;
      }
}

#####
#
# Generating Code For Sort Comparisons
#
#####

#
# nullSortSource - code to be inserted when null values are permitted for the
#  field.
#
variable nullSortSource {
        if (row1->_${fieldName}IsNull) {
	    if (row2->_${fieldName}IsNull) {
		result = 0;
	        break;
	    }

	    return direction;
	} else if (row2->_${fieldName}IsNull) {
	    return -direction;
	}
}

#
# gen_null_default_check_during_sort_comp -
#	emit null and default checking as part of field
#  comparing in a sort
#
proc gen_null_default_check_during_sort_comp {table fieldName} {
    variable nullSortSource
    variable varstringSortCompareNullSource
    variable varstringSortCompareDefaultSource

    upvar ::ctable::fields::$fieldName field

    if {"$field(type)" == "varstring"} {
	if {![info exists field(default)] || "$field(default)" == ""} {
	     set source $varstringSortCompareNullSource
	} else {
	     set source $varstringSortCompareDefaultSource
	     set defaultString "\"[cquote $field(default)]\""
	     set defaultChar "'[cquote [string index $field(default) 0] {'}]'"
	}
    } elseif {[info exists field(notnull)] && $field(notnull)} {
        set source ""
    } else {
	set source $nullSortSource
    }

    return [string range [subst -nobackslashes -nocommands $source] 1 end-1]
}

variable nullExcludeSource {
	      if (row->_${fieldName}IsNull) {
		  exclude = 1;
		  break;
	      }
}

proc gen_null_exclude_during_sort_comp {table fieldName} {
    variable nullExcludeSource

    upvar ::ctable::fields::$fieldName field

    if {[info exists field(notnull)] && $field(notnull)} {
        return ""
    } else {
	return [string range [subst -nobackslashes -nocommands $nullExcludeSource] 1 end-1]
    }
}

#
# boolSortSource - code we run subst over to generate a compare of a 
# boolean (bit) for use in a sort.
#
variable boolSortSource {
	case $fieldEnum: {
[gen_null_default_check_during_sort_comp $table $fieldName]
          if (row1->$fieldName && !row2->$fieldName) {
	      result = -direction;
	      break;
	  }

	  if (!row1->$fieldName && row2->$fieldName) {
	      result = direction;
	  }

	  result = 0;
	  break;
      }
}

#
# numberSortSource - code we run subst over to generate a compare of a standard
#  number such as an integer, long, double, and wide integer for use in a sort.
#
variable numberSortSource {
      case $fieldEnum: {
[gen_null_default_check_during_sort_comp $table $fieldName]
        if (row1->$fieldName < row2->$fieldName) {
	    result = -direction;
	    break;
	}

	if (row1->$fieldName > row2->$fieldName) {
	    result = direction;
	    break;
	}

	result = 0;
	break;
      }
}

#
# varstringSortCompareDefaultSource - compare against default strings for
#   sorting
#
# note there's also a varstringCompareNullSource that's pretty close to this
# but returns stuff rather than setting results and doing a break
#
#
variable varstringSortCompareDefaultSource {
    if (!row1->$fieldName) {
	if(!row2->$fieldName) {
	    result = 0;
	    break;
	} else {
	    if ($defaultChar != row2->${fieldName}[0]) {
		result = direction * (($defaultChar < row2->${fieldName}[0]) ? -1 : 1);
		break;
	    }
	    result = direction * strcmp($defaultString, row2->$fieldName);
	    break;
	}
    } else {
	if(!row2->$fieldName) {
	    if (row1->${fieldName}[0] != $defaultChar) {
		result = direction * ((row1->${fieldName}[0] < $defaultChar) ? -1 : 1);
		break;
	    }
	    result = direction * strcmp(row1->$fieldName, $defaultString);
	    break;
	}
    }
}

#
# varstringSortCompareNullSource - compare against default empty string
#   for sorting
#
# note there's also a varstringCompareNullSource that's pretty close to this
# but returns everything instead of just returning on non-match.
#
variable varstringSortCompareNullSource {
    if (!row1->$fieldName) {
	if(!row2->$fieldName) {
	    result = 0;
	    break;
	} else {
	    return direction * -1;
	}
    } else {
	if(!row2->$fieldName) {
	    return direction;
	}
    }
}

#
# varstringSortSource - code we run subst over to generate a compare of 
# a string for use in a sort.
#
variable varstringSortSource {
      case $fieldEnum: {
[gen_null_default_check_during_sort_comp $table $fieldName]

        result = direction * strcmp (row1->$fieldName, row2->$fieldName);
	break;
      }
}

#
# fixedstringSortSource - code we run subst over to generate a comapre of a 
# fixed-length string for use in a sort.
#
variable fixedstringSortSource {
      case $fieldEnum: {
[gen_null_default_check_during_sort_comp $table $fieldName]
        result = direction * strncmp (row1->$fieldName, row2->$fieldName, $length);
	break;
      }
}

#
# binaryDataSortSource - code we run subst over to generate a comapre of a 
# inline binary arrays (inets and mac addrs) for use in a sort.
#
variable binaryDataSortSource {
      case $fieldEnum: {
[gen_null_default_check_during_sort_comp $table $fieldName]
        result = direction * memcmp (&row1->$fieldName, &row2->$fieldName, $length);
	break;
      }
}

#
# tclobjSortSource - code we run subst over to generate a compare of 
# a tclobj for use in a sort.
#
variable tclobjSortSource {
      case $fieldEnum: {
        result = direction * strcmp (Tcl_GetString (row1->$fieldName), Tcl_GetString (row2->$fieldName));
	break;
      }
}

#
# keySortSource - code we run subst over to generate a compare of 
# a key for use in a sort.
#
variable keySortSource {
      case $fieldEnum: {
	if(*row1->hashEntry.key > *row2->hashEntry.key)
	    result = direction;
	else if(*row1->hashEntry.key < *row2->hashEntry.key)
	    result = -direction;
	else
            result = direction * strcmp (row1->hashEntry.key, row2->hashEntry.key);
	break;
      }
}

#####
#
# Generating Code For Search Comparisons
#
#####

#
# standardCompNullCheckSource - variable to substitute to do null
# handling in all comparison types
#
variable standardCompNullCheckSource {
	  if (row->_${fieldName}IsNull) {
	      if (compType == CTABLE_COMP_NULL) {
		  break;
	      }
	      exclude = 1;
	      break;
          }

	  if (compType == CTABLE_COMP_NULL) {
	      exclude = 1;
	      break;
	  }

	  if (compType == CTABLE_COMP_NOTNULL) {
	      break;
	  }
}

#
# standardCompNotNullCheckSource - variable to substitute to do null
# comparison handling for fields defined notnull.
#
variable standardCompNotNullCheckSource {
	  if (compType == CTABLE_COMP_NULL) {
	      exclude = 1;
	      break;
          } else if (compType == CTABLE_COMP_NOTNULL) {
	      break;
	  }
}

#
# gen_standard_comp_null_check_source - gen code to check null stuff
#  when generating search comparison routines
#
proc gen_standard_comp_null_check_source {table fieldName} {
    variable standardCompNullCheckSource
    variable standardCompNotNullCheckSource
    upvar ::ctable::fields::$fieldName field

    if {[info exists field(notnull)] && $field(notnull)} {
        return [string range $standardCompNotNullCheckSource 1 end-1]
    } else {
	return [string range [subst -nobackslashes -nocommands $standardCompNullCheckSource] 1 end-1]
    }
}

#
# standardCompSwitchSource -stuff that gets emitted in a number of compare
#  routines we generate
#
variable standardCompSwitchSource {
          switch (compType) {
	    case CTABLE_COMP_LT:
	        exclude = !(strcmpResult < 0);
		break;

	    case CTABLE_COMP_LE:
	        exclude = !(strcmpResult <= 0);
		break;

	    case CTABLE_COMP_EQ:
	        exclude = !(strcmpResult == 0);
		break;

	    case CTABLE_COMP_NE:
	        exclude = !(strcmpResult != 0);
		break;

	    case CTABLE_COMP_GE:
	        exclude = !(strcmpResult >= 0);
		break;

	    case CTABLE_COMP_GT:
	        exclude = !(strcmpResult > 0);
		break;

	    default:
	        panic ("compare type %d not implemented for field \"${fieldName}\"", compType);
	  }
	  break;
}

#
# gen_standard_comp_switch_source - emit the standard compare source
#
proc gen_standard_comp_switch_source {fieldName} {
    variable standardCompSwitchSource

    return [string range [subst -nobackslashes -nocommands $standardCompSwitchSource] 1 end-1]
}

#
# boolCompSource - code we run subst over to generate a compare of a 
# boolean (bit)
#
variable boolCompSource {
      case $fieldEnum: {
[gen_standard_comp_null_check_source $table $fieldName]
	switch (compType) {
	  case CTABLE_COMP_TRUE:
	     exclude = (!row->$fieldName);
	     break;

	  case CTABLE_COMP_FALSE:
	    exclude = row->$fieldName;
	    break;
	}
	break;
      }
}

#
# numberCompSource - code we run subst over to generate a compare of a standard
#  number such as an integer, long, double, and wide integer.  (We have to 
#  handle shorts and floats specially due to type coercion requirements.)
#
variable numberCompSource {
        case $fieldEnum: {
[gen_standard_comp_null_check_source $table $fieldName]
          switch (compType) {
	    case CTABLE_COMP_LT:
	        exclude = !(row->$fieldName < row1->$fieldName);
		break;

	    case CTABLE_COMP_LE:
	        exclude = !(row->$fieldName <= row1->$fieldName);
		break;

	    case CTABLE_COMP_EQ:
	        exclude = !(row->$fieldName == row1->$fieldName);
		break;

	    case CTABLE_COMP_NE:
	        exclude = !(row->$fieldName != row1->$fieldName);
		break;

	    case CTABLE_COMP_GE:
	        exclude = !(row->$fieldName >= row1->$fieldName);
		break;

	    case CTABLE_COMP_GT:
	        exclude = !(row->$fieldName > row1->$fieldName);
		break;

	    case CTABLE_COMP_TRUE:
	        exclude = (!row->$fieldName);
		break;

	    case CTABLE_COMP_FALSE:
	        exclude = row->$fieldName;
		break;

	    default:
	        panic ("compare type %d not implemented for field \"${fieldName}\"", compType);
	  }
	  break;
        }
}

#
# Generate an assignment to a string that may be a null
# string with a default value. If shortcut is true then the case where the
# string is null is taken care of elsewhere, otherwise we need to use the
# default value (or the empty string).
#
proc gen_assign_string_with_default {table fieldName varName rowName shortcut} {
    upvar ::ctable::fields::$fieldName field

    if {$shortcut && !([info exists field(notnull)] && $field(notnull))} {
	return "$varName = $rowName->$fieldName;"
    }
    if {[info exists field(default)]} {
	set default "\"[cquote $field(default)]\""
    } else {
	set default "\"\""
    }
    return "$varName = $rowName->$fieldName ? $rowName->$fieldName : $default;"
}

#
# Generate a declaration and an assignment to the length of a string that
# might be null. If it's null AND the shortcut doesn't mean we've taken care
# of this case elsewhere then use the length of the defaul value.
#
proc gen_assign_length_with_default {table fieldName varName rowName shortcut} {
    upvar ::ctable::fields::$fieldName field

    if {$shortcut && !([info exists field(notnull)] && $field(notnull))} {
	return "int $varName = $rowName->_${fieldName}Length;"
    }
    if {[info exists field(default)]} {
	set defaultLength [string length $field(default)]
    } else {
	set defaultLength 0
    }
    return "int $varName = $rowName->$fieldName ? $rowName->_${fieldName}Length : $defaultLength;"
}

#
# varstringCompSource - code we run subst over to generate a compare of 
# a string.
#
variable varstringCompSource {
        case $fieldEnum: {
          int     strcmpResult;
	  char *[gen_assign_string_with_default $table $fieldName string row 1]
	  [gen_assign_length_with_default $table $fieldName stringLength row 1]
	  char *string1 = NULL;

[gen_standard_comp_null_check_source $table $fieldName]

	  [gen_assign_string_with_default $table $fieldName string1 row1 0]
	  if ((compType == CTABLE_COMP_MATCH) || (compType == CTABLE_COMP_NOTMATCH) || (compType == CTABLE_COMP_MATCH_CASE) || (compType == CTABLE_COMP_NOTMATCH_CASE)) {
[gen_null_exclude_during_sort_comp $table $fieldName]
	      // matchMeansKeep will be 1 if matching means keep,
	      // 0 if it means discard
	      int matchMeansKeep = ((compType == CTABLE_COMP_MATCH) || (compType == CTABLE_COMP_MATCH_CASE));
	      struct ctableSearchMatchStruct *sm = component->clientData;

	      if (sm->type == CTABLE_STRING_MATCH_ANCHORED) {
		  char *field;
		  char *match;

		  exclude = !matchMeansKeep;
		  for (field = string, match = string1; *match != '*' && *match != '\0'; match++, field++) {
		      // printf("comparing '%c' and '%c'\n", *field, *match);
		      if (sm->nocase) {
			  if (tolower (*field) != tolower (*match)) {
			      exclude = matchMeansKeep;
			      break;
			  }
		      } else {
			  if (*field != *match) {
			      exclude = matchMeansKeep;
			      break;
			  }
		      }
		  }
		  // if we got here it was anchored and we now know the score
		  break;
	      } else if (sm->type == CTABLE_STRING_MATCH_UNANCHORED) {
	          exclude = (boyer_moore_search (sm, (unsigned char *)string, stringLength, sm->nocase) == NULL);
		  if (!matchMeansKeep) exclude = !exclude;
		  break;
	      } else if (sm->type == CTABLE_STRING_MATCH_PATTERN) {
	          exclude = !(Tcl_StringCaseMatch (string, string1, ((compType == CTABLE_COMP_MATCH) || (compType == CTABLE_COMP_NOTMATCH))));
		  if (!matchMeansKeep) exclude = !exclude;
		  break;
              } else {
		  panic ("software bug, sm->type unknown match type");
	      }
	  }

          strcmpResult = strcmp (string, string1);
[gen_standard_comp_switch_source $fieldName]
        }
}

#
# fixedstringCompSource - code we run subst over to generate a comapre of a 
# fixed-length string.
#
variable fixedstringCompSource {
        case $fieldEnum: {
          int     strcmpResult;

[gen_standard_comp_null_check_source $table $fieldName]
          strcmpResult = strncmp (row->$fieldName, row1->$fieldName, $length);
[gen_standard_comp_switch_source $fieldName]
        }
}

#
# binaryDataCompSource - code we run subst over to generate a comapre of a 
# binary data.
#
variable binaryDataCompSource {
        case $fieldEnum: {
          int              strcmpResult;

[gen_standard_comp_null_check_source $table $fieldName]
          strcmpResult = memcmp ((void *)&row->$fieldName, (void *)&row1->$fieldName, $length);
[gen_standard_comp_switch_source $fieldName]
        }
}

#
# tclobjCompSource - code we run subst over to generate a compare of 
# a tclobj for use in a search.
#
# this could be so wrong - there may be a way to keep it from generating
# the text -- right now we are doing a Tcl_GetStringFromObj in the
# routine that sets this up, maybe don't do that and figure out some
# way to compare objects (?)
#
variable tclobjCompSource {
        case $fieldEnum: {
          int      strcmpResult;

[gen_standard_comp_null_check_source $table $fieldName]
          strcmpResult = strcmp (Tcl_GetString (row->$fieldName), Tcl_GetString (row1->$fieldName));
[gen_standard_comp_switch_source $fieldName]
        }
}

#
# keyCompSource - code we run subst over to generate a compare of 
# a string.
#
variable keyCompSource {
        case $fieldEnum: {
          int     strcmpResult;

[gen_standard_comp_null_check_source $table $fieldName]
	  if ((compType == CTABLE_COMP_MATCH) || (compType == CTABLE_COMP_NOTMATCH) || (compType == CTABLE_COMP_MATCH_CASE) || (compType == CTABLE_COMP_NOTMATCH_CASE)) {
[gen_null_exclude_during_sort_comp $table $fieldName]
	      // matchMeansKeep will be 1 if matching means keep,
	      // 0 if it means discard
	      int matchMeansKeep = ((compType == CTABLE_COMP_MATCH) || (compType == CTABLE_COMP_MATCH_CASE));
	      struct ctableSearchMatchStruct *sm = component->clientData;

	      if (sm->type == CTABLE_STRING_MATCH_ANCHORED) {
		  char *field;
		  char *match;

		  exclude = !matchMeansKeep;
		  for (field = row->hashEntry.key, match = row1->hashEntry.key; *match != '*' && *match != '\0'; match++, field++) {
		      // printf("comparing '%c' and '%c'\n", *field, *match);
		      if (sm->nocase) {
			  if (tolower (*field) != tolower (*match)) {
			      exclude = matchMeansKeep;
			      break;
			  }
		      } else {
			  if (*field != *match) {
			      exclude = matchMeansKeep;
			      break;
			  }
		      }
		  }
		  // if we got here it was anchored and we now know the score
		  break;
	      } else if (sm->type == CTABLE_STRING_MATCH_UNANCHORED) {
	          exclude = (boyer_moore_search (sm, (unsigned char *)row->hashEntry.key, strlen(row->hashEntry.key), sm->nocase) == NULL);
		  if (!matchMeansKeep) exclude = !exclude;
		  break;
	      } else if (sm->type == CTABLE_STRING_MATCH_PATTERN) {
	          exclude = !(Tcl_StringCaseMatch (row->hashEntry.key, row1->hashEntry.key, ((compType == CTABLE_COMP_MATCH) || (compType == CTABLE_COMP_NOTMATCH))));
		  if (!matchMeansKeep) exclude = !exclude;
		  break;
              } else {
		  panic ("software bug, sm->type unknown match type");
	      }
	  }

          strcmpResult = strcmp (row->hashEntry.key, row1->hashEntry.key);
[gen_standard_comp_switch_source $fieldName]
        }
}


#####
#
# Generating Code To Set Fields In Rows
#
#####

variable fieldObjSetSource {
struct $table *${table}_make_row_struct () {
    struct $table *row;

    row = (struct $table *)ckalloc (sizeof (struct $table));
    ${table}_init (row);

    return row;
}

//
// Wrapper for hash search.
//
// Always succeeds unless using shared memory and we run out of shared memory
//
// Must handle this in caller beacuse we're not passing an interpreter in
//
struct $table *${table}_find_or_create (Tcl_Interp *interp, CTable *ctable, char *key, int *indexCtlPtr) {
    struct $table *row = NULL;
    static struct $table *nextRow = NULL;
    int flags = KEY_VOLATILE;
    char *key_value = key;

#ifdef WITH_SHARED_TABLES
    // If it's a shared table, the existing nextRow isn't usable
    if(nextRow && ctable->share_type == CTABLE_SHARED_MASTER) {
	ckfree((char *)nextRow);
	nextRow = NULL;
    }
#endif

    // Make sure the preallocated row is prepared
    if(!nextRow) {
#ifdef WITH_SHARED_TABLES
        if(ctable->share_type == CTABLE_SHARED_MASTER) {
	    nextRow = (struct $table *)shmalloc(ctable->share, sizeof(struct $table));
	    if(!nextRow) {
		if(ctable->share_panic) ${table}_shmpanic(ctable);
		TclShmError(interp, key);
	        return NULL;
	    }
	} else
#endif
	    nextRow = (struct $table *)ckalloc(sizeof(struct $table));

        ${table}_init (nextRow);
    }

#ifdef WITH_SHARED_TABLES
    if(ctable->share_type == CTABLE_SHARED_MASTER) {
        key_value = (char *)shmalloc(ctable->share, strlen(key)+1);
	if(!key_value) {
	    if(ctable->share_panic) ${table}_shmpanic(ctable);
	    TclShmError(interp, key);
	    return NULL;
	}
	strcpy(key_value, key);
	flags = KEY_STATIC;
    }
#endif

    row = (struct $table *)ctable_StoreHashEntry (ctable->keyTablePtr, key_value, (ctable_HashEntry *)nextRow, flags, indexCtlPtr);

    // If we used this row, forget the old row.
    if(*indexCtlPtr)
	nextRow = NULL;
#ifdef WITH_SHARED_TABLES
    else {
	if(flags == KEY_STATIC) {
	    // Don't need to "shmfree" because the key was never made visible to
	    // any readers.
	    shmdealloc(ctable->share, key_value);
	}
	// Don't keep a row around if it's shared, and don't need to shmfree
	// for the same reason
	if(ctable->share_type == CTABLE_SHARED_MASTER) {
	    shmdealloc(ctable->share, (char *)nextRow);
	    nextRow = NULL;
	}
    }
#endif

    if (*indexCtlPtr) {
	ctable_ListInsertHead (&ctable->ll_head, (ctable_BaseRow *)row, 0);
	ctable->count++;
	// printf ("created new entry for '%s'\n", key);
    } else {
	// printf ("found existing entry for '%s'\n", key);
    }

    return row;
}

int
${table}_set_fieldobj (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *obj, struct $table *row, Tcl_Obj *fieldObj, int indexCtl, int nocomplain)
{
    int field;

    if (Tcl_GetIndexFromObj (interp, fieldObj, ${table}_fields, "field", TCL_EXACT, &field) != TCL_OK) {
	if (nocomplain) {
	    Tcl_ResetResult(interp);
	    return TCL_OK;
	}
	return TCL_ERROR;
    }

    return ${table}_set (interp, ctable, obj, row, field, indexCtl);
}
}

variable fieldSetSource {
int
${table}_set (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *obj, struct $table *row, int field, int indexCtl) $leftCurly
}

variable fieldSetSwitchSource {
    switch ((enum ${table}_fields) field) $leftCurly
}

variable fieldObjGetSource {
struct $table *${table}_find (CTable *ctable, char *key) {
    ctable_HashEntry *hashEntry;

    hashEntry = ctable_FindHashEntry (ctable->keyTablePtr, key);
    if (hashEntry == (ctable_HashEntry *) NULL) {
        return (struct $table *) NULL;
    }
    
    return (struct $table *) hashEntry;
}

Tcl_Obj *
${table}_get_fieldobj (Tcl_Interp *interp, struct $table *row, Tcl_Obj *fieldObj)
{
    int field;

    if (Tcl_GetIndexFromObj (interp, fieldObj, ${table}_fields, "field", TCL_EXACT, &field) != TCL_OK) {
        return (Tcl_Obj *)NULL;
    }

    return ${table}_get (interp, row, field);
}

int
${table}_lappend_field (Tcl_Interp *interp, Tcl_Obj *destListObj, void *vPointer, int field)
{
    struct $table *row = vPointer;

    Tcl_Obj *obj = ${table}_get (interp, row, field);

    if (Tcl_ListObjAppendElement (interp, destListObj, obj) == TCL_ERROR) {
        return TCL_ERROR;
    }

    return TCL_OK;
}

int
${table}_lappend_fieldobj (Tcl_Interp *interp, void *vPointer, Tcl_Obj *fieldObj)
{
    struct $table *row = vPointer;
    Tcl_Obj *obj = ${table}_get_fieldobj (interp, row, fieldObj);

    if (obj == NULL) {
        return TCL_ERROR;
    }

    if (Tcl_ListObjAppendElement (interp, Tcl_GetObjResult (interp), obj) == TCL_ERROR) {
        return TCL_ERROR;
    }

    return TCL_OK;
}
}

variable lappendFieldAndNameObjSource {
int
${table}_lappend_field_and_name (Tcl_Interp *interp, Tcl_Obj *destListObj, void *vPointer, int field)
{
    struct $table *row = vPointer;
    Tcl_Obj   *obj;

    if (Tcl_ListObjAppendElement (interp, destListObj, ${table}_NameObjList[field]) == TCL_ERROR) {
        return TCL_ERROR;
    }

    obj = ${table}_get (interp, row, field);
    if (Tcl_ListObjAppendElement (interp, destListObj, obj) == TCL_ERROR) {
        return TCL_ERROR;
    }

    return TCL_OK;
}

int
${table}_lappend_field_and_nameobj (Tcl_Interp *interp, void *vPointer, Tcl_Obj *fieldObj)
{
    int        field;

    if (Tcl_GetIndexFromObj (interp, fieldObj, ${table}_fields, "field", TCL_EXACT, &field) != TCL_OK) {
        return TCL_ERROR;
    }

    return ${table}_lappend_field_and_name (interp, Tcl_GetObjResult (interp), vPointer, field); 
}

}

variable lappendNonnullFieldAndNameObjSource {
int
${table}_lappend_nonnull_field_and_name (Tcl_Interp *interp, Tcl_Obj *destListObj, void *vPointer, int field)
{
    struct $table *row = vPointer;
    Tcl_Obj   *obj;

    obj = ${table}_get (interp, row, field);
    if (obj == ${table}_NullValueObj) {
        return TCL_OK;
    }

    if (Tcl_ListObjAppendElement (interp, destListObj, ${table}_NameObjList[field]) == TCL_ERROR) {
        return TCL_ERROR;
    }

    if (Tcl_ListObjAppendElement (interp, destListObj, obj) == TCL_ERROR) {
        return TCL_ERROR;
    }

    return TCL_OK;
}

int
${table}_lappend_nonnull_field_and_nameobj (Tcl_Interp *interp, void *vPointer, Tcl_Obj *fieldObj)
{
    int        field;

    if (Tcl_GetIndexFromObj (interp, fieldObj, ${table}_fields, "field", TCL_EXACT, &field) != TCL_OK) {
        return TCL_ERROR;
    }

    return ${table}_lappend_nonnull_field_and_name (interp, Tcl_GetObjResult (interp), vPointer, field);
}

}

variable arraySetFromFieldSource {
int
${table}_array_set (Tcl_Interp *interp, Tcl_Obj *arrayNameObj, void *vPointer, int field)
{
    struct $table *row = vPointer;
    Tcl_Obj   *obj;

    obj = ${table}_get (interp, row, field);
    if (obj == ${table}_NullValueObj) {
        // it's null?  unset it from the array, might not be there, ignore error
        Tcl_UnsetVar2 (interp, Tcl_GetString (arrayNameObj), ${table}_fields[field], 0);
        return TCL_OK;
    }

    if (Tcl_ObjSetVar2 (interp, arrayNameObj, ${table}_NameObjList[field], obj, TCL_LEAVE_ERR_MSG) == (Tcl_Obj *)NULL) {
        return TCL_ERROR;
    }

    return TCL_OK;
}

int
${table}_array_set_with_nulls (Tcl_Interp *interp, Tcl_Obj *arrayNameObj, void *vPointer, int field)
{
    struct $table *row = vPointer;
    Tcl_Obj   *obj;

    obj = ${table}_get (interp, row, field);
    if (Tcl_ObjSetVar2 (interp, arrayNameObj, ${table}_NameObjList[field], obj, TCL_LEAVE_ERR_MSG) == (Tcl_Obj *)NULL) {
        return TCL_ERROR;
    }

    return TCL_OK;
}

}

#####
#
# Generating Code To Get Fields From A Rows
#
#####

variable fieldGetSource {
Tcl_Obj *
${table}_get (Tcl_Interp *interp, void *vPointer, int field) $leftCurly
    struct $table *row = vPointer;

    switch ((enum ${table}_fields) field) $leftCurly
}

variable fieldGetStringSource {
CONST char *
${table}_get_string (const void *vPointer, int field, int *lengthPtr, Tcl_Obj *utilityObj) $leftCurly
    int length;
    const struct $table *row = vPointer;

    if (lengthPtr == (int *) NULL) {
        lengthPtr = &length;
    }

    switch ((enum ${table}_fields) field) $leftCurly
}

#####
#
# Generating Code To Read And Write Tab-Separated Rows
#
#####

variable tabSepFunctionsSource {

void ${table}_dumpFieldNums(int *fieldNums, int nFields, char *msg)
{
    int i;

    fprintf(stderr, "%s, %d fields: ", msg, nFields);

    for(i = 0; i < nFields; i++) {
	int num = fieldNums[i];
	if(num == -1) fprintf(stderr, "* ");
	else fprintf(stderr, "%d=%s ", num, ${table}_fields[num]);
    }

    fprintf(stderr, "\n");
}

void
${table}_dstring_append_get_tabsep (CONST char *key, void *vPointer, int *fieldNums, int nFields, Tcl_DString *dsPtr, int noKeys, char *sepstr, int quoteType, char *nullString) {
    int              i;
    CONST char      *string;
    int              nChars;
    Tcl_Obj         *utilityObj = Tcl_NewObj();
    struct $table *row = vPointer;

    if (!noKeys) {
	int copy = 0;
	if(quoteType) {
	    copy = ctable_quoteString(&key, NULL, quoteType, sepstr);
	}
	Tcl_DStringAppend (dsPtr, key, -1);
	if(copy) {
	    ckfree((void *)key);
	    key = NULL;
	}
    }

    for (i = 0; i < nFields; i++) {
	if (!noKeys || (i > 0)) {
	    Tcl_DStringAppend (dsPtr, sepstr, -1);
	}

	if(nullString && ${table}_is_null(row, fieldNums[i])) {
	    Tcl_DStringAppend (dsPtr, nullString, -1);
	    continue;
	}

	string = ${table}_get_string (row, fieldNums[i], &nChars, utilityObj);
	if (nChars != 0) {
	    int copy = 0;
	    if (quoteType && ${table}_needs_quoting[fieldNums[i]]) {
		copy = ctable_quoteString(&string, &nChars, quoteType, sepstr);
	    }
	    Tcl_DStringAppend (dsPtr, string, nChars);
	    if(copy) {
		ckfree((void *)string);
		string = NULL;
	    }
	}
    }
    Tcl_DStringAppend (dsPtr, "\n", 1);
    Tcl_DecrRefCount (utilityObj);
}

void 
${table}_dstring_append_fieldnames (int *fieldNums, int nFields, Tcl_DString *dsPtr, int noKeys, char *sepstr)
{
    int i;

    if(!noKeys) {
    	Tcl_DStringAppend(dsPtr, "_key", 4);
    }

    for (i = 0; i < nFields; i++) {
	if (!noKeys || (i > 0)) {
	    Tcl_DStringAppend (dsPtr, sepstr, -1);
	}

	Tcl_DStringAppend(dsPtr, ${table}_fields[fieldNums[i]], -1);
    }
    Tcl_DStringAppend (dsPtr, "\n", 1);
}

int
${table}_get_fields_from_tabsep (Tcl_Interp *interp, char *string, int *nFieldsPtr, int **fieldNumsPtr, int *noKeysPtr, char *sepstr, int nocomplain)
{
    int    i;
    int    field;
    char  *tab;
    char   save = '\0';
    int    seplen = strlen(sepstr);
    int   *fieldNums = NULL;
    char  *s;
    int    nColumns;
    int    keyCol = -1;

    *noKeysPtr = 1;

    // find the number of fields and allocate space
    nColumns = 2;
    s = string;
    while((s = strstr(s, sepstr))) {
	nColumns++;
	s += strlen(sepstr);
    }
    fieldNums = (int *)ckalloc(nColumns * sizeof(*fieldNums));

    field = 0;
    while(string) {
	if ( (tab = strstr(string, sepstr)) ) {
	    save = *tab;
	    *tab = 0;
	}

	if(*noKeysPtr && field == 0 && strcmp(string, "_key") == 0) {
	    *noKeysPtr = 0;
	    keyCol = 0;
	} else {
	    int num = -1;
	    for(i = 0; ${table}_fields[i]; i++) {
	        if(strcmp(string, ${table}_fields[i]) == 0) {
		    num = i;
		    break;
		}
	    }

	    if(!nocomplain && num == -1) {
                Tcl_AppendResult (interp, "Unknown field \"", string, "\" in ${table}", (char *)NULL);
		ckfree((void *)fieldNums);
                return TCL_ERROR;
            }

	    if(num == ${table}_keyField) {
		if(keyCol>= 0)
		    num = -1;
		else
		    keyCol = num;
	    }

	    fieldNums[field++] = num;
	}

	if(tab) {
	    *tab = save;
	    tab += seplen;
	}

	string = tab;
    }

    *nFieldsPtr = field;
    *fieldNumsPtr = fieldNums;

    return TCL_OK;
}

int
${table}_export_tabsep (Tcl_Interp *interp, CTable *ctable, CONST char *channelName, int *fieldNums, int nFields, char *pattern, int noKeys, int withFieldNames, char *sepstr, char *term, int quoteType, char *nullString) {
    Tcl_Channel             channel;
    int                     mode;
    Tcl_DString             dString;
    char                   *key;
    ctable_BaseRow         *row;

    if ((channel = Tcl_GetChannel (interp, channelName, &mode)) == NULL) {
        return TCL_ERROR;
    }

    if ((mode & TCL_WRITABLE) == 0) {
	Tcl_AppendResult (interp, "channel \"", channelName, "\" not writable", (char *)NULL);
        return TCL_ERROR;
    }

    Tcl_DStringInit (&dString);

    if (withFieldNames) {

        Tcl_DStringSetLength (&dString, 0);

	${table}_dstring_append_fieldnames (fieldNums, nFields, &dString, noKeys, sepstr);

	if (Tcl_WriteChars (channel, Tcl_DStringValue (&dString), Tcl_DStringLength (&dString)) < 0) {
	    Tcl_AppendResult (interp, "write error on channel \"", channelName, "\"", (char *)NULL);
	    Tcl_DStringFree (&dString);
	    return TCL_ERROR;
	}

    }

    CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {
	// if there's no pattern and no keys has been set, no need to
	// get the key
        if ((pattern == NULL) && noKeys) {
	    key = NULL;
	} else {
	    // key is needed and if there's a pattern, check it
	    key = row->hashEntry.key;
	    if ((pattern != NULL) && (!Tcl_StringCaseMatch (key, pattern, 1))) continue;
	}

        Tcl_DStringSetLength (&dString, 0);

	${table}_dstring_append_get_tabsep (key, (struct ${table} *)row, fieldNums, nFields, &dString, noKeys, sepstr, quoteType, nullString);

	if (Tcl_WriteChars (channel, Tcl_DStringValue (&dString), Tcl_DStringLength (&dString)) < 0) {
	    Tcl_AppendResult (interp, "write error on channel \"", channelName, "\"", (char *)NULL);
	    Tcl_DStringFree (&dString);
	    return TCL_ERROR;
	}
    }

    Tcl_DStringFree (&dString);

    if(term) {
	if (Tcl_WriteChars (channel, term, strlen(term)) < 0 || Tcl_WriteChars(channel, "\n", 1) < 0) {
	    Tcl_AppendResult (interp, "write error on channel \"", channelName, "\"", (char *)NULL);
	    return TCL_ERROR;
	}
    }

    return TCL_OK;
}

int
${table}_set_from_tabsep (Tcl_Interp *interp, CTable *ctable, char *string, int *fieldIds, int nFields, int keyColumn, char *sepstr, char *nullString, int quoteType) {
    struct $table *row;
    char          *key;
    char          *field;
    int            indexCtl;
    int            i;
    int		   col;
    Tcl_Obj       *utilityObj = Tcl_NewObj ();
    char           keyNumberString[32];
    char	  *keyCopy = NULL;
    int		   seplen = strlen(sepstr);
    char	   save = '\0';

    if (keyColumn == -1) {
        sprintf (keyNumberString, "%d", ctable->autoRowNumber++);
	key = keyNumberString;
    } else {
        // find the beginning of the "keyColumn"th column in the string.
        for (key = string, i = 0; key && i < keyColumn; i++) {
	    key = strstr(key, sepstr);
	    if(key) key += seplen;
        }
        if (key) {
	    char *keyEnd = strstr(key, sepstr);
	    if(keyEnd) {
		save = *keyEnd;
		*keyEnd = 0;
	    }
	    keyCopy = ckalloc(strlen(key)+1);
	    if(quoteType)
		ctable_copyDequoted(keyCopy, key, -1, quoteType);
	    else
		strcpy(keyCopy, key);
	    key = keyCopy;
	    if(keyEnd) *keyEnd = save;
        }
	if(!key)
	    key = "";
    }

    row = ${table}_find_or_create (interp, ctable, key, &indexCtl);
    if(!row) {
	return TCL_ERROR;
    }

    for (col = i = 0; col < nFields; i++) {
	if(string) {
	    field = string;
            string = strstr (string, sepstr);
	    if(string) {
	        *string = '\0';
	        string += seplen;
	    }
	} else {
	    field = nullString ? nullString : "";
	}

	if(i == keyColumn) {
	    continue;
	}
	if(fieldIds[col] == -1) {
	    col++;
	    continue;
	}

	if(nullString == NULL ||
	   ${table}_nullable_fields[fieldIds[col]] == 0 ||
	   (field != nullString &&
	    field[0] != nullString[0] &&
	    strcmp(field, nullString) != 0)
	) {
	    if (${table}_needs_quoting[fieldIds[col]] && quoteType)
		ctable_dequoteString(field, -1, quoteType);

	    Tcl_SetStringObj (utilityObj, field, -1);
	    if (${table}_set (interp, ctable, utilityObj, row, fieldIds[col], indexCtl) == TCL_ERROR) {
	        Tcl_DecrRefCount (utilityObj);
	        return TCL_ERROR;
	    }
	}

	col++;
    }

    if (indexCtl == CTABLE_INDEX_NEW)
        if(${table}_index_defaults(interp, ctable, row) == TCL_ERROR)
	    return TCL_ERROR;

    Tcl_DecrRefCount (utilityObj);
    if(keyCopy) ckfree(keyCopy);
    return TCL_OK;
}

int
${table}_import_tabsep (Tcl_Interp *interp, CTable *ctable, CONST char *channelName, int *fieldNums, int nFields, char *pattern, int noKeys, int withFieldNames, char *sepstr, char *skip, char *term, int nocomplain, int withNulls, int quoteType, char *nullString) {
    Tcl_Channel      channel;
    int              mode;
    Tcl_Obj         *lineObj = NULL;
    char            *string;
    int              recordNumber = 0;
    char             keyNumberString[32];
    int		     keyColumn;
    int		     i;
    int		     seplen = strlen(sepstr);
    char	     save = '\0';
    int		     col;
    int		    *newFieldNums = NULL;
    int	             status = TCL_OK;

    if ((channel = Tcl_GetChannel (interp, channelName, &mode)) == NULL) {
        return TCL_ERROR;
    }

    if ((mode & TCL_READABLE) == 0) {
	Tcl_AppendResult (interp, "channel \"", channelName, "\" not readable", (char *)NULL);
        return TCL_ERROR;
    }

    /* Don't allocate this until necessary */
    lineObj = Tcl_NewObj();

    /* If no fields, read field names from first row */
    if(withFieldNames) {
	do {
            Tcl_SetStringObj (lineObj, "", 0);
            if (Tcl_GetsObj (channel, lineObj) <= 0) {
	        Tcl_DecrRefCount (lineObj);
	        return TCL_OK;
	    }
	    string = Tcl_GetString (lineObj);
	} while(skip && Tcl_StringMatch(string, skip));

	if (${table}_get_fields_from_tabsep(interp, string, &nFields, &newFieldNums, &noKeys, sepstr, nocomplain) == TCL_ERROR) {
	    status = TCL_ERROR;
	    goto cleanup;
	}
	fieldNums = newFieldNums;
    }

    if(noKeys) {
	keyColumn = -1;
    } else {
	keyColumn = 0;
    }

    for(col = i = 0; i < nFields; i++) {
	if(fieldNums[i] == ${table}_keyField) {
	    keyColumn = i;
	} else {
	    if(col != i) {
	        fieldNums[col] = fieldNums[i];
	    }
	    col++;
	}
    }
    if(col != i)
	nFields--;

//${table}_dumpFieldNums(fieldNums, nFields, "after key check");
    if(withNulls && !nullString) {
	int nullLen;

	nullString = Tcl_GetStringFromObj (${table}_NullValueObj, &nullLen);
    }

    while (1) {
	char            *key;

	do {
            Tcl_SetStringObj (lineObj, "", 0);
	    if (Tcl_GetsObj (channel, lineObj) <= 0) {
		goto done;
	    }

	    string = Tcl_GetString (lineObj);

	    if(term && term[0] && Tcl_StringCaseMatch (string, term, 1)) goto done;
	} while(skip && Tcl_StringMatch(string, skip));

	// if pattern exists, see if it does not match key and if so, skip
	if (pattern != NULL) {
	    for (key = string, i = 0; key && i < keyColumn; i++) {
		key = strstr(key, sepstr);
		if(key) key += seplen;
	    }
	    if (key) {
		char *keyEnd = strstr(key, sepstr);
	        if(keyEnd) {
		    save = *keyEnd;
		    *keyEnd = 0;
		}

	        if (!Tcl_StringCaseMatch (string, pattern, 1)) continue;
		if(keyEnd) *keyEnd = save;
	    }
	}

	if (${table}_set_from_tabsep (interp, ctable, string, fieldNums, nFields, keyColumn, sepstr, nullString, quoteType) == TCL_ERROR) {
	    char lineNumberString[32];

	    sprintf (lineNumberString, "%d", recordNumber + 1);
            Tcl_AppendResult (interp, " while reading line ", lineNumberString, " of input", (char *)NULL);
	    status = TCL_ERROR;
	    goto cleanup;
	}

	recordNumber++;
    }
done:

    if(noKeys)
    {
       sprintf (keyNumberString, "%d", ctable->autoRowNumber - 1);
       Tcl_SetObjResult (interp, Tcl_NewStringObj (keyNumberString, -1));
    }

cleanup:
    if(lineObj) {
	Tcl_DecrRefCount (lineObj);
    }

    if(newFieldNums) {
	ckfree((void *)newFieldNums);
    }

    return status;
}
}

#
# new_table - the proc that starts defining a table, really, a meta table, and
#  also following it will be the definition of the structure itself. Clears
# all per-table variables in ::ctable::
#
proc new_table {name} {
    variable table
    variable booleans
    variable nonBooleans
    variable fields
    variable fieldList
    variable keyField
    variable keyFieldName

    set table $name

    set booleans ""
    set nonBooleans ""
    unset -nocomplain fields
    set fieldList ""
    unset -nocomplain keyField
    unset -nocomplain keyFieldName

    foreach var [info vars ::ctable::fields::*] {
        unset -nocomplain $var
    }
}

#
# end_table - proc that declares the end of defining a table - currently does
#  nothing
#
proc end_table {} {
}

#
# Is this a legal field name.
#
# Special fields are automatically legal.
#
proc is_legal {fieldName} {
    variable specialFieldNames
    if {[lsearch $specialFieldNames $fieldName] != -1} {
	return 1
    }
    return [regexp {^[a-zA-Z][_a-zA-Z0-9]*$} $fieldName]
}

#
# deffield - helper for defining fields.
#
proc deffield {fieldName argList {listName nonBooleans}} {
    variable fields
    variable fieldList
    variable $listName
    variable ctableTypes
    variable reservedWords

    if {[lsearch -exact $reservedWords $fieldName] >= 0} {
        error "illegal field name \"$fieldName\" -- it's a reserved word"
    }

    if {![is_legal $fieldName]} {
        error "field name \"$fieldName\" must start with a letter and can only contain letters, numbers, and underscores"
    }

    if {[llength $argList] % 2 != 0} {
        error "number of values in field '$fieldName' definition arguments ('$argList') must be even"
    }

    array set argHash $argList

    # If "key" is still in the option list, then it's not on the right type
    if {[info exists argHash(key)] && $argHash(key)} {
	error "field '$fieldName' is the wrong type for a key"
    }

    # If it's got a default value, then it must be notnull
    if {[info exists argHash(default)]} {
	if {[info exists argHash(notnull)]} {
	    if {!$argHash(notnull)} {
		error "field '$fieldName' must not be null"
	    }
	} else {
	    set argHash(notnull) 1
	    lappend argList notnull 1
	}
    }

    set fields($fieldName) [linsert $argList 0 name $fieldName]
    array set ::ctable::fields::$fieldName $fields($fieldName)

    lappend fieldList $fieldName
    lappend $listName $fieldName
}

#
# boolean - define a boolean field
#
proc boolean {fieldName args} {
    deffield $fieldName [linsert $args 0 type boolean] booleans
}

#
# fixedstring - define a fixed-length string field
#
proc fixedstring {fieldName length args} {
    array set field $args

    # if it's defined notnull, it must have a default string
    if {[info exists field(notnull)] && $field(notnull)} {
	if {![info exists field(default)]} {
	    error "fixedstring \"$fieldName\" is defined notnull but has no default string, which is required"
	}
    }

    # if there's a default string, it must be the correct width
    if {[info exists field(default)]} {
        if {[string length $field(default)] != $length} {
	    error "fixedstring \"$fieldName\" default string \"[cquote $field(default)]\" must match length \"$length\""
	}
    }

    deffield $fieldName [linsert $args 0 type fixedstring length $length needsQuoting 1]
}

#
# varstring - define a variable-length string field
#
# If "key 1" is in the argument list, make it a "key" instead
#
proc varstring {fieldName args} {
    if {[set i [lsearch -exact "key" $args]] % 2 == 0} {
	incr i
	if {[lindex $args $i]} {
	    return [eval [list key $fieldName] $args]
	}
    }
    deffield $fieldName [linsert $args 0 type varstring needsQuoting 1]
}

#
# char - define a single character field -- this should probably just be
#  fixedstring[1] but it's simpler.  shrug.
#
proc char {fieldName args} {
    deffield $fieldName [linsert $args 0 type char needsQuoting 1]
}

#
# mac - define a mac address field
#
proc mac {fieldName args} {
    deffield $fieldName [linsert $args 0 type mac]
}

#
# short - define a short integer field
#
proc short {fieldName args} {
    deffield $fieldName [linsert $args 0 type short]
}

#
# int - define an integer field
#
proc int {fieldName args} {
    deffield $fieldName [linsert $args 0 type int]
}

#
# long - define a long integer field
#
proc long {fieldName args} {
    deffield $fieldName [linsert $args 0 type long]
}

#
# wide - define a wide integer field -- should always be at least 64 bits
#
proc wide {fieldName args} {
    deffield $fieldName [linsert $args 0 type wide]
}

#
# float - define a floating point field
#
proc float {fieldName args} {
    deffield $fieldName [linsert $args 0 type float]
}

#
# double - define a double-precision floating point field
#
proc double {fieldName args} {
    deffield $fieldName [linsert $args 0 type double]
}

#
# inet - define an IPv4 address field
#
proc inet {fieldName args} {
    deffield $fieldName [linsert $args 0 type inet]
}

#
# tclobj - define an straight-through Tcl_Obj
#
proc tclobj {fieldName args} {
    deffield $fieldName [linsert $args 0 type tclobj needsQuoting 1]
}

#
# key - define a pseudofield for the key
#
proc key {name args} {
    # Sanitize arguments
    if {[set i [lsearch -exact  $args key]] % 2 == 0} {
	set args [lreplace $args $i [expr $i + 1]]
    }

    # Only allow one key field
    if [info exists ::ctable::keyFieldName] {
	# But only complain if it's not an internal "special" field
        if {[lsearch $::ctable::specialFieldNames $name] == -1} {
	    error "Duplicate key field"
	}
	return
    }

    deffield $name [linsert $args 0 type key needsQuoting 1 notnull 1]
    set ::ctable::keyField [lsearch $::ctable::fieldList $name]
    if {$::ctable::keyField == -1} {
	unset ::ctable::keyField
    } else {
	set ::ctable::keyFieldName $name
    }
}

#
# putfield - write out a field definition when emitting a C struct
#
proc putfield {type fieldName {comment ""}} {
    if {[string index $fieldName 0] != "*"} {
        set fieldName " $fieldName"
    }

    if {$comment != ""} {
        set comment " /* $comment */"
    }
    emit [format "    %-20s %s;%s" $type $fieldName $comment]
}

#
# ctable_type_to_enum - return a type mapped to the name we use when
#  creating or referencing an enumerated list of ctable types.
#
proc ctable_type_to_enum {type} {
    return "CTABLE_TYPE_[string toupper $type]"
}

#
# gen_ctable_type_stuff - # generate an array of char pointers to the type names
#
proc gen_ctable_type_stuff {} {
    variable ctableTypes
    variable leftCurly
    variable rightCurly

    emit "static char *ctableTypes\[\] = $leftCurly"
    foreach type $ctableTypes {
        emit "    \"$type\","
    }
    emit "    (char *) NULL"
    emit "$rightCurly;"
    emit ""
}

#
# gen_defaults_subr - gen code to set a row to default values
#
proc gen_defaults_subr {struct} {
    variable table
    variable fields
    variable withSharedTables
    variable withDirty
    variable fieldList
    variable leftCurly
    variable rightCurly

    set baseCopy ${struct}_basecopy

    emit "void ${struct}_init(struct $struct *row) $leftCurly"
    emit "    static int firstPass = 1;"
    emit "    static struct $struct $baseCopy;"
    emit ""
    emit "    if (firstPass) $leftCurly"
    emit "        int i;"
    emit "        firstPass = 0;"
    emit ""
    emit "        $baseCopy.hashEntry.key = NULL;"

    if {$withSharedTables} {
        emit "        $baseCopy._row_cycle = LOST_HORIZON;"
    }

    emit ""
    emit "        for(i = 0; i < [string toupper $table]_NLINKED_LISTS; i++) $leftCurly"
    emit "	      $baseCopy._ll_nodes\[i].next = NULL;"
    emit "	      $baseCopy._ll_nodes\[i].prev = NULL;"
    emit "	      $baseCopy._ll_nodes\[i].head = NULL;"
    emit "	  $rightCurly"
    emit ""

    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	switch $field(type) {
	    key {
		# No work to do
	    }

	    varstring {
	        emit "        $baseCopy.$fieldName = (char *) NULL;"
		emit "        $baseCopy._${fieldName}Length = 0;"
		emit "        $baseCopy._${fieldName}AllocatedLength = 0;"

		if {![info exists field(notnull)] || !$field(notnull)} {
		    if {[info exists field(default)]} {
			emit "        $baseCopy._${fieldName}IsNull = 0;"
		    } else {
			emit "        $baseCopy._${fieldName}IsNull = 1;"
		    }
		}
	    }

	    fixedstring {
	        if {[info exists field(default)]} {
		    emit "        strncpy ($baseCopy.$fieldName, \"[cquote $field(default)]\", $field(length));"
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 0;"
		    }
		} else {
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 1;"
		    }
		}
	    }

	    mac {
		if {[info exists field(default)]} {
		    emit "        $baseCopy.$fieldName = *ether_aton (\"$field(default)\");"
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 0;"
		    }
		} else {
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 1;"
		    }
		}
	    }

	    inet {
		if {[info exists field(default)]} {
		    emit "        inet_aton (\"$field(default)\", &$baseCopy.$fieldName);"
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 0;"
		    }
		} else {
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 1;"
		    }
		}
	    }

	    char {
	        if {[info exists field(default)]} {
		    emit "        $baseCopy.$fieldName = '[cquote [string index $field(default) 0] {'}]';"
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 0;"
		    }
		} else {
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 1;"
		    }
		}
	    }

	    tclobj {
	        emit "        $baseCopy.$fieldName = (Tcl_Obj *) NULL;"
		if {![info exists field(notnull)] || !$field(notnull)} {
		    emit "        $baseCopy._${fieldName}IsNull = 1;"
		}
	    }

	    default {
	        if {[info exists field(default)]} {
	            emit "        $baseCopy.$fieldName = $field(default);"
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 0;"
		    }
		} else {
		    if {![info exists field(notnull)] || !$field(notnull)} {
			emit "        $baseCopy._${fieldName}IsNull = 1;"
		    }
		}
	    }
	}
    }

    emit "    $rightCurly"
    emit ""
    emit "    *row = $baseCopy;"

    emit "$rightCurly"
    emit ""

    emit "int ${struct}_index_defaults(Tcl_Interp *interp, CTable *ctable, struct $struct *row) $leftCurly"

# emit "printf(\"${struct}_index_defaults(...);\\n\");"
    set fieldnum 0 ; # postincremented 0 .. fields
    set listnum 0  ; # preincrementd 1 .. lists+1
    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	if {[info exists field(indexed)] && $field(indexed)} {
	    incr listnum
	    unset -nocomplain def
	    if {[info exists field(default)]} {
		set def $field(default)
	    } elseif {[info exists field(notnull)] && $field(notnull)} {
		set def ""
	    }
	    if {[info exists def]} {
		emit "// Field \"$fieldName\" ($fieldnum) index $listnum:"
# emit "printf(\"ctable->skipLists\[$fieldnum] == %08lx\\n\",  (long)ctable->skipLists\[$fieldnum]);"

# emit "printf(\"row->_ll_nodes\[$listnum].head == %08lx\\n\",  (long)row->_ll_nodes\[$listnum].head);"

	        emit "    if(ctable->skipLists\[$fieldnum] && row->_ll_nodes\[$listnum].head == NULL) $leftCurly"
if 0 {
emit "fprintf(stderr, \"row->_ll_nodes\[$listnum] = { 0x%lx 0x%lx 0x%lx }\","
emit "    (long)row->_ll_nodes\[$listnum].head,"
emit "    (long)row->_ll_nodes\[$listnum].prev,"
emit "    (long)row->_ll_nodes\[$listnum].next);"
emit "fprintf(stderr, \"Inserting $fieldName into new row for $struct\\n\");"
}
	        if {"$def" != "" && "$field(type)" == "varstring"} {
		    emit "        row->$fieldName = \"[cquote $def]\";"
	        }
	        emit "        if (ctable_InsertIntoIndex (interp, ctable, row, $fieldnum) == TCL_ERROR)"
	        emit "            return TCL_ERROR;"
	        if {"$def" != "" && "$field(type)" == "varstring"} {
	            emit "        row->$fieldName = NULL;"
	        }
	        emit "    $rightCurly"
	    } else {
		emit "// Field \"$fieldName\" ($fieldnum) index $listnum no default"
	    }
	} else {
	    emit "// Field \"$fieldName\" ($fieldnum) not indexed"
        }
        incr fieldnum
    }

    emit "    return TCL_OK;"

    emit "$rightCurly"
    emit ""
}

variable deleteRowHelperSource {
void ${table}_deleteKey(CTable *ctable, struct ${table} *row, int free_shared)
{
    if(!row->hashEntry.key)
	return;

#ifdef WITH_SHARED_TABLES
    if(ctable->share_type == CTABLE_SHARED_MASTER) {
	if(free_shared)
	    shmfree(ctable->share, (void *)row->hashEntry.key);
    } else
#endif
    ckfree(row->hashEntry.key);
    row->hashEntry.key = NULL;
}
 
void ${table}_deleteHashEntry(CTable *ctable, struct ${table} *row)
{
#ifdef WITH_SHARED_TABLES
    if(row->hashEntry.key && ctable->share_type == CTABLE_SHARED_MASTER) {
	shmfree(ctable->share, (void *)row->hashEntry.key);
	row->hashEntry.key = NULL;
    }
#endif
    ctable_DeleteHashEntry (ctable->keyTablePtr, (ctable_HashEntry *)row);
}
}

#
# gen_delete_subr - gen code to delete (free) a row
#
proc gen_delete_subr {subr struct} {
    variable table
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly
    variable withSharedTables
    variable deleteRowHelperSource

    emit [string range [subst -nobackslashes -nocommands $deleteRowHelperSource] 1 end-1]

    emit "void ${subr}(CTable *ctable, void *vRow, int indexCtl) {"
    emit "    struct $struct *row = vRow;"
    if {$withSharedTables} {
        emit "    // 'final' means 'shared memory will be deleted anyway, just zero out'"
	emit "    int             final = indexCtl == CTABLE_INDEX_DESTROY_SHARED;"
	emit "    int             is_master = ctable->share_type == CTABLE_SHARED_MASTER;"
	emit "    int             is_shared = ctable->share_type != CTABLE_SHARED_NONE;"
    }
    emit ""
    emit "    // If there's an index, AND we're not deleting all indices"
    emit "    if (indexCtl == CTABLE_INDEX_NORMAL) $leftCurly"
    emit "        ctable_RemoveFromAllIndexes (ctable, (void *)row);"
    if {$withSharedTables} {
	emit "        ${table}_deleteKey(ctable, row, TRUE);"
    }
    emit "        ctable_DeleteHashEntry (ctable->keyTablePtr, (ctable_HashEntry *)row);"
    emit "    $rightCurly else"
    emit "        ${table}_deleteKey(ctable, row, indexCtl != CTABLE_INDEX_DESTROY_SHARED);"
    emit ""

    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	switch $field(type) {
	    varstring {
    		if {$withSharedTables} {
	            emit "    if (row->$fieldName != (char *) NULL) {"
		    emit "	  if(!is_shared || indexCtl == CTABLE_INDEX_PRIVATE)"
		    emit "            ckfree ((void *)row->$fieldName);"
		    emit "        else if(is_master && !final)"
		    emit "            shmfree(ctable->share, (char *)row->$fieldName);"
		    emit "    }"
		} else {
	            emit "    if (row->$fieldName != (char *) NULL) ckfree ((void *)row->$fieldName);"
		}
	    }
	}
    }
    if {$withSharedTables} {
        emit "    if(!is_shared || indexCtl == CTABLE_INDEX_PRIVATE)"
	emit "        ckfree ((void *)row);"
	emit "    else if(is_master && !final)"
	emit "        shmfree(ctable->share, (char *)row);"
    } else {
        emit "    ckfree ((void *)row);"
    }

    emit "}"
    emit ""
}


variable isNullSubrSource {
int ${table}_obj_is_null(Tcl_Obj *obj) {
    char     *nullValueString;
    int       nullValueLength;

    char     *objString;
    int       objStringLength;

     nullValueString = Tcl_GetStringFromObj (${table}_NullValueObj, &nullValueLength);
     objString = Tcl_GetStringFromObj (obj, &objStringLength);

    if (nullValueLength != objStringLength) {
        return 0;
    }

    if (nullValueLength == 0) {
        return 1;
    }

    if (*nullValueString != *objString) {
        return 0;
    }

    return (strncmp (nullValueString, objString, nullValueLength) == 0);
}

}

#
# gen_is_null_subr - gen code to determine if an object contains the null value
#
proc gen_obj_is_null_subr {} {
    variable table
    variable isNullSubrSource

    emit [string range [subst -nobackslashes -nocommands $isNullSubrSource] 1 end-1]
}

#
# sanity_check - prior to generating everything, make sure what we're being
#  asked to do is reasonable
#
proc sanity_check {} {
    variable fieldList
    variable table

    if {[llength $fieldList] == 0} {
        error "no fields defined in table \"$table\" -- at least one field must be defined in a table"
    }
}

#
# determine_how_many_linked_lists - count up the number of indexed
# nodes and any other stuff we want linked lists in the row for
#
# currently one defined for every row for a master linked list and one
# defined for each field that is defined indexed and not unique
# for use with skip lists to have indexes on fields of rows that have
# duplicate entries like, for instance, latitude and/or longitude.
#
proc determine_how_many_linked_lists_and_gen_field_index_table {} {
    variable nonBooleans
    variable fields
    variable fieldList
    variable booleans
    variable table
    variable leftCurly
    variable rightCurly

    set result "int ${table}_index_numbers\[\] = $leftCurly"
    set nLinkedLists 1
    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

        # if the "indexed" field doesn't exist or is 0, skip it
        if {![info exists field(indexed)] || !$field(indexed)} {
	    append result "\n    -1,"
            continue
        }
  
        # we're going to use linked lists even if it's not unique
if 0 {
        # if the "unique" field doesn't exist or isn't set to 0
        if {![info exists field(unique)] || $field(unique)} {
	    append result "\n    -1,"
            continue
        }
}
  
        # if we got here it's indexed and not unique,
        # i.e. field args include "indexed 1 unique 0"
        # generate them a list entry

	append result "\n[format "%6d" $nLinkedLists],"
  
        incr nLinkedLists
    }

    emit "[string range $result 0 end-1]\n$rightCurly;"

    return $nLinkedLists
}

#
# gen_struct - gen the table being defined's C structure
#
proc gen_struct {} {
    variable table
    variable booleans
    variable nonBooleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set nLinkedLists [determine_how_many_linked_lists_and_gen_field_index_table]
    set NLINKED_LISTS [string toupper $table]_NLINKED_LISTS
    emit "#define $NLINKED_LISTS $nLinkedLists"
    emit ""

    emit "struct $table $leftCurly"

    putfield "ctable_HashEntry" "hashEntry"

    # Generating this as #ifdef...#endif instead of conditionally generating
    # it here because otherwise the resulting code violates the POLA while
    # debugging.

    emit "#ifdef WITH_SHARED_TABLES"
    putfield "cell_t" "_row_cycle"
    emit #endif

    putfield "ctable_LinkedListNode"  "_ll_nodes\[$NLINKED_LISTS\]"

    foreach fieldName $nonBooleans {
	upvar ::ctable::fields::$fieldName field

	switch $field(type) {
	    varstring {
		putfield char "*$field(name)"
		putfield int  "_$field(name)Length"
		putfield int  "_$field(name)AllocatedLength"
	    }

	    fixedstring {
		putfield char "$field(name)\[$field(length)]"
	    }

	    wide {
		putfield "Tcl_WideInt" $field(name)
	    }

	    mac {
		putfield "struct ether_addr" $field(name)
	    }

	    inet {
		putfield "struct in_addr" $field(name)
	    }

	    tclobj {
		putfield "struct Tcl_Obj" "*$field(name)"
	    }

	    key {
		# Do nothing, it's in the hashEntry
	    }

	    default {
		putfield $field(type) $field(name)
	    }
	}
    }

    foreach fieldName $booleans {
	putfield "unsigned int" "$fieldName:1"
    }

    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	if {![info exists field(notnull)] || !$field(notnull)} {
	    putfield "unsigned int" _${fieldName}IsNull:1
	}
    }

    emit "$rightCurly;"
    emit ""
}

#
# emit_set_num_field - emit code to set a numeric field
#
proc emit_set_num_field {fieldName type} {
    variable numberSetSource
    variable table
    variable withSharedTables

    set typeText $type

    switch $type {
        short {
	    set newObjCmd Tcl_NewIntObj
	    set getObjCmd Tcl_GetIntFromObj
	    set typeText "int"
	}

        int {
	    set newObjCmd Tcl_NewIntObj
	    set getObjCmd Tcl_GetIntFromObj
	}

	long {
	    set newObjCmd Tcl_NewLongObj
	    set getObjCmd Tcl_GetLongFromObj

	}

	wide {
	    set type "Tcl_WideInt"
	    set newObjCmd Tcl_NewWideIntObj
	    set getObjCmd Tcl_GetWideIntFromObj
	    set typeText "Tcl_WideInt"
	}

	float {
	    set newObjCmd Tcl_NewDoubleObj
	    set getObjCmd Tcl_GetDoubleFromObj
	    set typeText "double"
	}

	double {
	    set newObjCmd Tcl_NewDoubleObj
	    set getObjCmd Tcl_GetDoubleFromObj
	}

	default {
	    error "unknown numeric field type: $type"
	}
    }

    set optname [field_to_enum $fieldName]

    emit [string range [subst $numberSetSource] 1 end-1]
}

#
# emit_set_standard_field - emit code to set a field that has a
# "set source" string to go with it and gets managed in a standard
#  way
#
proc emit_set_standard_field {fieldName setSourceVarName} {
    variable $setSourceVarName
    variable table

    set optname [field_to_enum $fieldName]
    emit [string range [subst [set $setSourceVarName]] 1 end-1]
}

#
# emit_set_varstring_field - emit code to set a varstring field
#
proc emit_set_varstring_field {table fieldName default defaultLength} {
    variable varstringSetSource

    set default [cquote $default]

    set optname [field_to_enum $fieldName]

    emit [string range [subst $varstringSetSource] 1 end-1]
}

#           
# emit_set_fixedstring_field - emit code to set a fixedstring field
#
proc emit_set_fixedstring_field {fieldName length} {
    variable fixedstringSetSource
    variable table

    upvar ::ctable::fields::$fieldName field

    if {[info exists field(default)]} {
	set default $field(default)
    } else {
	set default ""
    }

    set optname [field_to_enum $fieldName]

    emit [string range [subst $fixedstringSetSource] 1 end-1]
} 

variable fieldIncrSource {
int
${table}_incr (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *obj, struct $table *row, int field, int indexCtl) $leftCurly

    switch ((enum ${table}_fields) field) $leftCurly
}

variable numberIncrNullCheckSource {
	if (row->_${fieldName}IsNull) {
	    // incr of a null field, default to 0
	    if ((indexCtl == CTABLE_INDEX_NORMAL) && ctable->skipLists[field] != NULL) {
		if (ctable_RemoveNullFromIndex (interp, ctable, row, field) == TCL_ERROR) {
		    return TCL_ERROR;
		}
	    }
	    row->_${fieldName}IsNull = 0;
	    row->$fieldName = incrAmount;

	    if ((indexCtl != CTABLE_INDEX_PRIVATE) && (ctable->skipLists[field] != NULL)) {
		if (ctable_InsertIntoIndex (interp, ctable, row, field) == TCL_ERROR) {
		    return TCL_ERROR;
		}
	    }
	    break;
	}
}

#
# gen_number_incr_null_check_code - return code to check for null stuff
#  inside incr code, if the field doesn't prevent it by having notnull set,
#  in which case return nothing.
#
proc gen_number_incr_null_check_code {table fieldName} {
    variable numberIncrNullCheckSource
    upvar ::ctable::fields::$fieldName field

    if {[info exists field(notnull)] && $field(notnull)} {
        return ""
    } else {
        return [string range [subst -nobackslashes -nocommands $numberIncrNullCheckSource] 1 end-1]
    }
}

#
# gen_set_notnull_if_notnull - if the field has not been defined "not null",
#  return code to set that it isn't null
#
proc gen_set_notnull_if_notnull {table fieldName} {
    upvar ::ctable::fields::$fieldName field

    if {[info exists field(notnull)] && $field(notnull)} {
        return ""
    } else {
	return "row->_${fieldName}IsNull = 0;"
    }
}

#
# numberIncrSource - code we run subst over to generate a set of a standard
#  number such as an integer, long, double, and wide integer.  (We have to 
#  handle shorts and floats specially due to type coercion requirements.)
#
variable numberIncrSource {
      case $optname: {
	int incrAmount;

	if (Tcl_GetIntFromObj (interp, obj, &incrAmount) == TCL_ERROR) {
	    Tcl_AppendResult (interp, " while converting $fieldName increment amount", (char *)NULL);
	    return TCL_ERROR;
	}
[gen_number_incr_null_check_code $table $fieldName]

	if ((indexCtl == CTABLE_INDEX_NORMAL) && ctable->skipLists\[field] != NULL) {
	    ctable_RemoveFromIndex (ctable, row, field);
	}

	row->$fieldName += incrAmount;
[gen_set_notnull_if_notnull $table $fieldName]
	if ((indexCtl != CTABLE_INDEX_PRIVATE) && (ctable->skipLists\[field] != NULL)) {
	    if (ctable_InsertIntoIndex (interp, ctable, row, field) == TCL_ERROR) {
		return TCL_ERROR;
	    }
	}
	break;
      }
}

variable illegalIncrSource {
      case $optname: {
	Tcl_ResetResult (interp);
	Tcl_AppendResult (interp, "can't incr non-numeric field '$fieldName'", (char *)NULL);
	    return TCL_ERROR;
	}
}

variable incrFieldObjSource {
int
${table}_incr_fieldobj (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *obj, struct $table *row, Tcl_Obj *fieldObj, int indexCtl)
{
    int field;

    if (Tcl_GetIndexFromObj (interp, fieldObj, ${table}_fields, "field", TCL_EXACT, &field) != TCL_OK) {
        return TCL_ERROR;
    }

    return ${table}_incr (interp, ctable, obj, row, field, indexCtl);
}
}

#
# emit_incr_num_field - emit code to incr a numeric field
#
proc emit_incr_num_field {fieldName} {
    variable numberIncrSource
    variable table

    set optname [field_to_enum $fieldName]

    emit [string range [subst $numberIncrSource] 1 end-1]
}

#
# emit_incr_illegal_field - we run this to generate code that will cause
#  an error on attempts to incr the field that's being processed -- for
#  when incr is not a reasonable thing
#
proc emit_incr_illegal_field {fieldName} {
    variable illegalIncrSource

    set optname [field_to_enum $fieldName]
    emit [string range [subst -nobackslashes -nocommands $illegalIncrSource] 1 end-1]
}

#
# gen_incrs - emit code to incr all of the incr'able fields of the table being 
# defined
#
proc gen_incrs {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	switch $field(type) {
	    int {
		emit_incr_num_field $fieldName
	    }

	    long {
		emit_incr_num_field $fieldName
	    }

	    wide {
		emit_incr_num_field $fieldName
	    }

	    double {
		emit_incr_num_field $fieldName
	    }

	    short {
		emit_incr_num_field $fieldName
	    }

	    float {
	        emit_incr_num_field $fieldName
	    }

	    default {
	        emit_incr_illegal_field $fieldName
	    }
	}
    }
}

#
# gen_incr_function - create a *_incr routine that takes a pointer to the
# tcl interp, an object, a pointer to a table row and a field number,
# and incrs that field in that row by the the value extracted from the obj
#
proc gen_incr_function {table} {
    variable fieldIncrSource
    variable incrFieldObjSource
    variable leftCurly
    variable rightCurly

    emit [string range [subst -nobackslashes -nocommands $fieldIncrSource] 1 end-1]

    gen_incrs

    emit "    $rightCurly"
    emit "    return TCL_OK;"
    emit "$rightCurly"

    emit [string range [subst -nobackslashes -nocommands $incrFieldObjSource] 1 end-1]
}

#
# gen_sets - emit code to set all of the fields of the table being defined
#
proc gen_sets {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	switch $field(type) {
	    key {
		emit_set_standard_field $fieldName keySetSource
	    }

	    int {
		emit_set_num_field $fieldName int
	    }

	    long {
		emit_set_num_field $fieldName long
	    }

	    wide {
		emit_set_num_field $fieldName wide
	    }

	    double {
		emit_set_num_field $fieldName double
	    }

	    short {
		emit_set_num_field $fieldName int
	    }

	    float {
		emit_set_num_field $fieldName float
	    }

	    fixedstring {
		emit_set_fixedstring_field $fieldName $field(length)
	    }

	    varstring {
	        if {[info exists field(default)]} {
		    set default $field(default)
		    set defaultLength [string length $field(default)]
		} else {
		    set default ""
		    set defaultLength 0
		}
		emit_set_varstring_field $table $fieldName $default $defaultLength
	    }

	    boolean {
		emit_set_standard_field $fieldName boolSetSource
	    }

	    char {
		emit_set_standard_field $fieldName charSetSource
	    }

	    inet {
	        emit_set_standard_field $fieldName inetSetSource
	    }

	    mac {
	        emit_set_standard_field $fieldName macSetSource
	    }

	    tclobj {
	        emit_set_standard_field $fieldName tclobjSetSource
	    }

	    default {
	        error "attempt to emit set field of unknown type $field(type)"
	    }
	}
    }
}

#
# setNullSource - code that gets substituted for nonnull fields for set_null
#
variable setNullSource {
      case $optname: 
        if (row->_${myField}IsNull) {
	    break;
	}

	if ((indexCtl == CTABLE_INDEX_NORMAL) && (ctable->skipLists[field] != NULL)) {
	    ctable_RemoveFromIndex (ctable, row, field);
	}
        row->_${myField}IsNull = 1; 
	if ((indexCtl != CTABLE_INDEX_PRIVATE) && (ctable->skipLists[field] != NULL)) {
	    if (ctable_InsertNullIntoIndex (interp, ctable, row, field) == TCL_ERROR) {
		return TCL_ERROR;
	    }
	}
	break;
}

variable setNullNotNullSource {
      case $optname: 
        Tcl_AppendResult (interp, "can't set non-null field \"${myField}\" to be null", (char *)NULL);
	return TCL_ERROR;
}

#
# gen_set_null_function - emit C routine to set a specific field to null
#  in a given table and row
#
proc gen_set_null_function {table} {
    variable fieldList
    variable leftCurly
    variable rightCurly
    variable setNullSource
    variable setNullNotNullSource

    emit "int"
    emit "${table}_set_null (Tcl_Interp *interp, CTable *ctable, struct $table *row, int field, int indexCtl) $leftCurly"

    emit "    switch ((enum ${table}_fields) field) $leftCurly"

    foreach myField $fieldList {
	upvar ::ctable::fields::$myField field

        set optname [field_to_enum $myField]

	if {[info exists field(notnull)] && $field(notnull)} {
	    emit [subst -nobackslashes -nocommands $setNullNotNullSource]
	} else {
	    emit [subst -nobackslashes -nocommands $setNullSource]
	}
    }

    emit "    $rightCurly"
    emit "    return TCL_OK;"
    emit "$rightCurly"
    emit ""
}

#
# gen_is_null_function - emit C routine to test if a specific field is null
#  in a given table and row
#
proc gen_is_null_function {table} {
    variable fieldList
    variable leftCurly
    variable rightCurly

    emit "int"
    emit "${table}_is_null (struct $table *row, int field) $leftCurly"

    emit "    switch ((enum ${table}_fields) field) $leftCurly"

    foreach myField $fieldList {
	upvar ::ctable::fields::$myField field

        set optname [field_to_enum $myField]

	if {!([info exists field(notnull)] && $field(notnull))} {
	    emit "        case [field_to_enum $myField]:"
	    emit "            return row->_${myField}IsNull;"
	}
    }

    emit "        default:"
    emit "            return 0;"
    emit "    $rightCurly"
    emit "$rightCurly"
    emit ""
}

#
# put_metatable_source - emit the code to define the meta table (table-defining
# command)
#
proc put_metatable_source {table} {
    variable metaTableSource

    set Id {CTable template Id}

    emit [subst -nobackslashes -nocommands $metaTableSource]
}

#
# put_init_command_source - emit the code to initialize create within Tcl
# the command that will invoke the C command defined by 
# put_metatable_source
#
proc put_init_command_source {table} {
    variable extensionFragmentSource

    set Id {init extension Id}
    set NFIELDS [string toupper $table]_NFIELDS
    set NLINKED_LISTS [string toupper $table]_NLINKED_LISTS

    emit [subst -nobackslashes -nocommands $extensionFragmentSource]
}

#
# put_init_extension_source - emit the code to create the C functions that
# Tcl will expect to find when loading the shared library.
#
proc put_init_extension_source {extension extensionVersion} {
    variable initExtensionSource
    variable tables

    set Id {init extension Id}
    emit [subst -nobackslashes -nocommands $initExtensionSource]
}

#
# gen_set_function - create a *_set routine that takes a pointer to the
# tcl interp, an object, a pointer to a table row and a field number,
# and sets the value extracted from the obj into the field of the row
#
proc gen_set_function {table} {
    variable withDirty
    variable withSharedTables
    variable sanityChecks
    variable fieldObjSetSource
    variable fieldSetSource
    variable fieldSetSwitchSource
    variable leftCurly
    variable rightCurly

    emit [string range [subst -nobackslashes -nocommands $fieldSetSource] 1 end-1]

    if {$withSharedTables} {
        emit "    if (ctable->share_type == CTABLE_SHARED_MASTER) $leftCurly"
	if {$sanityChecks} {
	    emit "        if(ctable->share->map->cycle == LOST_HORIZON)"
	    emit "            panic(\"map->cycle not updated?\");"
	}
	emit "        row->_row_cycle = ctable->share->map->cycle;"
	emit "    $rightCurly"
    }

    emit [string range [subst -nobackslashes -nocommands $fieldSetSwitchSource] 1 end-1]
    gen_sets

    if {$withDirty} {
	emit "    row->_dirty = 1;"
    }

    emit "    $rightCurly"
    emit "    return TCL_OK;"
    emit "$rightCurly"

    emit [string range [subst -nobackslashes -nocommands $fieldObjSetSource] 1 end-1]

}

#
# gen_get_function - create a *_get routine that takes a pointer to the
#  tcl interp, an object pointer, a pointer to a table row and a field number,
#  and gets the value from the field of the row and store it into the
#  object.
#
#  Also create a *_get_fieldobj function that takes pointers to the same
#  tcl interpreter, object, and table row but takes an object containg
#  a string identifying the field, which is then looked up to identify
#  the field number and used in a call to the *_get function.
#
proc gen_get_function {table} {
    variable fieldObjGetSource
    variable lappendFieldAndNameObjSource
    variable lappendNonnullFieldAndNameObjSource
    variable arraySetFromFieldSource
    variable tabSepFunctionsSource
    variable fieldGetSource
    variable fieldGetStringSource
    variable leftCurly
    variable rightCurly

    emit [string range [subst -nobackslashes -nocommands $fieldGetSource] 1 end-1]
    gen_gets_cases
    emit "    $rightCurly"
    emit "    return TCL_OK;"
    emit "$rightCurly"

    emit [string range [subst -nobackslashes -nocommands $fieldObjGetSource] 1 end-1]

    emit [string range [subst -nobackslashes -nocommands $lappendFieldAndNameObjSource] 1 end-1]

    emit [string range [subst -nobackslashes -nocommands $lappendNonnullFieldAndNameObjSource] 1 end-1]

    emit [string range [subst -nobackslashes -nocommands $fieldGetStringSource] 1 end-1]
    gen_gets_string_cases
    emit "    $rightCurly"
    emit "    return TCL_OK;"
    emit "$rightCurly"

    emit [string range [subst -nobackslashes -nocommands $tabSepFunctionsSource] 1 end-1]

    emit [string range [subst -nobackslashes -nocommands $arraySetFromFieldSource] 1 end-1]
}

#
# gen_setup_routine - emit code to be run for this table type at shared 
#  libary load time
#
proc gen_setup_routine {table} {
    variable fieldList
    variable fields
    variable leftCurly
    variable rightCurly

    emit "void ${table}_setup (void) $leftCurly"

    # create and initialize all of the NameObj objects containing field
    # names as Tcl objects and increment their reference counts so 
    # (hopefully, heh) they'll never be deleted.
    #
    # also populate the *_NameObjList table
    #
    set position 0
    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	set nameObj [field_to_nameObj $table $fieldName]
        emit "    ${table}_NameObjList\[$position\] = $nameObj = Tcl_NewStringObj (\"$fieldName\", -1);"
	emit "    Tcl_IncrRefCount ($nameObj);"
	emit ""
	incr position
    }
    emit "    ${table}_NameObjList\[$position\] = (Tcl_Obj *) NULL;"
    emit ""

    set emptyObj ${table}_DefaultEmptyStringObj
    emit "    $emptyObj = Tcl_NewObj ();"
    emit "    Tcl_IncrRefCount ($emptyObj);"
    emit ""

    #
    # create and initialize string objects for varstring defaults
    #
    emit "    // defaults for varstring objects, if any"
    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	if {$field(type) != "varstring"} continue
	if {![info exists field(default)]} continue

	set defObj ${table}_${fieldName}DefaultStringObj

	if {$field(default) != ""} {
	    emit "    $defObj = Tcl_NewStringObj (\"[cquote $field(default)]\", -1);"
	    emit "    Tcl_IncrRefCount ($defObj);"
	    emit ""
	}
    }

    emit "    // initialize the null string object to the default (empty) value"
    emit "    ${table}_NullValueObj = Tcl_NewObj ();"
    emit "    Tcl_IncrRefCount (${table}_NullValueObj);"

    emit "$rightCurly"
    emit ""
}

# Generate allocator for shared ctables
proc gen_shared_string_allocator {} {
    variable withSharedTables
    variable table
    variable leftCurly
    variable rightCurly
    variable fieldList

    if {!$withSharedTables} {
	return
    }

    emit "int ${table}_setupDefaultStrings(CTable *ctable) $leftCurly"
    emit "    volatile char **defaultList;"
    emit "    volatile char *bundle;"
    emit ""

    emit "    // If it's not a shared table, just use constants"
    emit "    if(ctable->share_type == CTABLE_SHARED_NONE) $leftCurly"
    emit "        ctable->emptyString = \"\";"
    emit "        ctable->defaultStrings = ${table}_defaultStrings;"
    emit "        return TRUE;"
    emit "    $rightCurly"
    emit ""

    emit "    // reader table, use the master table"
    emit "    if(ctable->share_type == CTABLE_SHARED_READER) $leftCurly"
    emit "        ctable->emptyString = ctable->share_ctable->emptyString;"
    emit "        ctable->defaultStrings = ctable->share_ctable->defaultStrings;"
    emit "        return TRUE;"
    emit "    $rightCurly"
    emit ""

    # Generate and save the assignments
    # to the shared bundle, and set up bundle
    set bundle {\0}
    set bundleLen 1
    set fieldNum 0
    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	if {$field(type) != "varstring"} {
	    lappend sets "    defaultList\[$fieldNum] = NULL;"
	} elseif {![info exists field(default)]} {
	    lappend sets "    defaultList\[$fieldNum] = &bundle\[0];"
	} else {
	    set def [cquote $field(default)]
	    lappend sets "    defaultList\[$fieldNum] = &bundle\[$bundleLen];"

	    append bundle $def
	    incr bundleLen [string length $field(default)]
	    append bundle {\0}
	    incr bundleLen
	}
	incr fieldNum
    }

    emit "    // Allocate array and the strings themselves in one chunk"

    set totalSize "$fieldNum * sizeof (char *) + $bundleLen"
    emit "    defaultList = (volatile char **)shmalloc(ctable->share, $totalSize);"
    emit "    if (!defaultList) {"
    emit "        if(ctable->share_panic) ${table}_shmpanic(ctable);"
    emit "        return FALSE;"
    emit "    }"
    emit ""

    emit "    bundle = (char *)&defaultList\[$fieldNum];"
    emit ""

    emit "    memcpy((char *)bundle, \"$bundle\", $bundleLen);"
    emit ""

    emit "   ctable->emptyString = (char *)&bundle\[0];"
    emit "   ctable->defaultStrings = (char **)defaultList;"
    emit ""

    emit [join $sets "\n"]
    emit ""
    emit "    return TRUE;"
    emit "$rightCurly"
}

#
# gen_code - generate all of the code for the underlying methods for
#  managing a created table
#
proc gen_code {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable withSharedTables
    variable leftCurly
    variable rightCurly
    variable cmdBodySource

    # Used in cmdBodySubst:
    variable extension
    variable keyFieldName

    #set pointer "${table}_ptr"
    set pointer p

    set Id {CTable template Id}

    set nFields [string toupper $table]_NFIELDS

    set rowStruct $table

    gen_sanity_checks $table

    gen_allocate_function $table

    gen_insert_row_function $table

    gen_set_function $table

    gen_set_null_function $table

    gen_is_null_function $table

    gen_get_function $table

    gen_incr_function $table

    gen_field_compare_functions

    gen_sort_compare_function

    gen_search_compare_function

    gen_make_key_functions

    gen_shared_string_allocator

    emit [subst -nobackslashes -nocommands $cmdBodySource]
}

#
# gen_new_obj - given a data type, pointer name and field name, return
#  the C code to generate a Tcl object containing that element from the
#  pointer pointing to the named field.
#
proc gen_new_obj {type fieldName} {
    variable table
    upvar ::ctable::fields::$fieldName field

    switch $type {
	key {
	    return "Tcl_NewStringObj (row->hashEntry.key, -1)"
	}

	short {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewIntObj (row->$fieldName)"
	    } else {
		return "Tcl_NewIntObj (row->$fieldName)"
	    }
	}

	int {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewIntObj (row->$fieldName)"
	    } else {
		return "Tcl_NewIntObj (row->$fieldName)"
	    }
	}

	long {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewLongObj (row->$fieldName)"
	    } else {
		return "Tcl_NewLongObj (row->$fieldName)"
	    }
	}

	wide {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewWideIntObj (row->$fieldName)"
	    } else {
		return "Tcl_NewWideIntObj (row->$fieldName)"
	    }
	}

	double {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewDoubleObj (row->$fieldName)"
	    } else {
		return "Tcl_NewDoubleObj (row->$fieldName)"
	    }
	}

	float {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewDoubleObj (row->$fieldName)"
	    } else {
		return "Tcl_NewDoubleObj (row->$fieldName)"
	    }
	}

	boolean {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewBooleanObj (row->$fieldName)"
	    } else {
		return "Tcl_NewBooleanObj (row->$fieldName)"
	    }
	}

	varstring {
	    # if there's no default for the var string, the null pointer 
	    # response is the null
	    if {![info exists field(default)]} {
	        set defObj ${table}_NullValueObj
	    } else {
		if {$field(default) == ""} {
		    set defObj ${table}_DefaultEmptyStringObj
		} else {
		    set defObj ${table}_${fieldName}DefaultStringObj
		}
	    }

	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : ((row->$fieldName == (char *) NULL) ? $defObj  : Tcl_NewStringObj (row->$fieldName, row->_${fieldName}Length))"
	    } else {
		return "(row->$fieldName == (char *) NULL) ? $defObj  : Tcl_NewStringObj (row->$fieldName, row->_${fieldName}Length)"
	    }
	}

	char {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewStringObj (&row->$fieldName, 1)"
	    } else {
		return "Tcl_NewStringObj (&row->$fieldName, 1)"
	    }
	}

	fixedstring {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewStringObj (row->$fieldName, $field(length))"
	    } else {
		return "Tcl_NewStringObj (row->$fieldName, $field(length))"
	    }
	}

	inet {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewStringObj (inet_ntoa (row->$fieldName), -1)"
	    } else {
		return "Tcl_NewStringObj (inet_ntoa (row->$fieldName), -1)"
	    }
	}

	mac {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewStringObj (ether_ntoa (&row->$fieldName), -1)"
	    } else {
		return "Tcl_NewStringObj (ether_ntoa (&row->$fieldName), -1)"
	    }
	}

	tclobj {
	    if {![info exists field(notnull)] || !$field(notnull)} {
		return "row->_${fieldName}IsNull ? ${table}_NullValueObj : ((row->$fieldName == (Tcl_Obj *) NULL) ? Tcl_NewObj () : row->$fieldName)"
	    } else {
		return "((row->$fieldName == (Tcl_Obj *) NULL) ? Tcl_NewObj () : row->$fieldName)"
	    }
	}

	default {
	    error "no code to gen obj for type $type"
	}
    }
}

#
# gen_get_set_obj - given an object, a data type, pointer name and field name, 
#  return the C code to set a Tcl object to contain that element from the
#  pointer pointing to the named field.
#
# note: this is an inefficient way to get the value of varstrings,
# fixedstrings and chars, and can't even do tclobjs.  
#
# do what gen_get_string_cases does, or call its parent anyway *_get_string,
# to get string representations of those efficiently.
#
proc gen_get_set_obj {obj type fieldName} {
    variable fields
    variable table

    switch $type {
	short {
	    return "Tcl_SetIntObj ($obj, row->$fieldName)"
	}

	int {
	    return "Tcl_SetIntObj ($obj, row->$fieldName)"
	}

	long {
	    return "Tcl_SetLongObj ($obj, row->$fieldName)"
	}

	wide {
	    return "Tcl_SetWideIntObj ($obj, row->$fieldName)"
	}

	double {
	    return "Tcl_SetDoubleObj ($obj, row->$fieldName)"
	}

	float {
	    return "Tcl_SetDoubleObj ($obj, row->$fieldName)"
	}

	boolean {
	    return "Tcl_SetBooleanObj ($obj, row->$fieldName)"
	}

	varstring {
	    return "Tcl_SetStringObj ($obj, row->$fieldName, row->_${fieldName}Length)"
	}

	char {
	    return "Tcl_SetStringObj ($obj, &row->$fieldName, 1)"
	}

	fixedstring {
	    upvar ::ctable::fields::$fieldName field

	    return "Tcl_SetStringObj ($obj, row->$fieldName, $field(length))"
	}

	inet {
	    return "Tcl_SetStringObj ($obj, inet_ntoa (row->$fieldName), -1)"
	}

	mac {
	    return "Tcl_SetStringObj ($obj, ether_ntoa (&row->$fieldName), -1)"
	}

	tclobj {
	    error "can't set a string to a tclobj (field \"$fieldName\") -- you have to handle this outside of gen_get_set_obj"
	}

	default {
	    error "no code to gen obj for type $type"
	}
    }
}

#
# set_list_obj - generate C code to emit a Tcl obj containing the named
#  field into a list that's being cons'ed up
#
proc set_list_obj {position type fieldName} {
    emit "    listObjv\[$position] = [gen_new_obj $type $fieldName];"
}

#
# append_list_element - generate C code to append a list element to the
#  output object.  used by code that lets you get one or more named fields.
#
proc append_list_element {type fieldName} {
    return "Tcl_ListObjAppendElement (interp, Tcl_GetObjResult (interp), [gen_new_obj $type $fieldName])"
}

#
# gen_list - generate C code to emit an entire row into a Tcl list
#
proc gen_list {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set lengthDef [string toupper $table]_NFIELDS

    emit "Tcl_Obj *${table}_genlist (Tcl_Interp *interp, void *vPointer) $leftCurly"
    emit "    struct $table *row = vPointer;"

    emit "    Tcl_Obj *listObjv\[$lengthDef];"
    emit ""

    set position 0
    foreach fieldName $fieldList {
	if {[is_hidden $fieldName]} {
	    continue
	}

	upvar ::ctable::fields::$fieldName field

	set_list_obj $position $field(type) $fieldName

	incr position
    }

    emit "    return Tcl_NewListObj ($position, listObjv);"
    emit "$rightCurly"
    emit ""
}

#
# gen_keyvalue_list - generate C code to emit an entire row into a Tcl list in
#  "array set" format
#
proc gen_keyvalue_list {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set lengthDef [string toupper $table]_NFIELDS

    emit "Tcl_Obj *${table}_gen_keyvalue_list (Tcl_Interp *interp, void *vPointer) $leftCurly"
    emit "    struct $table *row = vPointer;"

    emit "    Tcl_Obj *listObjv\[$lengthDef * 2];"
    emit ""

    set position 0
    foreach fieldName $fieldList {
	if {[is_hidden $fieldName]} {
	    continue
	}

	upvar ::ctable::fields::$fieldName field

	emit "    listObjv\[$position] = [field_to_nameObj $table $fieldName];"
	incr position

	set_list_obj $position $field(type) $fieldName
	incr position

	emit ""
    }

    emit "    return Tcl_NewListObj ($position, listObjv);"
    emit "$rightCurly"
    emit ""
}

#
# gen_nonnull_keyvalue_list - generate C code to emit all of the nonnull
#   values in an entire row into a Tcl list in "array set" format
#
proc gen_nonnull_keyvalue_list {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set lengthDef [string toupper $table]_NFIELDS

    emit "Tcl_Obj *${table}_gen_nonnull_keyvalue_list (Tcl_Interp *interp, struct $table *row) $leftCurly"

    emit "    Tcl_Obj *listObjv\[$lengthDef * 2];"
    emit "    int position = 0;"
    emit "    Tcl_Obj *obj;"
    emit ""

    foreach fieldName $fieldList {
	if {[is_hidden $fieldName]} {
	    continue
	}

	upvar ::ctable::fields::$fieldName field

	if {[is_key $fieldName]} {
	    emit "    listObjv\[position++] = [field_to_nameObj $table $fieldName];"
	    emit "    listObjv\[position++] = [gen_new_obj $field(type) $fieldName];"
	} else {
	    emit "    obj = [gen_new_obj $field(type) $fieldName];"
	    emit "    if (obj != ${table}_NullValueObj) $leftCurly"
	    emit "        listObjv\[position++] = [field_to_nameObj $table $fieldName];"
	    emit "        listObjv\[position++] = obj;"
	    emit "    $rightCurly"
	}
    }

    emit "    return Tcl_NewListObj (position, listObjv);"
    emit "$rightCurly"
    emit ""
}

#
# gen_make_key_functions - Generate C code to return the key fields as a list
#
proc gen_make_key_functions {} {
    gen_make_key_from_keylist
}

proc gen_make_key_from_keylist {} {
    variable table
    variable fields
    variable keyFieldName
    variable fieldList
    variable leftCurly
    variable rightCurly

    emit "Tcl_Obj *${table}_key_from_keylist (Tcl_Interp *interp, Tcl_Obj **objv, int objc) $leftCurly"

    if {"$keyFieldName" != ""} {
	emit "    int      i;"
        emit ""

        emit "    for(i = 0; i < objc; i+=2)"
	emit "        if(strcmp(Tcl_GetString(objv\[i]), \"$keyFieldName\") == 0)"
	emit "            return objv\[i+1];"
        emit ""
    }
    emit "    return (Tcl_Obj *)NULL;"

    emit "$rightCurly"
    emit ""
}

#
# gen_field_names - generate C code containing an array of pointers to strings
#  comprising the names of all of the fields in a row of the table being
#  defined.  Also generate an enumerated type of all of the field names
#  mapped to uppercase and prepended with FIELD_ for use with
#  Tcl_GetIndexFromObj in figuring out what fields are wanted
#
proc gen_field_names {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly
    variable keyField
    variable withSharedTables

    emit "#define [string toupper $table]_NFIELDS [llength $fieldList]"
    emit ""

    emit "int      ${table}_keyField = $keyField;"

    emit "static CONST char *${table}_fields\[] = $leftCurly"
    foreach fieldName $fieldList {
	emit "    \"$fieldName\","
    }
    emit "    (char *) NULL"
    emit "$rightCurly;\n"

    set fieldenum "enum ${table}_fields $leftCurly"
    foreach myField $fieldList {
	append fieldenum "\n    [field_to_enum $myField],"
    }
    set fieldenum "[string range $fieldenum 0 end-1]\n$rightCurly;\n"
    emit $fieldenum

    set typeList "enum ctable_types ${table}_types\[\] = $leftCurly"
    foreach myField $fieldList {
	upvar ::ctable::fields::$myField field

	append typeList "\n    [ctable_type_to_enum $field(type)],"
    }
    emit "[string range $typeList 0 end-1]\n$rightCurly;\n"

    emit "// define per-field array for ${table} saying what fields need quoting"
    set needsQuoting "int ${table}_needs_quoting\[\] = $leftCurly"
    foreach myField $fieldList {
	upvar ::ctable::fields::$myField field

	if {[info exists field(needsQuoting)] && $field(needsQuoting)} {
	    set quoting 1
	} else {
	    set quoting 0
	}
	append needsQuoting "\n    $quoting,"
    }
    emit "[string range $needsQuoting 0 end-1]\n$rightCurly;\n"

    emit "// define per-field array for ${table} saying what fields are unique"
    set unique "int ${table}_unique\[\] = $leftCurly"
    foreach myField $fieldList {
	upvar ::ctable::fields::$myField field

	if {[info exists field(unique)] && $field(unique)} {
	    set uniqueVal 1
	} else {
	    set uniqueVal 0
	}
	append unique "\n    $uniqueVal,"
    }
    emit "[string range $unique 0 end-1]\n$rightCurly;\n"

    emit "// define objects that will be filled with the corresponding field names"
    foreach fieldName $fieldList {
        emit "Tcl_Obj *[field_to_nameObj $table $fieldName];"
    }
    emit ""

    emit "// define field property list keys and values to allow introspection"

    # do keys
    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	set propstring "char *[field_to_var $table $fieldName propkeys]\[] = $leftCurly"
    
	foreach fieldName [lsort [array names field]] {
	    append propstring "\"$fieldName\", "
	}
	emit "${propstring}(char *)NULL$rightCurly;"
    }
    emit ""

    set propstring "static char **${table}_propKeys\[] = $leftCurly"
    foreach fieldName $fieldList {
        append propstring "[field_to_var $table $fieldName propkeys],"
    }
    emit "[string range $propstring 0 end-1]$rightCurly;"
    emit ""
    # end of keys

    # do values, replica of keys, needs to be collapsed
    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	set propstring "char *[field_to_var $table $fieldName propvalues]\[] = $leftCurly"
    
	foreach fieldName [lsort [array names field]] {
	    append propstring "\"$field($fieldName)\", "
	}
	emit "${propstring}(char *)NULL$rightCurly;"
    }
    emit ""

    set propstring "static char **${table}_propValues\[] = $leftCurly"
    foreach fieldName $fieldList {
        append propstring "[field_to_var $table $fieldName propvalues],"
    }
    emit "[string range $propstring 0 end-1]$rightCurly;"
    emit ""
    # end of values

    emit "Tcl_Obj *${table}_NameObjList\[[string toupper $table]_NFIELDS + 1\];"
    emit ""

    emit "Tcl_Obj *${table}_DefaultEmptyStringObj;"
    emit ""

    emit "// define the null value object"
    emit "Tcl_Obj *${table}_NullValueObj;"
    emit ""

    emit "// define default objects for varstring fields, if any"
    foreach myField $fieldList {
	upvar ::ctable::fields::$myField field

	if {$field(type) == "varstring" && [info exists field(default)]} {
	    if {$field(default) != ""} {
		emit "Tcl_Obj *${table}_${myField}DefaultStringObj;"
	    }
	    lappend defaultStrings [cquote $field(default)]
	} else {
	    lappend defaultStrings ""
	}
    }
    emit ""

    set nullableList {}

    foreach myField $fieldList {
	upvar ::ctable::fields::$myField field

        set value 1
        if {[info exists field(notnull)] && $field(notnull)} {
	    set value 0
        }
#	if {[info exists field(default)]} {
#	    set value 1
#	}

	lappend nullableList $value
    }

    emit "// define fields that may be null"
    emit "int ${table}_nullable_fields\[] = { [join $nullableList ", "] };"
    emit ""

    if {$withSharedTables} {
        emit "// define default string list"
        emit "char *${table}_defaultStrings\[] = $leftCurly"
        emit "    \"[join $defaultStrings {", "}]\""
        emit "$rightCurly;"
        emit ""
    }
}

#
# gen_gets_cases - generate case statements for each field, each case fetches
#  field from row and returns a new Tcl_Obj set with that field's value
#
proc gen_gets_cases {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    foreach myField $fieldList {
	upvar ::ctable::fields::$myField field

	emit "      case [field_to_enum $myField]:"
	emit "        return [gen_new_obj $field(type) $myField];"
	emit ""
    }
}

#
# gen_gets_string_cases - generate case statements for each field, each case
#  generates a return of a char * to a string representing that field's
#  value and sets a passed-in int * to the length returned.
#
proc gen_gets_string_cases {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    foreach myField $fieldList {
	upvar ::ctable::fields::$myField field

	emit "      case [field_to_enum $myField]:"

	if {![info exists field(notnull)] || !$field(notnull)} {
	    emit "        if (row->_${myField}IsNull) $leftCurly"
	    emit "            return Tcl_GetStringFromObj (${table}_NullValueObj, lengthPtr);"
	    emit "        $rightCurly"
	}

	switch $field(type) {
	  "key" {
	    emit "        *lengthPtr = strlen(row->hashEntry.key);"
	    emit "        return row->hashEntry.key;"
	  }

	  "varstring" {
	    emit "        if (row->${myField} == NULL) $leftCurly"

	    if {![info exists field(default)] || $field(default) == ""} {
	        set source ${table}_DefaultEmptyStringObj
	    } else {
	        set source ${table}_${myField}DefaultStringObj
	    }
	    emit "            return Tcl_GetStringFromObj ($source, lengthPtr);"
	    emit "        $rightCurly"
	    emit "        *lengthPtr = row->_${myField}Length;"
	    emit "        return row->$myField;"
	  }

	  "fixedstring" {
	      emit "        *lengthPtr = $field(length);"
	      emit "        return row->$myField;"
	  }

	  "char" {
	      emit "        *lengthPtr = 1;"
	      emit "        return &row->$myField;"
	  }

	  "tclobj" {
	    emit "        if (row->$myField == NULL) $leftCurly"
	    emit "            return Tcl_GetStringFromObj (${table}_DefaultEmptyStringObj, lengthPtr);"
	    emit "        $rightCurly"
	    emit "        return Tcl_GetStringFromObj (row->$myField, lengthPtr);"
	  }

	  default {
	      emit "        [gen_get_set_obj utilityObj $field(type) $myField];"
	      emit "        return Tcl_GetStringFromObj (utilityObj, lengthPtr);"
	  }
	}
	emit ""
    }
}

# Static utility routines for command body that aren't ctable specific

variable sharedStaticSource {

// Call write-lock at least once during command.
static INLINE void begin_write(CTable *ctable)
{
  if(ctable->share_type == CTABLE_SHARED_MASTER) {
    write_lock(ctable->share);
    ctable->was_locked = 1;
  }
}

// Call write-unlock once at the end of the command, IFF it was locked
static INLINE void end_write(CTable *ctable)
{
  if(ctable->was_locked && ctable->share_type == CTABLE_SHARED_MASTER) {
    write_unlock(ctable->share);
    ctable->was_locked = 0;
  }
}

}

variable unsharedStaticSource {
// Dummy lock/unlock functions, since we're not doing shared ctables.
#  define begin_write(ct)
#  define end_write(ct)
}

#
# gen_preamble - generate stuff that goes at the head of the C file
#  we're generating
#
proc gen_preamble {} {
    variable fullInline
    variable fullStatic
    variable withPgtcl
    variable withSharedTables
    variable withSharedTclExtension
    variable sanityChecks
    variable sharedTraceFile
    variable sharedBase
    variable poolRatio
    variable preambleCannedSource
    variable sharedStaticSource
    variable unsharedStaticSource

    emit "/* autogenerated by ctable table generator [clock format [clock seconds]] */"
    emit "/* DO NOT EDIT */"
    emit ""
    if {$fullInline} {
	emit "#define INLINE inline"
    } else {
	emit "#define INLINE"
    }
    if {$fullStatic} {
	emit "#define CTABLE_INTERNAL static"
	emit "#define CTABLE_EXTERNAL"
	emit "#define FULLSTATIC"
    } else {
	emit "#define CTABLE_INTERNAL"
	emit "#define CTABLE_EXTERNAL extern"
    }
    emit ""
    if {$withPgtcl} {
        emit "#define WITH_PGTCL"
        emit ""
    }
    if {$sanityChecks} {
	emit "#define SANITY_CHECKS"
        emit ""
    }
    if {$withSharedTables} {
	emit "#define WITH_SHARED_TABLES"
	emit "#define WITH_TCL"
	if {$withSharedTclExtension} {
	    emit "#define SHARED_TCL_EXTENSION"
	}
	emit ""
        if {[info exists sharedTraceFile]} {
	    if {"$sharedTraceFile" != "-none"} {
	        emit "#define SHM_DEBUG_TRACE"
	        if {"$sharedTraceFile" != "-stderr"} {
		    emit "#define SHM_DEBUG_TRACE_FILE \"$sharedTraceFile\""
	        }
	    }
        }
	if {[info exists sharedBase] && "$sharedBase" != "NULL"} {
	    emit "#define SHARE_BASE ((char *)$sharedBase)"
	}
	emit "#define POOL_RATIO $poolRatio"
    }
    emit $preambleCannedSource
    if {$withSharedTables} {
	if {[info exists sharedBase] && "$sharedBase" != "NULL"} {
	    emit "char *set_share_base = NULL;"
	}

        emit $sharedStaticSource
    } else {
        emit $unsharedStaticSource
    }
}

#####
#
# Field Compare Function Generation
#
#####

#
# fieldCompareNullCheckSource - this checks for nulls when comparing a field
#
variable fieldCompareNullCheckSource {
    // nulls sort high
    if (row1->_${fieldName}IsNull) {
	if (row2->_${fieldName}IsNull) {
	    return 0;
	}
	return 1;
    } else if (row2->_${fieldName}IsNull) {
	return -1;
    }
}

#
# gen_field_compare_null_check_source - return code to be emitted into a field
#  compare, nothing if the field is not null else code to check for null
#
proc gen_field_compare_null_check_source {table fieldName} {
    variable fieldCompareNullCheckSource
    variable varstringCompareDefaultSource
    variable varstringCompareNullSource
    upvar ::ctable::fields::$fieldName field

    if {"$field(type)" == "varstring"} {
	if {![info exists field(default)] || "$field(default)" == ""} {
	     set source $varstringCompareNullSource
	} else {
	     set source $varstringCompareDefaultSource
	     set defaultString "\"[cquote $field(default)]\""
	     set defaultChar "'[cquote [string index $field(default) 0] {'}]'"
	}
    } elseif {[info exists field(notnull)] && $field(notnull)} {
        set source ""
    } else {
	set source $fieldCompareNullCheckSource
    }

    return [string range [subst -nobackslashes -nocommands $source] 1 end-1]
}

#
# fieldCompareHeaderSource - code for defining a field compare function
#
variable fieldCompareHeaderSource {
// field compare function for field '$fieldName' of the '$table' table...
int ${table}_field_${fieldName}_compare(const ctable_BaseRow *vPointer1, const ctable_BaseRow *vPointer2) $leftCurly
    struct ${table} *row1, *row2;

    row1 = (struct $table *) vPointer1;
    row2 = (struct $table *) vPointer2;
[gen_field_compare_null_check_source $table $fieldName]
}

variable fieldCompareTrailerSource {
$rightCurly
}

#
# keyCompareSource - code for defining a key compare function
#
variable keyCompareSource {
// field compare function for key of the '$table' table...
int ${table}_key_compare(const ctable_BaseRow *vPointer1, const ctable_BaseRow *vPointer2) $leftCurly
    struct ${table} *row1, *row2;

    row1 = (struct $table *) vPointer1;
    row2 = (struct $table *) vPointer2;
    if (*row1->hashEntry.key != *row2->hashEntry.key) {
        if (*row1->hashEntry.key < *row2->hashEntry.key) {
	    return -1;
	} else {
	    return 1;
	}
    }
    return strcmp(row1->hashEntry.key, row2->hashEntry.key);
$rightCurly
}

#
# boolFieldCompSource - code we run subst over to generate a compare of a 
# boolean (bit) for use in a field comparison routine.
#
variable boolFieldCompSource {
    if (row1->$fieldName && !row2->$fieldName) {
	return -1;
    }

    if (!row1->$fieldName && row2->$fieldName) {
	return 1;
    }

    return 0;
}

#
# numberFieldSource - code we run subst over to generate a compare of a standard
#  number such as an integer, long, double, and wide integer for use in field
#  compares.
#
variable numberFieldCompSource {
    if (row1->$fieldName < row2->$fieldName) {
        return -1;
    }

    if (row1->$fieldName > row2->$fieldName) {
	return 1;
    }

    return 0;
}

#
# varstringFieldCompSource - code we run subst over to generate a compare of 
# a string for use in searching, sorting, etc.
#
variable varstringFieldCompSource {
    if (row1->$fieldName == NULL) {
        if (row2->$fieldName == NULL) {
	    return 0;
	}
	return strcmp (${table}_defaultStrings[$fieldToEnum], row2->$fieldName);
    } else if (row2->$fieldName == NULL) {
        return strcmp (row1->$fieldName, ${table}_defaultStrings[$fieldToEnum]);
    }

    if (*row1->$fieldName != *row2->$fieldName) {
        if (*row1->$fieldName < *row2->$fieldName) {
	    return -1;
	} else {
	    return 1;
	}
    }
    return strcmp (row1->$fieldName, row2->$fieldName);
}

#
# varstringCompareDefaultSource - compare against default strings
#
# note there's also a varstringSortCompareDefaultSource that's pretty close to 
# this but sets a result variable and does a break to get out of a case
# statement rather than returning something
#
variable varstringCompareDefaultSource {
    if (!row1->$fieldName) {
	if(!row2->$fieldName) {
	    return 0;
	} else {
	    if ($defaultChar != row2->${fieldName}[0]) {
		return ($defaultChar < row2->${fieldName}[0]) ? -1 : 1;
	    }
	    return strcmp($defaultString, row2->$fieldName);
	}
    } else {
	if(!row2->$fieldName) {
	    if (row1->${fieldName}[0] != $defaultChar) {
		return (row1->${fieldName}[0] < $defaultChar) ? -1 : 1;
	    }
	    return strcmp(row1->$fieldName, $defaultString);
	}
    }
}

#
# varstringCompareNullSource - compare against default empty string
#
# note there's also a varstringSortCompareNullSource that's pretty close to 
# this but sets a result variable and does a break to get out of a case
# statement rather than returning something
#
variable varstringCompareNullSource {
    if (!row1->$fieldName) {
	if(!row2->$fieldName) {
	    return 0;
	} else {
	    return -1;
	}
    } else {
	if(!row2->$fieldName) {
	    return 1;
	}
    }
}


#
# fixedstringFieldCompSource - code we run subst over to generate a comapre of a 
# fixed-length string for use in a searching, sorting, etc.
#
variable fixedstringFieldCompSource {
    if (*row1->$fieldName != *row2->$fieldName) {
        if (*row1->$fieldName < *row2->$fieldName) {
	    return -1;
	} else {
	    return 1;
	}
    }
    return strncmp (row1->$fieldName, row2->$fieldName, $length);
}

#
# binaryDataFieldCompSource - code we run subst over to generate a comapre of a 
# inline binary arrays (inets and mac addrs) for use in searching and sorting.
#
variable binaryDataFieldCompSource {
    return memcmp (&row1->$fieldName, &row2->$fieldName, $length);
}

#
# tclobjFieldCompSource - code we run subst over to generate a compare of 
# a tclobj for use in searching and sorting.
#
variable tclobjFieldCompSource {
    return strcmp (Tcl_GetString (row1->$fieldName), Tcl_GetString (row2->$fieldName));
}

#
# gen_field_comp - emit code to compare a field for a field comparison routine
#
proc gen_field_comp {fieldName} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    variable numberFieldCompSource
    variable fixedstringFieldCompSource
    variable binaryDataFieldCompSource
    variable varstringFieldCompSource
    variable boolFieldCompSource
    variable keyCompSource
    variable tclobjFieldCompSource

    upvar ::ctable::fields::$fieldName field

    switch $field(type) {
	key {
	    emit [string range [subst -nobackslashes -nocommands $keyCompSource] 1 end-1]
	}

	int {
	    emit [string range [subst -nobackslashes -nocommands $numberFieldCompSource] 1 end-1]
	}

	long {
	    emit [string range [subst -nobackslashes -nocommands $numberFieldCompSource] 1 end-1]
	}

	wide {
	    emit [string range [subst -nobackslashes -nocommands $numberFieldCompSource] 1 end-1]
	}

	double {
	    emit [string range [subst -nobackslashes -nocommands $numberFieldCompSource] 1 end-1]
	}

	short {
	    emit [string range [subst -nobackslashes -nocommands $numberFieldCompSource] 1 end-1]
	}

	float {
	    emit [string range [subst -nobackslashes -nocommands $numberFieldCompSource] 1 end-1]
	}

	char {
	    emit [string range [subst -nobackslashes -nocommands $numberFieldCompSource] 1 end-1]
	}

	fixedstring {
	    set length $field(length)
	    emit [string range [subst -nobackslashes -nocommands $fixedstringFieldCompSource] 1 end-1]
	}

	varstring {
	    set fieldToEnum [field_to_enum $fieldName]
	    emit [string range [subst -nobackslashes -nocommands $varstringFieldCompSource] 1 end-1]
	}

	boolean {
	    emit [string range [subst -nobackslashes -nocommands $boolFieldCompSource] 1 end-1]
	}

	inet {
	    set length "sizeof(struct in_addr)"
	    emit [string range [subst -nobackslashes -nocommands $binaryDataFieldCompSource] 1 end-1]
	}

	mac {
	    set length "sizeof(struct ether_addr)"
	    emit [string range [subst -nobackslashes -nocommands $binaryDataFieldCompSource] 1 end-1]
	}

	tclobj {
	    emit [string range [subst -nobackslashes -nocommands $tclobjFieldCompSource] 1 end-1]
	}

	default {
	    error "attempt to emit sort compare source for field of unknown type $field(type)"
	}
    }
}
#
# gen_field_compare_functions - generate functions for each field that will
# compare that field from two row pointers and return -1, 0, or 1.
#
proc gen_field_compare_functions {} {
    variable table
    variable leftCurly
    variable rightCurly
    variable fieldCompareHeaderSource
    variable fieldCompareTrailerSource
    variable keyCompareSource
    variable fieldList

    # generate all of the field compare functions
    foreach fieldName $fieldList {
	if [is_key $fieldName] {
	    emit [subst -nobackslashes $keyCompareSource]
	    continue
	}
	emit [string range [subst -nobackslashes $fieldCompareHeaderSource] 1 end-1]
	gen_field_comp $fieldName
	emit [string range [subst -nobackslashes -nocommands $fieldCompareTrailerSource] 1 end-1]
    }

    # generate an array of pointers to field compare functions for this type
    emit "// array of table's field compare routines indexed by field number"
    emit "fieldCompareFunction_t ${table}_compare_functions\[] = $leftCurly"
    set typeList ""
    foreach fieldName $fieldList {
	if [is_key $fieldName] {
	    append typeList "\n    ${table}_key_compare,"
	} else {
	    append typeList "\n    ${table}_field_${fieldName}_compare,"
	}
    }
    emit "[string range $typeList 0 end-1]\n$rightCurly;\n"
}

#####
#
# Sort Comparison Function Generation
#
#####

variable sortCompareHeaderSource {

int ${table}_sort_compare(void *clientData, const void *vRow1, const void *vRow2) $leftCurly
    CTableSort *sortControl = (CTableSort *)clientData;
    const struct $table *row1 = (*(void **)vRow1);
    const struct $table *row2 = (*(void **)vRow2);
    int              i;
    int              direction;
    int              result = 0;

// printf ("sort comp he1 %lx, he2 %lx, p1 %lx, p2 %lx\n", (long unsigned int)hashEntryPtr1, (long unsigned int)hashEntryPtr2, (long unsigned int)row1, (long unsigned int)row2);

    for (i = 0; i < sortControl->nFields; i++) $leftCurly
        direction = sortControl->directions[i];
        switch (sortControl->fields[i]) $leftCurly 
}

variable sortCompareTrailerSource {
        $rightCurly // end of switch

	// if they're not equal, we're done.  if they are, we may need to
	// compare a subordinate sort field (if there is one)
	if (result != 0) {
	    break;
	}
    $rightCurly // end of for loop on sort fields
    return result;
$rightCurly
}

#
# gen_sort_compare_function - generate a function that will compare fields
# in two ctable structures for use by qsort
#
proc gen_sort_compare_function {} {
    variable table
    variable leftCurly
    variable rightCurly
    variable sortCompareHeaderSource
    variable sortCompareTrailerSource

    emit [string range [subst -nobackslashes -nocommands $sortCompareHeaderSource] 1 end-1]

    gen_sort_comp

    emit [string range [subst -nobackslashes -nocommands $sortCompareTrailerSource] 1 end-1]
}

#
# gen_sort_comp - emit code to compare fields for sorting
#
proc gen_sort_comp {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    variable numberSortSource
    variable fixedstringSortSource
    variable binaryDataSortSource
    variable varstringSortSource
    variable boolSortSource
    variable keySortSource
    variable tclobjSortSource

    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	set fieldEnum [field_to_enum $fieldName]

	switch $field(type) {
	    key {
		emit [string range [subst -nobackslashes $keySortSource] 1 end-1]
	    }

	    int {
		emit [string range [subst -nobackslashes $numberSortSource] 1 end-1]
	    }

	    long {
		emit [string range [subst -nobackslashes $numberSortSource] 1 end-1]
	    }

	    wide {
		emit [string range [subst -nobackslashes $numberSortSource] 1 end-1]
	    }

	    double {
		emit [string range [subst -nobackslashes $numberSortSource] 1 end-1]
	    }

	    short {
		emit [string range [subst -nobackslashes $numberSortSource] 1 end-1]
	    }

	    float {
		emit [string range [subst -nobackslashes $numberSortSource] 1 end-1]
	    }

	    char {
		emit [string range [subst -nobackslashes $numberSortSource] 1 end-1]
	    }

	    fixedstring {
	        set length $field(length)
		emit [string range [subst -nobackslashes $fixedstringSortSource] 1 end-1]
	    }

	    varstring {
		emit [string range [subst $varstringSortSource] 1 end-1]
	    }

	    boolean {
		emit [string range [subst -nobackslashes $boolSortSource] 1 end-1]
	    }

	    inet {
	        set length "sizeof(struct in_addr)"
		emit [string range [subst -nobackslashes $binaryDataSortSource] 1 end-1]
	    }

	    mac {
		set length "sizeof(struct ether_addr)"
		emit [string range [subst -nobackslashes $binaryDataSortSource] 1 end-1]
	    }

	    tclobj {
		emit [string range [subst -nobackslashes $tclobjSortSource] 1 end-1]
	    }

	    default {
	        error "attempt to emit sort compare source for field $fieldName of unknown type $field(type)"
	    }
	}
    }
}

#####
#
# Search Comparison Function Generation
#
#####

variable searchCompareHeaderSource {

// compare a row to a block of search components and see if it matches
int ${table}_search_compare(Tcl_Interp *interp, CTableSearch *searchControl, void *vPointer) $leftCurly
    struct $table *row = (struct $table *)vPointer;
    struct $table *row1;

    int                                 i;
    int                                 exclude = 0;
    int                                 compType;
    CTableSearchComponent              *component;
    int					inIndex;


#ifdef SANITY_CHECKS
    ${table}_sanity_check_pointer(searchControl->ctable, vPointer, CTABLE_INDEX_NORMAL, "${table}_search_compare");
#endif

    for (i = 0; i < searchControl->nComponents; i++) $leftCurly
      if (i == searchControl->alreadySearched)
	continue;

      component = &searchControl->components[i];

      row1 = (struct $table *)component->row1;
      compType = component->comparisonType;

      // Take care of the common code first
      switch (compType) {
	case CTABLE_COMP_IN:
	  if(component->inListRows == NULL && ctable_CreateInRows(interp, searchControl->ctable, component) == TCL_ERROR) {
              return TCL_ERROR;
	  }

	  for(inIndex = 0; inIndex < component->inCount; inIndex++) {
	      if (component->compareFunction ((ctable_BaseRow *)row, (ctable_BaseRow *)component->inListRows[inIndex]) == 0) {
		  break;
	      }
	  }

	  if(inIndex >= component->inCount) {
	      return TCL_CONTINUE;
	  }
	  continue;

	case CTABLE_COMP_LT:
	  if (component->compareFunction ((ctable_BaseRow *)row, (ctable_BaseRow *)row1) < 0) {
	      continue;
	  }
	  return TCL_CONTINUE;

	case CTABLE_COMP_LE:
	  if (component->compareFunction ((ctable_BaseRow *)row, (ctable_BaseRow *)row1) <= 0) {
	      continue;
	  }
	  return TCL_CONTINUE;

	case CTABLE_COMP_EQ:
	  if (component->compareFunction ((ctable_BaseRow *)row, (ctable_BaseRow *)row1) == 0) {
	      continue;
	  }
	  return TCL_CONTINUE;

	case CTABLE_COMP_NE:
	  if (component->compareFunction ((ctable_BaseRow *)row, (ctable_BaseRow *)row1) != 0) {
	      continue;
	  }
	  return TCL_CONTINUE;

	case CTABLE_COMP_GE:
	  if (component->compareFunction ((ctable_BaseRow *)row, (ctable_BaseRow *)row1) >= 0) {
	      continue;
	  }
	  return TCL_CONTINUE;

	case CTABLE_COMP_GT:
	  if (component->compareFunction ((ctable_BaseRow *)row, (ctable_BaseRow *)row1) > 0) {
	      continue;
	  }
	  return TCL_CONTINUE;

        case CTABLE_COMP_RANGE: {
	  struct $table *row2;

	  if (component->compareFunction ((ctable_BaseRow *)row, (ctable_BaseRow *)row1) < 0) {
	      return TCL_CONTINUE;
	  }

	  row2 = (struct $table *)component->row2;

	  if (component->compareFunction ((ctable_BaseRow *)row, (ctable_BaseRow *)row2) >= 0) {
	      return TCL_CONTINUE;
	  }
	  continue;
	}
      }

      switch (component->fieldID) $leftCurly
}

variable searchCompareTrailerSource {
       $rightCurly // end of switch on field ID

        // if exclude got set, we're done.
	if (exclude) {
	    return TCL_CONTINUE;
	}
    $rightCurly // end of for loop on search fields
    return TCL_OK;
$rightCurly
}

#
# gen_search_compare_function - generate a function that see if a row in
# a ctable matches the search criteria
#
proc gen_search_compare_function {} {
    variable table
    variable leftCurly
    variable rightCurly
    variable searchCompareHeaderSource
    variable searchCompareTrailerSource

    emit [string range [subst -nobackslashes -nocommands $searchCompareHeaderSource] 1 end-1]

    gen_search_comp

    emit [string range [subst -nobackslashes -nocommands $searchCompareTrailerSource] 1 end-1]
}

#
# gen_search_comp - emit code to compare fields for searching
#
proc gen_search_comp {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    variable numberCompSource
    variable fixedstringCompSource
    variable binaryDataCompSource
    variable varstringCompSource
    variable boolCompSource
    variable keyCompSource
    variable tclobjCompSource

    variable standardCompSwitchSource
    variable standardCompNullCheckSource

    set value sandbag

    foreach fieldName $fieldList {
	upvar ::ctable::fields::$fieldName field

	set fieldEnum [field_to_enum $fieldName]
	set type $field(type)
        set typeText $field(type)

	switch $type {
	    int {
		set getObjCmd Tcl_GetIntFromObj
		emit [string range [subst -nobackslashes $numberCompSource] 1 end-1]
	    }

	    long {
		set getObjCmd Tcl_GetLongFromObj
		emit [string range [subst -nobackslashes $numberCompSource] 1 end-1]
	    }

	    wide {
		set getObjCmd Tcl_GetWideIntFromObj
		set typeText "Tcl_WideInt"
		set type "Tcl_WideInt"
		emit [string range [subst -nobackslashes $numberCompSource] 1 end-1]
	    }

	    double {
		set getObjCmd Tcl_GetDoubleFromObj
		emit [string range [subst -nobackslashes $numberCompSource] 1 end-1]
	    }

	    short {
		set typeText "int"
		set getObjCmd Tcl_GetIntFromObj
		emit [string range [subst -nobackslashes $numberCompSource] 1 end-1]
	    }

	    float {
		set typeText "double"
		set getObjCmd Tcl_GetDoubleFromObj
		emit [string range [subst -nobackslashes $numberCompSource] 1 end-1]
	    }

	    char {
		set typeText "int"
		set getObjCmd Tcl_GetIntFromObj
		emit [string range [subst -nobackslashes $numberCompSource] 1 end-1]
	    }

	    fixedstring {
		set getObjCmd Tcl_GetString
	        set length $field(length)
		emit [string range [subst -nobackslashes $fixedstringCompSource] 1 end-1]
	    }

	    varstring {
		set getObjCmd Tcl_GetString
		emit [string range [subst -nobackslashes $varstringCompSource] 1 end-1]
	    }

	    boolean {
		set getObjCmd Tcl_GetBooleanFromObj
		emit [string range [subst -nobackslashes $boolCompSource] 1 end-1]
	    }

	    inet {
		set getObjCmd Tcl_GetStringFromObj
	        set length "sizeof(struct in_addr)"
		emit [string range [subst -nobackslashes $binaryDataCompSource] 1 end-1]
	    }

	    mac {
		set getObjCmd Tcl_GetStringFromObj
		set length "sizeof(struct ether_addr)"
		emit [string range [subst -nobackslashes $binaryDataCompSource] 1 end-1]
	    }

	    tclobj {
		set getObjCmd Tcl_GetStringFromObj
		emit [string range [subst -nobackslashes $tclobjCompSource] 1 end-1]
	    }

	    key {
		set getObjCmd Tcl_GetString
	        set length "strlen(row->hashEntry.key)"
		emit [string range [subst -nobackslashes $keyCompSource] 1 end-1]
	    }

	    default {
	        error "attempt to emit search compare source for field of unknown type $field(type)"
	    }
	}
    }
}

#####
#
# Invoking the Compiler
#
#####

proc myexec {command} {
    variable showCompilerCommands

    if {$showCompilerCommands} {
puts [info level 0]
	puts $command; flush stdout
    }

    eval exec $command
}

#
# Generate the fully qualified path to a file
#
proc target_name {name version {ext .c}} {
    return [file join [target_path $name] $name-$version$ext]
}

#
# Generate the path to the target files
#
# Either buildPath or buildPath/$name
#
# And make sure it exists!
#
proc target_path {name} {
    variable buildPath
    variable withSubdir
    variable dirStatus

    set path $buildPath

    if {$withSubdir} {
        set path [file join $path $name]
    }

    if {![info exists dirStatus($path)]} {
	set dirStatus($path) [file isdirectory $path]
	if {!$dirStatus($path)} {
	    file mkdir $path
	}
    }

    return $path
}

#
# compile - compile and link the shared library
#
proc compile {fileFragName version} {
    global tcl_platform
    variable buildPath
    variable sysFlags
    variable withPgtcl
    variable genCompilerDebug
    variable memDebug
    variable withPipe
    variable withSubdir

    variable sysconfig

    set include [target_path include]
    set targetPath [target_path $fileFragName]
    set sourceFile [target_name $fileFragName $version]
    set objFile [target_name $fileFragName $version .o]

    if {$withPipe} {
	set pipeFlag "-pipe"
    } else {
	set pipeFlag ""
    }

    set stubs [info exists sysconfig(stub)]

    if {$genCompilerDebug} {
	set optflag "-O0"
	set dbgflag $sysconfig(dbg)

	if {$memDebug} {
	    set memSuffix m
	} else {
	    set memSuffix ""
	}

	if {$stubs} {
		set stub "$sysconfig(stubg)$memSuffix"
	}
	set lib "$sysconfig(libg)$memSuffix"

    } else {
	set optflag $sysconfig(opt)
	set dbgflag ""

	if {$stubs} {
	    set stub " $sysconfig(stub)"
	}
	set lib $sysconfig(lib)
    }

    if {$stubs} {
	set stubString "-DUSE_TCL_STUBS=$stubs"
    } else {
	set stubString ""
    }

    # put -DTCL_MEM_DEBUG in there if you're building with
    # memory debugging (see Tcl docs)
    if {$memDebug} {
	set memDebugString "-DTCL_MEM_DEBUG=1"
    } else {
	set memDebugString ""
    }

    if {[info exists sysFlags($tcl_platform(os))]} {
	set sysString $sysFlags($tcl_platform(os))
    } else {
	set sysString ""
    }

    if {$withPgtcl} {
	set pgString -I$sysconfig(pgtclprefix)/include
	if [info exists sysconfig(pqprefix)] {
	    if {"$sysconfig(pqprefix)" != "$sysconfig(pgtclprefix)"} {
	        append pgString " -I$sysconfig(pqprefix)/include"
	    }
	}
    } else {
	set pgString ""
    }

    myexec "$sysconfig(cc) $sysString $optflag $dbgflag $sysconfig(ldflags) $sysconfig(ccflags) -I$include $sysconfig(warn) $pgString $stubString $memDebugString -c $sourceFile -o $objFile"

    set ld_cmd "$sysconfig(ld) $dbgflag -o $targetPath/lib${fileFragName}$sysconfig(shlib) $objFile"

    if {$withPgtcl} {
	set pgtcl_lib $sysconfig(pgtclprefix)/lib
	set pgtcl_ver $sysconfig(pgtclver)

        lappend pgpath $pgtcl_lib/pgtcl$pgtcl_ver

	if [info exists sysconfig(pqprefix)] {
	    if {"$sysconfig(pqprefix)" != "$sysconfig(pgtclprefix)"} {
		lappend pgpath $sysconfig(pqprefix)/lib
	    }
	}

	foreach dir $pgpath {
	    append ld_cmd " -R$dir"
	}
	foreach dir $pgpath {
	    append ld_cmd " -L$dir"
	}

	append ld_cmd " -lpgtcl$pgtcl_ver -L/usr/local/lib -lpq"
    }

    append ld_cmd " $sysconfig(ldflags) $stub"
    myexec $ld_cmd

    if {$withSubdir} {
	set pkg_args [list $buildPath */*.tcl */*[info sharedlibextension]]
    } else {
	set pkg_args [list $buildPath]
    }

    variable showCompilerCommands
    if {$showCompilerCommands} {
	puts [concat + pkg_mkIndex -verbose $pkg_args]
	eval pkg_mkIndex -verbose $pkg_args
    } else {
	eval pkg_mkIndex $pkg_args
    }
}

proc EndExtension {} {
    variable tables
    variable extension
    variable withSharedTables
    variable extensionVersion
    variable rightCurly
    variable ofp
    variable memDebug

    put_init_extension_source [string totitle $extension] $extensionVersion

    if {$withSharedTables} {
	emit "    Shared_Init(interp);"
    }

    foreach name $tables {
	put_init_command_source $name
    }

    emit "    return TCL_OK;"
    emit $rightCurly

    close $ofp
    unset ofp

    compile $extension $::ctable::extensionVersion
}

#
# extension_already_built - see if the extension already exists unchanged
#  from what's being asked for
#
proc extension_already_built {name version code} {
    # if open of the stash file fails, it ain't built
    if {[catch {open [target_name $name $version .ct]} fp] == 1} {
        #puts ".ct file not there, build required"
        return 0
    }

    # read the first line for the prior CVS ID, if failed, report not built
    if {[gets $fp controlLine] < 0} {
        #puts "first line read of .ct file failed, build required"
        close $fp
	return 0
    }

    # See if this file's control line matches the line in the .ct file.
    # If not, rebuild not built.
    if {$controlLine != [control_line]} {
        #puts "control line does not match, build required"
	return 0
    }

    set priorCode [read -nonewline $fp]
    close $fp

    # if the prior code and current code aren't identical, report not built
    if {$priorCode != $code} {
        #puts "extension code changed, build required"
	return 0
    }

    #puts "prior code and generator cvs match, build not required"
    return 1
}

# This is a unique ID that should change whenever anything significant
# changes in ctables
proc control_line {} {
    variable srcDir
    variable cvsID
    variable keyCompileVariables

    foreach v $keyCompileVariables {
	variable $v
	if [info exists $v] {
	    lappend compileSettings "$v=[set $v]"
	} else {
	    lappend compileSettings "$v?"
	}
    }
    set compileSettings [join $compileSettings ":"]

    return "$cvsID $compileSettings [file mtime $srcDir] [info patchlevel]"
}

#
# save_extension_code - after a successful build, cache the extension
#  definition so extension_already_built can see if it's necessary to
#  generate, compile and link the shared library next time we're run
#
proc save_extension_code {name version code} {
    set fp [open [target_name $name $version .ct] w]

    puts $fp [control_line]
    puts $fp $code

    close $fp
}

#
# install_ch_files - install .h in the target dir if something like it
#  isn't there already
#
proc install_ch_files {includeDir} {
    variable srcDir
    variable withSharedTables

    lappend subdirs skiplists hash

    set copyFiles {
	ctable.h ctable_search.c ctable_lists.c ctable_batch.c
	boyer_moore.c jsw_rand.c jsw_rand.h jsw_slib.c jsw_slib.h
	speedtables.h speedtableHash.c ctable_io.c ctable_qsort.c
    }

    if {$withSharedTables} {
	lappend copyFiles shared.c shared.h
	lappend subdirs shared
    }

    emit "// Importing .c and .h files to '$includeDir'\n//"
    foreach file $copyFiles {
	set fullName [file join $srcDir $file]

	if {![file exists $fullName]} {
	    unset fullName

	    foreach dir $subdirs {
		set fullName [file join $srcDir $dir $file]

		if {![file exists $fullName]} {
		    unset fullName
		} else {
		    break
		}
	    }
	}

	if [info exists fullName] {
            file copy -force $fullName $includeDir
	    emit "// Imported '$fullName'"
	} else {
	    return -code error "Can't find $file in $srcDir"
	}
    }
    emit "// Import complete\n"
}

#
# get_error_info - to keep tracebacks from containing lots of internals
#  of ctable stuff, we scarf errorInfo into ctableErrorInfo if we get
#  an error interpreting a CExtension/CTable definition.  This allows
#  one to get the error info if debugging is required, etc.
#
proc get_error_info {} {
    variable ctableErrorInfo

    return $ctableErrorInfo
}

}

#
# CExtension - define a C extension
#
proc CExtension {name version code} {
    uplevel 1 [list _speedtables $name $version $code]
}

#
# speedtables - define a Speedtable package
#
proc speedtables {name version code} {
    if {![string is upper [string index $name 0]]} {
	error "Speed Tables package name must start with an uppercase letter"
    }
    foreach char [split $name ""] {
	if [string is digit $char] {
	    error "Speed Tables package name can not include any digits"
	}
    }
    uplevel 1 [list _speedtables $name $version $code]
}

#
# _speedtables - Common code to define a package
#
proc _speedtables {name version code} {
    global tcl_platform errorInfo errorCode

    # clear the error info placeholder
    set ctableErrorInfo ""

    if {![info exists ::ctable::buildPath]} {
        CTableBuildPath stobj
    }

    set path [file normalize $::ctable::buildPath]
    file mkdir $path

    if {[::ctable::extension_already_built $name $version $code]} {
        #puts stdout "extension $name $version unchanged"
	return
    }

    set ::ctable::sourceCode $code
    set ::ctable::sourceFile [::ctable::target_name $name $version]
    set ::ctable::extension $name
    set ::ctable::extensionVersion $version
    set ::ctable::tables ""

    if {[catch {namespace eval ::ctable $code} result] == 1} {
        set ::ctable::ctableErrorInfo $errorInfo

	if $::ctable::errorDebug {
	    return -code error -errorcode $errorCode -errorinfo $errorInfo
	} else {
            return -code error -errorcode $errorCode "$result\n(run ::ctable::get_error_info to see ctable's internal errorInfo)"
	}
    }

    ::ctable::EndExtension

    ::ctable::save_extension_code $name $version $code
}

##
## start_ctable_codegen - can't be run until the ctable is loaded
##
proc start_codegen {} {
    if [info exists ::ctable::ofp] {
	return
    }

    set ::ctable::ofp [open $::ctable::sourceFile w]

    ::ctable::gen_preamble

    ::ctable::gen_ctable_type_stuff

    # This runs here so we have the log of where we got files from in
    # the right place
    ::ctable::install_ch_files [::ctable::target_path include]

    ::ctable::emit "#include \"ctable_io.c\""

    ::ctable::emit "#include \"ctable_search.c\""

    ::ctable::emit "static char *sourceCode = \"[::ctable::cquote "CExtension $::ctable::extension $::ctable::extensionVersion { $::ctable::sourceCode }"]\";"
    ::ctable::emit ""

    ::ctable::emit "static char *ctablePackageVersion = \"$::ctable::ctablePackageVersion\";"
}

#
# CTable - define a C meta table
#
proc CTable {name data} {
    uplevel 1 [list table $name $data]
}

#
# table - define a Speed Tables table
#
proc table {name data} {
    ::ctable::new_table $name
    lappend ::ctable::tables $name

    namespace eval ::ctable $data

    ::ctable::sanity_check

    start_codegen

    # Create a key field if there isn't already one
    ::ctable::key _key

    if {$::ctable::withDirty} {
        # Create a 'dirty' field
        ::ctable::boolean _dirty notnull 1 default 0
    }

    ::ctable::gen_struct

    ::ctable::gen_field_names

    ::ctable::gen_setup_routine $name

    ::ctable::gen_defaults_subr $name

    ::ctable::gen_delete_subr ${name}_delete $name

    ::ctable::gen_obj_is_null_subr

    ::ctable::gen_list

    ::ctable::gen_keyvalue_list

    ::ctable::gen_nonnull_keyvalue_list

    ::ctable::gen_code

    ::ctable::put_metatable_source $name

}

#
# CTableBuildPath - set the path for where we're building CTable stuff
#
proc CTableBuildPath {dir} {
    global auto_path

    set ::ctable::buildPath $dir

    if {[lsearch -exact $auto_path $dir] < 0} {
        lappend auto_path $dir
    }
}

package provide ctable $::ctable::ctablePackageVersion
package provide speedtable $::ctable::ctablePackageVersion

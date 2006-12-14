//
// ctable linked list routines
//
//
// $Id$
//


//
// ctable_ListInit - initialize a list
//
inline void
ctable_ListInit (struct ctable_baseRow **listPtr)
{
    *listPtr = NULL;
}

//
// ctable_ListEmpty - return 1 if the list is empty, else 0.
//
inline int
ctable_ListEmpty (struct ctable_baseRow *list)
{
    return (list == NULL);
}

//
// ctable_ListRemove - remove a row from a list
//
inline void
ctable_ListRemove (struct ctable_baseRow *row, int i)
{
    // if there's an object following me, make his prev be my prev
    if (row->_ll_nodes[i].next != NULL) {
        row->_ll_nodes[i].next->_ll_nodes[i].prev = row->_ll_nodes[i].prev;
    }

    // make my prev's next (or header) point to my next
    *row->_ll_nodes[i].prev = row->_ll_nodes[i].next;

    // i'm removed
}

//
// ctable_ListRemoveMightBeTheLastOne - remove a row from a list
//
inline int
ctable_ListRemoveMightBeTheLastOne (struct ctable_baseRow *row, int i)
{
    int mightBeTheLastOne;

    // if there's an object following me, make his prev be my prev
    if (row->_ll_nodes[i].next == NULL) {
        mightBeTheLastOne = 1;
    } else {
        row->_ll_nodes[i].next->_ll_nodes[i].prev = row->_ll_nodes[i].prev;
	mightBeTheLastOne = 0;
    }

    // make my prev's next (or header) point to my next
    *row->_ll_nodes[i].prev = row->_ll_nodes[i].next;

    // i'm removed
    return mightBeTheLastOne;
}


inline void
ctable_ListInsertHead (struct ctable_baseRow **listPtr, struct ctable_baseRow *row, int i)
{
    // make the new row's next point to what the head currently points
    // to, possibly NULL

    if ((row->_ll_nodes[i].next = *listPtr) != NULL) {

        // it wasn't null, make the node pointed to by head's prev
	// point to the new row

        (*listPtr)->_ll_nodes[i].prev = &row->_ll_nodes[i].next;
    }

    // in any case, make the head point to the new row,
    // and make the row's prev point to the address of the head pointer

    *listPtr = row;
    row->_ll_nodes[i].prev = listPtr;

    row->_ll_nodes[i].head = listPtr;

// printf ("insert head %lx i %d\n", (long unsigned int)listPtr, i);
}

//
// ctable_ListInsertBefore - insert row2 before row1
//
inline void
ctable_ListInsertBefore (struct ctable_baseRow *row1, struct ctable_baseRow *row2, int i)
{
    // make row2's head point to row1's head
    row2->_ll_nodes[i].head = row1->_ll_nodes[i].head;

    // make row2's prev point to row1's prev
    row2->_ll_nodes[i].prev = row1->_ll_nodes[i].prev;

    // make row2's next point to row1
    row2->_ll_nodes[i].next = row1;

    // make row1's prev's *next* point to row2
    *row1->_ll_nodes[i].prev = row2;

    // make row1's prev point ro row2's next
    row1->_ll_nodes[i].prev = &row2->_ll_nodes[i].next;
}

//
// ctable_ListInsertAfter - insert row2 after row1
//
inline void
ctable_ListInsertAfter (struct ctable_baseRow *row1, struct ctable_baseRow *row2, int i) {
    // make row2's head point to row1's head
    row2->_ll_nodes[i].head = row1->_ll_nodes[i].head;

    // set row2's next pointer to row1's next pointer and see if it's NULL

    if ((row2->_ll_nodes[i].next = row1->_ll_nodes[i].next) != NULL) {

        // it wasn't, make row1's next's prev point to the address of
	// row2's next

        row1->_ll_nodes[i].next->_ll_nodes[i].prev = &row2->_ll_nodes[i].next;
    }

    // in any case, make row1's next point to row2 and
    // make row2's prev point to the address of row1's next

    row1->_ll_nodes[i].next = row2;
    row2->_ll_nodes[i].prev = &row1->_ll_nodes[i].next;
}


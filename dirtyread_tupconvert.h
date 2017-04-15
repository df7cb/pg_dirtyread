/*-------------------------------------------------------------------------
 *
 * tupconvert.h
 *	  Tuple conversion support.
 *
 *
 * Portions Copyright (c) 1996-2017, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/access/tupconvert.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef DIRTYREAD_TUPCONVERT_H
#define DIRTYREAD_TUPCONVERT_H

#include "access/tupconvert.h"

extern TupleConversionMap *dirtyread_convert_tuples_by_name(TupleDesc indesc,
					   TupleDesc outdesc,
					   const char *msg);

extern AttrNumber *dirtyread_convert_tuples_by_name_map(TupleDesc indesc,
						   TupleDesc outdesc,
						   const char *msg);

extern HeapTuple dirtyread_do_convert_tuple(HeapTuple tuple, TupleConversionMap *map, TransactionId oldest_xmin);

#define DeadFakeAttributeNumber FirstLowInvalidHeapAttributeNumber

#endif   /* DIRTYREAD_TUPCONVERT_H */

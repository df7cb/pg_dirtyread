/*-------------------------------------------------------------------------
 *
 * tupconvert.h
 *	  Tuple conversion support.
 *
 *
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/access/tupconvert.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef DIRTYREAD_TUPCONVERT_H
#define DIRTYREAD_TUPCONVERT_H

#include "access/tupconvert.h"
#include "utils/snapmgr.h"

#if PG_VERSION_NUM >= 140000
#define OldestXminType GlobalVisState *
#else
#define OldestXminType TransactionId
#endif

extern TupleConversionMap *dirtyread_convert_tuples_by_name(TupleDesc indesc,
					   TupleDesc outdesc,
					   const char *msg);

extern AttrNumber *dirtyread_convert_tuples_by_name_map(TupleDesc indesc,
						   TupleDesc outdesc,
						   const char *msg);

extern HeapTuple dirtyread_do_convert_tuple(HeapTuple tuple, TupleConversionMap *map, OldestXminType oldest_xmin);

#define DeadFakeAttributeNumber FirstLowInvalidHeapAttributeNumber

#endif							/* TUPCONVERT_H */

/*-------------------------------------------------------------------------
 *
 * Copy of PostgreSQL 11's tupconvert.c for use by pg_dirtyread. The difference
 * is added support for system columns like xmin/xmax/oid. PostgreSQL 14
 * refactored it a lot, but the PG 11 version still works, so we stick with it.
 *
 * tupconvert.c
 *	  Tuple conversion support.
 *
 * These functions provide conversion between rowtypes that are logically
 * equivalent but might have columns in a different order or different sets
 * of dropped columns.  There is some overlap of functionality with the
 * executor's "junkfilter" routines, but these functions work on bare
 * HeapTuples rather than TupleTableSlots.
 *
 * Portions Copyright (c) 1996-2019, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/backend/access/common/tupconvert.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#if PG_VERSION_NUM >= 90300
#include "access/htup_details.h"
#endif
#include "access/tupconvert.h"
#include "access/sysattr.h"
#include "access/xlog.h" /* RecoveryInProgress */
#include "catalog/pg_type.h" /* *OID */
#include "utils/builtins.h"
#if PG_VERSION_NUM >= 120000
#include "access/heapam.h"
#else
#include "utils/tqual.h" /* HeapTupleIsSurelyDead */
#endif

#include "dirtyread_tupconvert.h"

#if PG_VERSION_NUM < 100000
/* from src/include/access/tupdesc.h, introduced in 2cd708452 */
#define TupleDescAttr(tupdesc, i) ((tupdesc)->attrs[(i)])
#endif

/*
 * The conversion setup routines have the following common API:
 *
 * The setup routine checks whether the given source and destination tuple
 * descriptors are logically compatible.  If not, it throws an error.
 * If so, it returns NULL if they are physically compatible (ie, no conversion
 * is needed), else a TupleConversionMap that can be used by do_convert_tuple
 * to perform the conversion.
 *
 * The TupleConversionMap, if needed, is palloc'd in the caller's memory
 * context.  Also, the given tuple descriptors are referenced by the map,
 * so they must survive as long as the map is needed.
 *
 * The caller must supply a suitable primary error message to be used if
 * a compatibility error is thrown.  Recommended coding practice is to use
 * gettext_noop() on this string, so that it is translatable but won't
 * actually be translated unless the error gets thrown.
 *
 *
 * Implementation notes:
 *
 * The key component of a TupleConversionMap is an attrMap[] array with
 * one entry per output column.  This entry contains the 1-based index of
 * the corresponding input column, or zero to force a NULL value (for
 * a dropped output column).  The TupleConversionMap also contains workspace
 * arrays.
 */


/*
 * Set up for tuple conversion, matching input and output columns by name.
 * (Dropped columns are ignored in both input and output.)	This is intended
 * for use when the rowtypes are related by inheritance, so we expect an exact
 * match of both type and typmod.  The error messages will be a bit unhelpful
 * unless both rowtypes are named composite types.
 */
TupleConversionMap *
dirtyread_convert_tuples_by_name(TupleDesc indesc,
					   TupleDesc outdesc,
					   const char *msg)
{
	TupleConversionMap *map;
	AttrNumber *attrMap;
	int			n = outdesc->natts;
	int			i;
	bool		same;

	/* Verify compatibility and prepare attribute-number map */
	attrMap = dirtyread_convert_tuples_by_name_map(indesc, outdesc, msg);

	/*
	 * Check to see if the map is one-to-one, in which case we need not do a
	 * tuple conversion.  We must also insist that both tupdescs either
	 * specify or don't specify an OID column, else we need a conversion to
	 * add/remove space for that.  (For some callers, presence or absence of
	 * an OID column perhaps would not really matter, but let's be safe.)
	 */
	if (indesc->natts == outdesc->natts
#if PG_VERSION_NUM < 120000
			&& indesc->tdhasoid == outdesc->tdhasoid
#endif
			)
	{
		same = true;
		for (i = 0; i < n; i++)
		{
			Form_pg_attribute inatt;
			Form_pg_attribute outatt;

			if (attrMap[i] == (i + 1))
				continue;

			/*
			 * If it's a dropped column and the corresponding input column is
			 * also dropped, we needn't convert.  However, attlen and attalign
			 * must agree.
			 */
			inatt = TupleDescAttr(indesc, i);
			outatt = TupleDescAttr(outdesc, i);
			if (attrMap[i] == 0 &&
				inatt->attisdropped &&
				inatt->attlen == outatt->attlen &&
				inatt->attalign == outatt->attalign)
				continue;

			same = false;
			break;
		}
	}
	else
		same = false;

	if (same)
	{
		/* Runtime conversion is not needed */
		elog(DEBUG1, "tuple conversion is not needed");
		pfree(attrMap);
		return NULL;
	}

	/* Prepare the map structure */
	map = (TupleConversionMap *) palloc(sizeof(TupleConversionMap));
	map->indesc = indesc;
	map->outdesc = outdesc;
#if PG_VERSION_NUM >= 130000
	/* TupleConversionMap->attrMap changed in PG13; luckily our old data structure is just a member of that */
	map->attrMap = (AttrMap *) palloc(sizeof(AttrMap));
	map->attrMap->attnums = attrMap;
	map->attrMap->maplen = n;
#else
	map->attrMap = attrMap;
#endif
	/* preallocate workspace for Datum arrays */
	map->outvalues = (Datum *) palloc(n * sizeof(Datum));
	map->outisnull = (bool *) palloc(n * sizeof(bool));
	n = indesc->natts + 1;		/* +1 for NULL */
	map->invalues = (Datum *) palloc(n * sizeof(Datum));
	map->inisnull = (bool *) palloc(n * sizeof(bool));
	map->invalues[0] = (Datum) 0;	/* set up the NULL entry */
	map->inisnull[0] = true;

	return map;
}

static const struct system_columns_t {
	char	   *attname;
	Oid			atttypid;
	int32		atttypmod;
	int			attnum;
} system_columns[] = {
	{ "ctid",     TIDOID,  -1, SelfItemPointerAttributeNumber },
#if PG_VERSION_NUM < 120000
	{ "oid",      OIDOID,  -1, ObjectIdAttributeNumber },
#endif
	{ "xmin",     XIDOID,  -1, MinTransactionIdAttributeNumber },
	{ "cmin",     CIDOID,  -1, MinCommandIdAttributeNumber },
	{ "xmax",     XIDOID,  -1, MaxTransactionIdAttributeNumber },
	{ "cmax",     CIDOID,  -1, MaxCommandIdAttributeNumber },
	{ "tableoid", OIDOID,  -1, TableOidAttributeNumber },
	{ "dead",     BOOLOID, -1, DeadFakeAttributeNumber }, /* fake column to return HeapTupleIsSurelyDead */
	{ 0 },
};

/*
 * Return a palloc'd bare attribute map for tuple conversion, matching input
 * and output columns by name.  (Dropped columns are ignored in both input and
 * output.)  This is normally a subroutine for convert_tuples_by_name, but can
 * be used standalone.
 *
 * This version from dirtyread_tupconvert.c adds the ability to retrieve dropped
 * columns by requesting "dropped_N" as output column, where N is the attnum.
 */
AttrNumber *
dirtyread_convert_tuples_by_name_map(TupleDesc indesc,
						   TupleDesc outdesc,
						   const char *msg)
{
	AttrNumber *attrMap;
	int			n;
	int			i;

	n = outdesc->natts;
	attrMap = (AttrNumber *) palloc0(n * sizeof(AttrNumber));
	for (i = 0; i < n; i++)
	{
		Form_pg_attribute outatt = TupleDescAttr(outdesc, i);
		char	   *attname;
		Oid			atttypid;
		int32		atttypmod;
		int			j;

		if (outatt->attisdropped)
			continue;			/* attrMap[i] is already 0 */
		attname = NameStr(outatt->attname);
		atttypid = outatt->atttypid;
		atttypmod = outatt->atttypmod;
		for (j = 0; j < indesc->natts; j++)
		{
			Form_pg_attribute inatt = TupleDescAttr(indesc, j);

			if (inatt->attisdropped)
				continue;
			if (strcmp(attname, NameStr(inatt->attname)) == 0)
			{
				/* Found it, check type */
				if (atttypid != inatt->atttypid || atttypmod != inatt->atttypmod)
					ereport(ERROR,
							(errcode(ERRCODE_DATATYPE_MISMATCH),
							 errmsg_internal("%s", _(msg)),
							 errdetail("Attribute \"%s\" has type %s in corresponding attribute of type %s.",
									   attname,
									   format_type_with_typemod(inatt->atttypid, inatt->atttypmod),
									   format_type_be(indesc->tdtypeid))));
				attrMap[i] = (AttrNumber) (j + 1);
				break;
			}
		}

		/* Check dropped columns */
		if (attrMap[i] == 0)
			if (strncmp(attname, "dropped_", sizeof("dropped_") - 1) == 0)
			{
				Form_pg_attribute inatt;
				j = atoi(attname + sizeof("dropped_") - 1);
				if (j < 1 || j > indesc->natts)
					ereport(ERROR,
							(errcode(ERRCODE_DATATYPE_MISMATCH),
							 errmsg_internal("%s", _(msg)),
							 errdetail("Attribute \"%s\" index is out of range 1 .. %d.",
									 attname, indesc->natts)));
				inatt = TupleDescAttr(indesc, j - 1);
				if (! inatt->attisdropped)
					ereport(ERROR,
							(errcode(ERRCODE_DATATYPE_MISMATCH),
							 errmsg_internal("%s", _(msg)),
							 errdetail("Attribute %d is not a dropped column.", j)));

				if (outatt->attlen != inatt->attlen)
					ereport(ERROR,
							(errcode(ERRCODE_DATATYPE_MISMATCH),
							 errmsg_internal("%s", _(msg)),
							 errdetail("Type length of dropped column \"%s\" was %d.",
									   attname, inatt->attlen)));
				if (outatt->attbyval != inatt->attbyval)
					ereport(ERROR,
							(errcode(ERRCODE_DATATYPE_MISMATCH),
							 errmsg_internal("%s", _(msg)),
							 errdetail("\"By value\" of dropped column \"%s\" does not match.",
									   attname)));
				if (outatt->attalign != inatt->attalign)
					ereport(ERROR,
							(errcode(ERRCODE_DATATYPE_MISMATCH),
							 errmsg_internal("%s", _(msg)),
							 errdetail("Alignment of dropped column \"%s\" was %c.",
									   attname, inatt->attalign)));

				inatt->atttypid = atttypid;
				if (atttypmod != inatt->atttypmod)
					ereport(ERROR,
							(errcode(ERRCODE_DATATYPE_MISMATCH),
							 errmsg_internal("%s", _(msg)),
							 errdetail("Type modifier of dropped column \"%s\" was %s.",
									   attname,
									   format_type_with_typemod(inatt->atttypid, inatt->atttypmod))));
				attrMap[i] = (AttrNumber) j;
			}

		/* Check system columns */
		if (attrMap[i] == 0)
			for (j = 0; system_columns[j].attname; j++)
				if (strcmp(attname, system_columns[j].attname) == 0)
				{
					/* Found it, check type */
					if (atttypid != system_columns[j].atttypid || atttypmod != system_columns[j].atttypmod)
						ereport(ERROR,
								(errcode(ERRCODE_DATATYPE_MISMATCH),
								 errmsg_internal("%s", _(msg)),
								 errdetail("Attribute \"%s\" has type %s in corresponding attribute of type %s.",
										   attname,
										   format_type_be(system_columns[j].atttypid),
										   format_type_be(indesc->tdtypeid))));
					/* GetOldestXmin() is not available during recovery */
					if (system_columns[j].attnum == DeadFakeAttributeNumber &&
							RecoveryInProgress())
						ereport(ERROR,
								(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								 errmsg("Cannot use \"dead\" column during recovery")));
					attrMap[i] = system_columns[j].attnum;
					break;
				}

		if (attrMap[i] == 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg_internal("%s", _(msg)),
					 errdetail("Attribute \"%s\" does not exist in type %s.",
							   attname,
							   format_type_be(indesc->tdtypeid))));
	}

	return attrMap;
}

/*
 * Perform conversion of a tuple according to the map.
 */
HeapTuple
dirtyread_do_convert_tuple(HeapTuple tuple, TupleConversionMap *map, OldestXminType oldest_xmin)
{
	AttrNumber *attrMap =
#if PG_VERSION_NUM >= 130000
		map->attrMap->attnums;
#else
		map->attrMap;
#endif
	Datum	   *invalues = map->invalues;
	bool	   *inisnull = map->inisnull;
	Datum	   *outvalues = map->outvalues;
	bool	   *outisnull = map->outisnull;
	int			outnatts = map->outdesc->natts;
	int			i;

	/*
	 * Extract all the values of the old tuple, offsetting the arrays so that
	 * invalues[0] is left NULL and invalues[1] is the first source attribute;
	 * this exactly matches the numbering convention in attrMap.
	 */
	heap_deform_tuple(tuple, map->indesc, invalues + 1, inisnull + 1);

	/*
	 * Transpose into proper fields of the new tuple.
	 */
	for (i = 0; i < outnatts; i++)
	{
		int			j = attrMap[i];

		if (j == DeadFakeAttributeNumber)
		{
			outvalues[i] = HeapTupleIsSurelyDead(tuple
#if PG_VERSION_NUM < 90400
					->t_data
#endif
					, oldest_xmin);
			outisnull[i] = false;
		}
		else if (j < 0)
			outvalues[i] = heap_getsysattr(tuple, j, map->indesc, &outisnull[i]);
		else
		{
			outvalues[i] = invalues[j];
			outisnull[i] = inisnull[j];
		}
	}

	/*
	 * Now form the new tuple.
	 */
	return heap_form_tuple(map->outdesc, outvalues, outisnull);
}

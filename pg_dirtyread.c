/*
 * Copyright (c) 1996-2017, PostgreSQL Global Development Group
 * Copyright (c) 2012, OmniTI Computer Consulting, Inc.
 * Portions Copyright (c) 1994, The Regents of the University of California
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 *       copyright notice, this list of conditions and the following
 *       disclaimer in the documentation and/or other materials provided
 *       with the distribution.
 *     * Neither the name OmniTI Computer Consulting, Inc. nor the names
 *       of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written
 *       permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#include "postgres.h"
#include "funcapi.h"
#include "utils/tqual.h"
#include "utils/rel.h"
#include "catalog/pg_type.h"
#include "access/tupconvert.h"
#if PG_VERSION_NUM >= 90300
#include "access/htup_details.h"
#endif
#include "access/xlog.h" /* RecoveryInProgress */
#include "miscadmin.h" /* superuser */
#include "storage/procarray.h" /* GetOldestXmin */

#include "dirtyread_tupconvert.h"

typedef struct
{
    Relation            rel;
    TupleDesc           reltupdesc;
    TupleConversionMap  *map;
    HeapScanDesc        scan;
    TransactionId       oldest_xmin;
} pg_dirtyread_ctx;

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(pg_dirtyread);
Datum pg_dirtyread(PG_FUNCTION_ARGS);

Datum
pg_dirtyread(PG_FUNCTION_ARGS)
{
    FuncCallContext     *funcctx;
    pg_dirtyread_ctx    *usr_ctx;
    HeapTuple           tuplein;

    if (SRF_IS_FIRSTCALL())
    {
        MemoryContext       oldcontext;
        Oid                 relid;
        TupleDesc           tupdesc;

        if (!superuser())
            ereport(ERROR,
                    (errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
                     errmsg("must be superuser to use pg_dirtyread")));

        relid = PG_GETARG_OID(0);
        if (!OidIsValid(relid))
            elog(ERROR, "invalid relation oid \"%d\"", relid);

        funcctx = SRF_FIRSTCALL_INIT();
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
        usr_ctx = (pg_dirtyread_ctx *) palloc(sizeof(pg_dirtyread_ctx));
        usr_ctx->rel = heap_open(relid, AccessShareLock);
        usr_ctx->reltupdesc = RelationGetDescr(usr_ctx->rel);
        if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
            ereport(ERROR,
                    (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                     errmsg("function returning record called in context "
                         "that cannot accept type record")));
        funcctx->tuple_desc = BlessTupleDesc(tupdesc);
        usr_ctx->map = dirtyread_convert_tuples_by_name(usr_ctx->reltupdesc,
                funcctx->tuple_desc, "Error converting tuple descriptors!");
        usr_ctx->scan = heap_beginscan(usr_ctx->rel, SnapshotAny, 0, NULL);
        /* only call GetOldestXmin while not in recovery */
        if (!RecoveryInProgress())
            usr_ctx->oldest_xmin = GetOldestXmin(
#if PG_VERSION_NUM >= 90400
                usr_ctx->rel
#else
                false /* allDbs */
#endif
                , 0);
        funcctx->user_fctx = (void *) usr_ctx;
        MemoryContextSwitchTo(oldcontext);
    }

    funcctx = SRF_PERCALL_SETUP();
    usr_ctx = (pg_dirtyread_ctx *) funcctx->user_fctx;

    if ((tuplein = heap_getnext(usr_ctx->scan, ForwardScanDirection)) != NULL)
    {
        if (usr_ctx->map != NULL)
        {
            tuplein = dirtyread_do_convert_tuple(tuplein, usr_ctx->map, usr_ctx->oldest_xmin);
            SRF_RETURN_NEXT(funcctx, HeapTupleGetDatum(tuplein));
        }
        else
            SRF_RETURN_NEXT(funcctx, heap_copy_tuple_as_datum(tuplein, usr_ctx->reltupdesc));
    }
    else
    {
        heap_endscan(usr_ctx->scan);
        heap_close(usr_ctx->rel, AccessShareLock);
        SRF_RETURN_DONE(funcctx);
    }
}

/* vim:et
 */

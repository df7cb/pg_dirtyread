CREATE FUNCTION t_infomask(i IN integer,
	HASNULL          OUT boolean,
	HASVARWIDTH      OUT boolean,
	HASEXTERNAL      OUT boolean,
	HASOID_OLD       OUT boolean,
	XMAX_KEYSHR_LOCK OUT boolean,
	COMBOCID         OUT boolean,
	XMAX_EXCL_LOCK   OUT boolean,
	XMAX_LOCK_ONLY   OUT boolean,
	XMIN_COMMITTED   OUT boolean,
	XMIN_INVALID     OUT boolean,
	XMAX_COMMITTED   OUT boolean,
	XMAX_INVALID     OUT boolean,
	XMAX_IS_MULTI    OUT boolean,
	UPDATED          OUT boolean,
	MOVED_OFF        OUT boolean,
	MOVED_IN         OUT boolean)
LANGUAGE SQL
AS $$SELECT
	/* HASNULL          */ i & x'0001'::int <> 0,  /* has null attribute(s) */
	/* HASVARWIDTH      */ i & x'0002'::int <> 0,  /* has variable-width attribute(s) */
	/* HASEXTERNAL      */ i & x'0004'::int <> 0,  /* has external stored attribute(s) */
	/* HASOID_OLD       */ i & x'0008'::int <> 0,  /* has an object-id field */
	/* XMAX_KEYSHR_LOCK */ i & x'0010'::int <> 0,  /* xmax is a key-shared locker */
	/* COMBOCID         */ i & x'0020'::int <> 0,  /* t_cid is a combo cid */
	/* XMAX_EXCL_LOCK   */ i & x'0040'::int <> 0,  /* xmax is exclusive locker */
	/* XMAX_LOCK_ONLY   */ i & x'0080'::int <> 0,  /* xmax, if valid, is only a locker */
	/* XMIN_COMMITTED   */ i & x'0100'::int <> 0,  /* t_xmin committed */
	/* XMIN_INVALID     */ i & x'0200'::int <> 0,  /* t_xmin invalid/aborted */
	/* XMAX_COMMITTED   */ i & x'0400'::int <> 0,  /* t_xmax committed */
	/* XMAX_INVALID     */ i & x'0800'::int <> 0,  /* t_xmax invalid/aborted */
	/* XMAX_IS_MULTI    */ i & x'1000'::int <> 0,  /* t_xmax is a MultiXactId */
	/* UPDATED          */ i & x'2000'::int <> 0,  /* this is UPDATEd version of row */
	/* MOVED_OFF        */ i & x'4000'::int <> 0,  /* moved to another place by pre-9.0 */
	/* MOVED_IN         */ i & x'8000'::int <> 0   /* moved from another place by pre-9.0 */
$$;

CREATE FUNCTION t_infomask2(i2 IN integer,
	NATTS            OUT integer,
	KEYS_UPDATED     OUT boolean,
	HOT_UPDATED      OUT boolean,
	ONLY_TUPLE       OUT boolean)
LANGUAGE SQL
AS $$SELECT
	/* NATTS_MASK       */ i2 & x'07FF'::int,       /* 11 bits for number of attributes */
	/* bits 0x1800 are available */
	/* KEYS_UPDATED     */ i2 & x'2000'::int <> 0,  /* tuple was updated and key cols modified, or tuple deleted */
	/* HOT_UPDATED      */ i2 & x'4000'::int <> 0,  /* tuple was HOT-updated */
	/* ONLY_TUPLE       */ i2 & x'8000'::int <> 0   /* this is heap-only tuple */
$$;

CREATE FUNCTION t_infomask(i IN integer, i2 IN integer,
	HASNULL          OUT boolean,
	HASVARWIDTH      OUT boolean,
	HASEXTERNAL      OUT boolean,
	HASOID_OLD       OUT boolean,
	XMAX_KEYSHR_LOCK OUT boolean,
	COMBOCID         OUT boolean,
	XMAX_EXCL_LOCK   OUT boolean,
	XMAX_LOCK_ONLY   OUT boolean,
	XMIN_COMMITTED   OUT boolean,
	XMIN_INVALID     OUT boolean,
	XMAX_COMMITTED   OUT boolean,
	XMAX_INVALID     OUT boolean,
	XMAX_IS_MULTI    OUT boolean,
	UPDATED          OUT boolean,
	MOVED_OFF        OUT boolean,
	MOVED_IN         OUT boolean,
	NATTS            OUT integer,
	KEYS_UPDATED     OUT boolean,
	HOT_UPDATED      OUT boolean,
	ONLY_TUPLE       OUT boolean)
LANGUAGE SQL
AS $$SELECT * FROM t_infomask(i), t_infomask2(i2)$$;

/* src/include/access/clog.h
#define TRANSACTION_STATUS_IN_PROGRESS      0x00
#define TRANSACTION_STATUS_COMMITTED        0x01
#define TRANSACTION_STATUS_ABORTED          0x02
#define TRANSACTION_STATUS_SUB_COMMITTED    0x03
*/
/* SLRU_PAGES_PER_SEGMENT*BLCKSZ*CLOG_XACTS_PER_BYTE = 1M transactions per file */

CREATE OR REPLACE FUNCTION pg_xact(start bigint, stop bigint, file text DEFAULT 'pg_xact/0000')
RETURNS TABLE(xid bigint, status text)
LANGUAGE SQL
AS $$WITH xact(xact) AS (SELECT pg_read_binary_file(file))
SELECT i,
	CASE 2*get_bit(xact, 2*i::int+1) + get_bit(xact, 2*i::int)
	WHEN 0 THEN 'in progress'
	WHEN 1 THEN 'committed'
	WHEN 2 THEN 'aborted'
	WHEN 3 THEN 'subtransaction commited'
	END
	FROM xact, generate_series(start, stop) g(i)
$$;

CREATE OR REPLACE FUNCTION pg_xact(xid bigint)
RETURNS text
LANGUAGE SQL
AS $$WITH xact(xact, off) AS
	(SELECT pg_read_binary_file('pg_xact/' || repeat('0', 4-length(to_hex(xid >> 20))) || to_hex(xid >> 20)),
		2 * (xid % (1<<20))::int)
SELECT 
	CASE 2 * get_bit(xact, off + 1)::int + get_bit(xact, off)::int
	WHEN 0 THEN 'in progress'
	WHEN 1 THEN 'committed'
	WHEN 2 THEN 'aborted'
	WHEN 3 THEN 'subtransaction commited'
	END
	FROM xact$$;

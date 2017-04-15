MODULE_big = pg_dirtyread
OBJS = pg_dirtyread.o dirtyread_tupconvert.o

EXTENSION = pg_dirtyread
DATA = pg_dirtyread--1.0.sql

REGRESS = extension dirtyread

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

pg_dirtyread.o dirtyread_tupconvert.o: dirtyread_tupconvert.h

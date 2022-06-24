-- Check changing table access method

-- Scenario 1: Heap to Heap
CREATE TABLE heap2heap(a int, b int) DISTRIBUTED BY (a);
CREATE TABLE heap2heap2(a int, b int) DISTRIBUTED BY (a);

INSERT INTO heap2heap SELECT i,i FROM generate_series(1,5) i;
INSERT INTO heap2heap2 SELECT i,i FROM generate_series(1,5) i;

CREATE TEMP TABLE relfilebeforeheap AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('heap2heap', 'heap2heap2')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('heap2heap', 'heap2heap2') ORDER BY segid;

-- changing to the same access method shouldn't rewrite the table
-- (i.e. the relfilenodes shouldn't change)
ALTER TABLE heap2heap SET ACCESS METHOD heap;
ALTER TABLE heap2heap2 SET WITH (appendoptimized=false);

CREATE TEMP TABLE relfileafterheap AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('heap2heap', 'heap2heap2')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('heap2heap', 'heap2heap2') ORDER BY segid;

-- relfilenodes shouldn't change
SELECT count(*) FROM (SELECT * FROM relfilebeforeheap UNION SELECT * FROM relfileafterheap)a;


-- Scenario 2: Heap to AO
CREATE TABLE heap2ao(a int, b int) WITH (fillfactor=70) DISTRIBUTED BY (a);
CREATE TABLE heap2ao2(a int, b int) DISTRIBUTED BY (a);

CREATE INDEX heapi ON heap2ao(b);
ALTER TABLE heap2ao2 ADD CONSTRAINT unique_constraint UNIQUE (a);

INSERT INTO heap2ao SELECT i,i FROM generate_series(1,5) i;
INSERT INTO heap2ao2 SELECT i,i FROM generate_series(1,5) i;

CREATE TEMP TABLE relfilebeforeao AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('heap2ao', 'heap2ao2', 'heapi')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('heap2ao', 'heap2ao2', 'heapi') ORDER BY segid;

-- Altering a heap table with a unique index to AO should error out
-- as unique indexes aren't supported on AO tables
ALTER TABLE heap2ao2 SET ACCESS METHOD ao_row;
ALTER TABLE heap2ao2 DROP CONSTRAINT unique_constraint;

-- Set default storage options for the table to inherit from
SET gp_default_storage_options = 'blocksize=65536, compresstype=zlib, compresslevel=5, checksum=true';

-- Alter table heap to AO should work
ALTER TABLE heap2ao SET ACCESS METHOD ao_row;
ALTER TABLE heap2ao2 SET WITH (appendoptimized=true);

-- The altered table should inherit storage options from gp_default_storage_options
SELECT blocksize,compresslevel,checksum,compresstype,columnstore
FROM pg_appendonly WHERE relid in ('heap2ao'::regclass::oid, 'heap2ao2'::regclass::oid);
SELECT reloptions from pg_class where relname in ('heap2ao', 'heap2ao2');

-- Check data is intact
SELECT * FROM heap2ao;
SELECT * FROM heap2ao2;

-- The tables and indexes should have been rewritten (should have different relfilenodes)
CREATE TEMP TABLE relfileafterao AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('heap2ao', 'heap2ao2', 'heapi')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('heap2ao', 'heap2ao2', 'heapi') ORDER BY segid;

SELECT * FROM relfilebeforeao INTERSECT SELECT * FROM relfileafterao;

-- aux tables are created, pg_appendonly row is created
-- FIXME: add check for gp_aoblkdir
SELECT * FROM gp_toolkit.__gp_aoseg('heap2ao');
SELECT * FROM gp_toolkit.__gp_aovisimap('heap2ao');
SELECT * FROM gp_toolkit.__gp_aoseg('heap2ao2');
SELECT * FROM gp_toolkit.__gp_aovisimap('heap2ao2');


-- check inherited tables
CREATE TABLE heapbase (a int, b int);
CREATE TABLE child (c int) INHERITS (heapbase);
CREATE TABLE heapbase2 (a int, b int);
CREATE TABLE child2 (c int) INHERITS (heapbase2);

INSERT INTO heapbase SELECT i,i FROM generate_series(1,5) i;
INSERT INTO child SELECT i,i,i FROM generate_series(1,5) i;
INSERT INTO heapbase2 SELECT i,i FROM generate_series(1,5) i;
INSERT INTO child2 SELECT i,i,i FROM generate_series(1,5) i;

CREATE TEMP TABLE inheritrelfilebefore AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('heapbase', 'heapbase2')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('heapbase', 'heapbase2') ORDER BY segid;

CREATE TEMP TABLE inheritchildrelfilebefore AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('child', 'child2')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('child', 'child2') ORDER BY segid;

ALTER TABLE heapbase SET ACCESS METHOD ao_row;
ALTER TABLE heapbase2 SET WITH (appendoptimized=true);

-- The altered table should inherit storage options from gp_default_storage_options
show gp_default_storage_options;
SELECT blocksize,compresslevel,checksum,compresstype,columnstore
FROM pg_appendonly WHERE relid in ('heapbase'::regclass::oid, 'heapbase2'::regclass::oid);
SELECT reloptions from pg_class where relname in ('heapbase','heapbase2');

SELECT blocksize,compresslevel,checksum,compresstype,columnstore
FROM pg_appendonly WHERE relid in ('child'::regclass::oid, 'child2'::regclass::oid);
SELECT reloptions from pg_class where relname in ('child','child2');

-- Check data is intact
SELECT * FROM heapbase;
SELECT * FROM heapbase2;

-- relfile node should change for base table set to AO
CREATE TEMP TABLE inheritrelfileafter AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('heapbase', 'heapbase2')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('heapbase', 'heapbase2') ORDER BY segid;

SELECT * FROM inheritrelfilebefore INTERSECT SELECT * FROM inheritrelfileafter;

-- relfile node should not change for child table
CREATE TEMP TABLE inheritchildrelfileafter AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('child', 'child2')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('child', 'child2') ORDER BY segid;

SELECT count(*) FROM (SELECT * FROM inheritchildrelfilebefore UNION SELECT * FROM inheritchildrelfileafter)a;

-- aux tables are created, pg_appendonly row is created
SELECT * FROM gp_toolkit.__gp_aoseg('heapbase');
SELECT * FROM gp_toolkit.__gp_aovisimap('heapbase');
SELECT * FROM gp_toolkit.__gp_aoseg('heapbase2');
SELECT * FROM gp_toolkit.__gp_aovisimap('heapbase2');

-- aux tables are not created for child table
SELECT * FROM gp_toolkit.__gp_aoseg('child');
SELECT * FROM gp_toolkit.__gp_aovisimap('child');
SELECT * FROM gp_toolkit.__gp_aoseg('child2');
SELECT * FROM gp_toolkit.__gp_aovisimap('child2');

-- Scenario 3: AO to Heap
CREATE TABLE ao2heap(a int, b int) WITH (appendonly=true);
CREATE INDEX aoi ON ao2heap(b);

INSERT INTO ao2heap SELECT i,i FROM generate_series(1,5) i;

-- Check once that the AO table has the custom reloptions 
SELECT reloptions FROM pg_class WHERE relname = 'ao2heap';

-- Check once that the AO table has relfrozenxid = 0
SELECT relfrozenxid FROM pg_class WHERE relname = 'ao2heap';

CREATE TEMP TABLE relfilebeforeao2heap AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('ao2heap', 'aoi')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('ao2heap', 'aoi') ORDER BY segid;

-- Altering AO to heap
ALTER TABLE ao2heap SET ACCESS METHOD heap;

-- The tables and indexes should have been rewritten (should have different relfilenodes)
CREATE TEMP TABLE relfileafterao2heap AS
    SELECT -1 segid, relfilenode FROM pg_class WHERE relname in ('ao2heap', 'aoi')
    UNION SELECT gp_segment_id segid, relfilenode FROM gp_dist_random('pg_class')
    WHERE relname in ('ao2heap', 'aoi') ORDER BY segid;

SELECT * FROM relfilebeforeao2heap INTERSECT SELECT * FROM relfileafterao2heap;

-- Check data is intact
SELECT * FROM ao2heap;

-- No AO aux tables should be left
SELECT * FROM gp_toolkit.__gp_aoseg('ao2heap');
SELECT * FROM gp_toolkit.__gp_aovisimap('ao2heap');

-- The new heap table shouldn't have the old AO table's reloptions
SELECT reloptions FROM pg_class WHERE relname = 'ao2heap';

-- The new heap table should have a valid relfrozenxid
SELECT relfrozenxid <> '0' FROM pg_class WHERE relname = 'ao2heap';

DROP TABLE ao2heap;
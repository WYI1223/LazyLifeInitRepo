-- Migration: 0004_fts.sql
-- Purpose: create FTS5 index and trigger-based synchronization for atom content search.
-- Invariants:
-- - only non-deleted atoms are indexed.
-- - inserts/updates/deletes keep FTS rows in sync via triggers.
-- - index bootstrap includes existing non-deleted atoms.
-- Backward compatibility:
-- - additive schema update on top of 0003_external_mappings.sql.

CREATE VIRTUAL TABLE atoms_fts USING fts5(
    content,
    uuid UNINDEXED,
    type UNINDEXED,
    tokenize = 'unicode61'
);

INSERT INTO atoms_fts (rowid, content, uuid, type)
SELECT rowid, content, uuid, type
FROM atoms
WHERE is_deleted = 0;

CREATE TRIGGER atoms_ai_fts
AFTER INSERT ON atoms
WHEN NEW.is_deleted = 0
BEGIN
    INSERT INTO atoms_fts (rowid, content, uuid, type)
    VALUES (NEW.rowid, NEW.content, NEW.uuid, NEW.type);
END;

CREATE TRIGGER atoms_ad_fts
AFTER DELETE ON atoms
WHEN OLD.is_deleted = 0
BEGIN
    DELETE FROM atoms_fts
    WHERE rowid = OLD.rowid;
END;

CREATE TRIGGER atoms_au_fts
AFTER UPDATE ON atoms
BEGIN
    DELETE FROM atoms_fts
    WHERE rowid = OLD.rowid;

    INSERT INTO atoms_fts (rowid, content, uuid, type)
    SELECT NEW.rowid, NEW.content, NEW.uuid, NEW.type
    WHERE NEW.is_deleted = 0;
END;

-- Add a boolean field to the platform table to indicate whether the platform is usable or not (Whether annotation upload completed succesfully or not).
ALTER TABLE platform ADD isAnnotated BOOLEAN NOT NULL DEFAULT 0;

-- All platforms already in there should be marked as annontated.
UPDATE platform SET isAnnotated = 1;

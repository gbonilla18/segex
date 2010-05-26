-- Allow null values in some fields.
ALTER TABLE gene MODIFY source VARCHAR(1022) DEFAULT '';

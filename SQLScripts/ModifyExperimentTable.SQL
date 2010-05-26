-- Add two new columns to the experiment table which will hold text values for the Sample1 and Sample2.
ALTER TABLE experiment ADD sample1 VARCHAR(120) NOT NULL;
ALTER TABLE experiment ADD sample2 VARCHAR(120) NOT NULL;
ALTER TABLE experiment ADD ExperimentDescription VARCHAR(1000);
ALTER TABLE experiment ADD AdditionalInformation VARCHAR(1000);

-- Carry the experiment description for the first sample over from the sample table.
UPDATE	 experiment
INNER JOIN sample ON sample.sid = experiment.sid1
SET	 experiment.sample1 = sample.description;

-- Carry the experiment description for the second sample over from the sample table.
UPDATE	 experiment
INNER JOIN sample ON sample.sid = experiment.sid2
SET	 experiment.sample2 = sample.description;

-- Remove the FK constraints so we can drop the useless columns.
ALTER TABLE experiment DROP FOREIGN KEY experiment_ibfk_2;
ALTER TABLE experiment DROP FOREIGN KEY experiment_ibfk_3;

-- Drop the columns in the experiment table that we don't need anymore.
ALTER TABLE experiment DROP sid1;
ALTER TABLE experiment DROP sid2;



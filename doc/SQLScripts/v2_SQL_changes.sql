-- 06/01/11

CREATE TABLE `project` (
  `prid` int(10) NOT NULL AUTO_INCREMENT,
  `prname` varchar(255) NOT NULL DEFAULT 'New Project',
  `prdesc` varchar(1023) NOT NULL DEFAULT '',
  `manager` int(10) unsigned,
  PRIMARY KEY (`prid`),
  UNIQUE KEY `prname` (`prname`),
  KEY `manager` (`manager`),
  CONSTRAINT `project_ibfk_1` FOREIGN KEY (`manager`) REFERENCES `users` (`uid`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE `ProjectStudy` (
  `prid` int(10) NOT NULL,
  `stid` int(10) NOT NULL,
  PRIMARY KEY (`prid`,`stid`),
  KEY `prid` (`prid`),
  KEY `stid` (`stid`),
  CONSTRAINT `ProjectStudy_ibfk_1` FOREIGN KEY (`prid`) REFERENCES `project` (`prid`) ON DELETE CASCADE,
  CONSTRAINT `ProjectStudy_ibfk_2` FOREIGN KEY (`stid`) REFERENCES `study` (`stid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;


-- 07/07/11

ALTER TABLE experiment ADD COLUMN pid INT(11) DEFAULT NULL;
UPDATE experiment SET pid=(SELECT DISTINCT pid FROM StudyExperiment NATURAL JOIN study WHERE eid=experiment.eid);

-- 07/15/11

-- allow creating temporary tables that are dropped on session close
GRANT CREATE TEMPORARY TABLES ON `segex_dev`.* TO 'segex_dev_user'@'localhost';

-- 07/19/11

-- now that we are using temporary tables for data upload and extended queries,
-- there is no need to allow the default user to create and drop tables:
REVOKE CREATE ON segex_dev.* FROM segex_dev_user@localhost;
REVOKE DROP ON segex_dev.* FROM segex_dev_user@localhost;

-- after the above modifications, the current grants for segex_dev_user look 
-- like this (note: password hash modified for security):
--   SHOW GRANTS FOR segex_dev_user@localhost;
-- Grants for segex_dev_user@localhost                                                                                   |
--   GRANT USAGE ON *.* TO 'segex_dev_user'@'localhost' IDENTIFIED BY PASSWORD '*FD47988C0D40379E291810379ABDE31248655F1C' |
--   GRANT SELECT, INSERT, UPDATE, DELETE, CREATE TEMPORARY TABLES ON `segex_dev`.* TO 'segex_dev_user'@'localhost'        |

-- no need for table `sample` anymore:
DROP TABLE sample;

-- Queries below move long annotation from seqname field to description (OK-ed by Dr. Waxman, 07/20/11)
UPDATE gene SET description=seqname WHERE ISNULL(description) AND seqname REGEXP ' ';
-- Query OK, 18 rows affected (0.53 sec)
UPDATE gene SET seqname=NULL WHERE description=seqname AND seqname REGEXP ' ';
-- Query OK, 403 rows affected (0.66 sec)
UPDATE gene SET seqname=NULL WHERE seqname REGEXP ' ';
-- Query OK, 9 rows affected (0.57 sec)

UPDATE gene SET seqname='Tcte3' WHERE seqname='Tcte3///100041586///100041639';

-- at this point, no valid seqname is longer than 24 characters
alter table gene modify seqname char(30);
alter table gene modify accnum char(30);
alter table probe modify reporter char(18) not null;

-- rebuild indexes
drop index seqname on gene;
drop index accnum on gene;
create index seqname on gene (seqname);
create index accnum on gene (accnum);

-- remove 'note' field from probes
alter table probe drop column note;

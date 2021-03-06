-- MySQL dump 10.13  Distrib 5.1.57, for apple-darwin10.3.0 (i386)
--
-- Host: localhost    Database: segex_dev
-- ------------------------------------------------------
-- Server version	5.1.57-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `GeneGO`
--

DROP TABLE IF EXISTS `GeneGO`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `GeneGO` (
  `gid` int(10) unsigned NOT NULL,
  `go_acc` int(7) unsigned zerofill NOT NULL,
  PRIMARY KEY (`gid`,`go_acc`),
  KEY `gid` (`gid`),
  KEY `go_acc` (`go_acc`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ProbeGene`
--

DROP TABLE IF EXISTS `ProbeGene`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ProbeGene` (
  `rid` int(10) unsigned NOT NULL,
  `gid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`rid`,`gid`),
  KEY `rid` (`rid`),
  KEY `gid` (`gid`),
  CONSTRAINT `ProbeGene_ibfk_1` FOREIGN KEY (`rid`) REFERENCES `probe` (`rid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ProjectStudy`
--

DROP TABLE IF EXISTS `ProjectStudy`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ProjectStudy` (
  `prid` int(10) unsigned NOT NULL,
  `stid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`prid`,`stid`),
  KEY `prid` (`prid`),
  KEY `stid` (`stid`),
  CONSTRAINT `ProjectStudy_ibfk_1` FOREIGN KEY (`prid`) REFERENCES `project` (`prid`) ON DELETE CASCADE,
  CONSTRAINT `ProjectStudy_ibfk_2` FOREIGN KEY (`stid`) REFERENCES `study` (`stid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `StudyExperiment`
--

DROP TABLE IF EXISTS `StudyExperiment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `StudyExperiment` (
  `stid` int(10) unsigned NOT NULL,
  `eid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`stid`,`eid`),
  KEY `eid` (`eid`),
  KEY `stid` (`stid`),
  CONSTRAINT `studyexperiment_ibfk_1` FOREIGN KEY (`eid`) REFERENCES `experiment` (`eid`) ON DELETE CASCADE,
  CONSTRAINT `studyexperiment_ibfk_2` FOREIGN KEY (`stid`) REFERENCES `study` (`stid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `experiment`
--

DROP TABLE IF EXISTS `experiment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `experiment` (
  `eid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `public` tinyint(1) NOT NULL DEFAULT '0',
  `sample1` varchar(255) NOT NULL DEFAULT '',
  `sample2` varchar(255) NOT NULL DEFAULT '',
  `ExperimentDescription` varchar(1023) NOT NULL DEFAULT '',
  `AdditionalInformation` varchar(1023) NOT NULL DEFAULT '',
  `pid` int(10) unsigned NOT NULL,
  `PValFlag` tinyint(1) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`eid`),
  KEY `pid` (`pid`),
  CONSTRAINT `experiment_ibfk_1` FOREIGN KEY (`pid`) REFERENCES `platform` (`pid`)
) ENGINE=InnoDB AUTO_INCREMENT=154 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `gene`
--

DROP TABLE IF EXISTS `gene`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `gene` (
  `gid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `sid` int(10) unsigned NOT NULL,
  `gtype` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `gsymbol` char(32) NOT NULL,
  `gname` varchar(1022) DEFAULT NULL,
  `gdesc` varchar(2044) DEFAULT NULL,
  PRIMARY KEY (`gid`),
  UNIQUE KEY `sid_gsymbol` (`sid`,`gsymbol`),
  KEY `sid` (`sid`),
  FULLTEXT KEY `full` (`gsymbol`,`gname`,`gdesc`)
) ENGINE=MyISAM AUTO_INCREMENT=174422 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `go_term`
--

DROP TABLE IF EXISTS `go_term`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `go_term` (
  `go_acc` int(7) unsigned zerofill NOT NULL,
  `go_term_type` varchar(55) NOT NULL,
  `go_name` varchar(255) NOT NULL DEFAULT '',
  `go_term_definition` text,
  `go_term_id` int(10) unsigned NOT NULL,
  PRIMARY KEY (`go_term_id`),
  UNIQUE KEY `go_acc` (`go_acc`),
  FULLTEXT KEY `full` (`go_name`,`go_term_definition`),
  FULLTEXT KEY `names` (`go_name`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `locus`
--

DROP TABLE IF EXISTS `locus`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `locus` (
  `rid` int(10) unsigned NOT NULL,
  `sid` int(10) unsigned NOT NULL,
  `chr` varchar(127) NOT NULL,
  `zinterval` geometry NOT NULL,
  SPATIAL KEY `zinterval` (`zinterval`),
  KEY `rid` (`rid`),
  KEY `sid_chr` (`sid`,`chr`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `platform`
--

DROP TABLE IF EXISTS `platform`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `platform` (
  `pid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `pname` varchar(120) NOT NULL,
  `def_p_cutoff` double DEFAULT NULL,
  `def_f_cutoff` double DEFAULT NULL,
  `sid` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`pid`),
  UNIQUE KEY `pname` (`pname`),
  KEY `sid` (`sid`),
  CONSTRAINT `platform_ibfk_1` FOREIGN KEY (`sid`) REFERENCES `species` (`sid`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `probe`
--

DROP TABLE IF EXISTS `probe`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `probe` (
  `rid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `reporter` char(18) NOT NULL,
  `probe_sequence` varchar(100) DEFAULT NULL,
  `pid` int(10) unsigned NOT NULL,
  `probe_comment` varchar(2047) DEFAULT NULL,
  PRIMARY KEY (`rid`),
  UNIQUE KEY `pid_reporter` (`pid`,`reporter`),
  KEY `pid` (`pid`),
  CONSTRAINT `probe_ibfk_1` FOREIGN KEY (`pid`) REFERENCES `platform` (`pid`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=382534 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `project`
--

DROP TABLE IF EXISTS `project`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `project` (
  `prid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `prname` varchar(255) NOT NULL DEFAULT '',
  `prdesc` varchar(1023) NOT NULL DEFAULT '',
  PRIMARY KEY (`prid`),
  UNIQUE KEY `prname` (`prname`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `response`
--

DROP TABLE IF EXISTS `response`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `response` (
  `eid` int(10) unsigned NOT NULL,
  `rid` int(10) unsigned NOT NULL,
  `ratio` double DEFAULT NULL,
  `foldchange` double DEFAULT NULL,
  `intensity1` double DEFAULT NULL,
  `intensity2` double DEFAULT NULL,
  `pvalue1` double DEFAULT NULL,
  `pvalue2` double DEFAULT NULL,
  `pvalue3` double DEFAULT NULL,
  `pvalue4` double DEFAULT NULL,
  PRIMARY KEY (`eid`,`rid`),
  KEY `rid` (`rid`),
  KEY `eid` (`eid`),
  CONSTRAINT `response_ibfk_1` FOREIGN KEY (`eid`) REFERENCES `experiment` (`eid`) ON DELETE CASCADE,
  CONSTRAINT `response_ibfk_2` FOREIGN KEY (`rid`) REFERENCES `probe` (`rid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `sessions`
--

DROP TABLE IF EXISTS `sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `sessions` (
  `id` char(32) NOT NULL,
  `a_session` text NOT NULL,
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `species`
--

DROP TABLE IF EXISTS `species`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `species` (
  `sid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `sname` varchar(64) NOT NULL,
  `slatin` varchar(64) DEFAULT NULL,
  `sncbi` varchar(64) NOT NULL,
  `sversion` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`sid`),
  UNIQUE KEY `sname` (`sname`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `study`
--

DROP TABLE IF EXISTS `study`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `study` (
  `stid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `description` varchar(255) NOT NULL DEFAULT '',
  `pubmed` varchar(255) NOT NULL DEFAULT '',
  `pid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`stid`),
  UNIQUE KEY `pid_description` (`pid`,`description`),
  KEY `pid` (`pid`),
  CONSTRAINT `study_ibfk_1` FOREIGN KEY (`pid`) REFERENCES `platform` (`pid`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=34 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `users` (
  `uid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `uname` varchar(60) NOT NULL DEFAULT '',
  `pwd` char(40) DEFAULT NULL,
  `email` varchar(127) NOT NULL DEFAULT '',
  `full_name` varchar(255) NOT NULL DEFAULT '',
  `address` varchar(255) DEFAULT NULL,
  `phone` varchar(127) DEFAULT NULL,
  `level` enum('nogrants','readonly','user','admin') NOT NULL DEFAULT 'nogrants',
  `email_confirmed` tinyint(1) DEFAULT '0',
  `udate` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`uid`),
  UNIQUE KEY `uname` (`uname`)
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping routines for database 'segex_dev'
--
/*!50003 DROP FUNCTION IF EXISTS `format_locus` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = latin1 */ ;
/*!50003 SET character_set_results = latin1 */ ;
/*!50003 SET collation_connection  = latin1_swedish_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50020 DEFINER=`root`@`localhost`*/ /*!50003 FUNCTION `format_locus`(chr varchar(127), zinterval geometry) RETURNS varchar(255) CHARSET latin1
    NO SQL
    DETERMINISTIC
BEGIN
DECLARE tuple_content varchar(127);
SET tuple_content = SUBSTRING_INDEX(SUBSTRING_INDEX(AsText(zinterval), '(', -1),')',1);
RETURN CONCAT('chr', chr, ':', FORMAT(SUBSTRING_INDEX(TRIM(SUBSTRING_INDEX(tuple_content, ',', 1)), ' ', -1), 0), '-', FORMAT(SUBSTRING_INDEX(TRIM(SUBSTRING_INDEX(tuple_content, ',', -1)), ' ', -1), 0));
    END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2012-05-12 20:01:37

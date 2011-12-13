-- MySQL dump 10.13  Distrib 5.1.57, for apple-darwin10.3.0 (i386)
--
-- Host: localhost    Database: segex_dev
-- ------------------------------------------------------
-- Server version	5.1.57

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
-- Table structure for table `accnum`
--

DROP TABLE IF EXISTS `accnum`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `accnum` (
  `rid` int(10) unsigned NOT NULL,
  `accnum` char(20) NOT NULL DEFAULT '',
  PRIMARY KEY (`rid`,`accnum`),
  KEY `rid` (`rid`),
  CONSTRAINT `accnum_ibfk_1` FOREIGN KEY (`rid`) REFERENCES `probe` (`rid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `annotates`
--

DROP TABLE IF EXISTS `annotates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `annotates` (
  `rid` int(10) unsigned NOT NULL,
  `gid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`rid`,`gid`),
  KEY `gid` (`gid`)
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
  PRIMARY KEY (`eid`),
  KEY `pid` (`pid`),
  CONSTRAINT `experiment_ibfk_1` FOREIGN KEY (`pid`) REFERENCES `platform` (`pid`)
) ENGINE=InnoDB AUTO_INCREMENT=143 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `gene`
--

DROP TABLE IF EXISTS `gene`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `gene` (
  `gid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `seqname` char(30) DEFAULT NULL,
  `accnum` char(30) DEFAULT NULL,
  `description` varchar(1022) DEFAULT NULL,
  `gene_note` varchar(1022) DEFAULT NULL,
  PRIMARY KEY (`gid`),
  UNIQUE KEY `gid` (`gid`),
  KEY `accnum_seqname` (`accnum`,`seqname`(18)),
  KEY `seqname` (`seqname`),
  KEY `accnum` (`accnum`)
) ENGINE=InnoDB AUTO_INCREMENT=360282 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `go_link`
--

DROP TABLE IF EXISTS `go_link`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `go_link` (
  `rid` int(10) unsigned NOT NULL,
  `go_acc` int(10) unsigned NOT NULL,
  PRIMARY KEY (`rid`,`go_acc`),
  KEY `rid` (`rid`),
  KEY `go_acc` (`go_acc`),
  CONSTRAINT `go_link_ibfk_1` FOREIGN KEY (`rid`) REFERENCES `probe` (`rid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `go_term`
--

DROP TABLE IF EXISTS `go_term`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `go_term` (
  `go_term_id` int(10) unsigned NOT NULL,
  `go_acc` int(10) unsigned NOT NULL,
  `go_term_type` varchar(55) NOT NULL,
  `go_name` varchar(255) NOT NULL DEFAULT '',
  `go_term_definition` text,
  PRIMARY KEY (`go_term_id`),
  UNIQUE KEY `go_acc` (`go_acc`),
  FULLTEXT KEY `full` (`go_name`,`go_term_definition`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `location`
--

DROP TABLE IF EXISTS `location`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `location` (
  `rid` int(10) unsigned NOT NULL,
  `chromosome` varchar(127) DEFAULT NULL,
  `start` int(10) unsigned DEFAULT NULL,
  `end` int(10) unsigned DEFAULT NULL,
  `sid` int(10) unsigned NOT NULL,
  KEY `rid` (`rid`),
  KEY `sid` (`sid`),
  KEY `common` (`sid`,`chromosome`(2),`start`,`end`),
  CONSTRAINT `location_ibfk_1` FOREIGN KEY (`rid`) REFERENCES `probe` (`rid`) ON DELETE CASCADE,
  CONSTRAINT `location_ibfk_2` FOREIGN KEY (`sid`) REFERENCES `species` (`sid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `microarray`
--

DROP TABLE IF EXISTS `microarray`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `microarray` (
  `eid` int(10) unsigned NOT NULL,
  `rid` int(10) unsigned NOT NULL,
  `ratio` double DEFAULT NULL,
  `foldchange` double DEFAULT NULL,
  `pvalue` double DEFAULT NULL,
  `intensity2` double DEFAULT NULL,
  `intensity1` double DEFAULT NULL,
  PRIMARY KEY (`eid`,`rid`),
  KEY `rid` (`rid`),
  KEY `eid` (`eid`),
  CONSTRAINT `microarray_ibfk_1` FOREIGN KEY (`eid`) REFERENCES `experiment` (`eid`) ON DELETE CASCADE,
  CONSTRAINT `microarray_ibfk_2` FOREIGN KEY (`rid`) REFERENCES `probe` (`rid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
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
  KEY `sid` (`sid`),
  CONSTRAINT `platform_ibfk_1` FOREIGN KEY (`sid`) REFERENCES `species` (`sid`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=latin1;
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
  PRIMARY KEY (`rid`),
  UNIQUE KEY `reporter_pid` (`reporter`,`pid`),
  KEY `pid` (`pid`),
  CONSTRAINT `probe_ibfk_1` FOREIGN KEY (`pid`) REFERENCES `platform` (`pid`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=316999 DEFAULT CHARSET=latin1;
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
  `manager` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`prid`),
  UNIQUE KEY `prname` (`prname`),
  KEY `manager` (`manager`),
  CONSTRAINT `project_ibfk_1` FOREIGN KEY (`manager`) REFERENCES `users` (`uid`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;
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
  `sname` varchar(120) NOT NULL,
  PRIMARY KEY (`sid`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;
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
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=latin1;
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
  `pwd` char(40) NOT NULL,
  `email` varchar(127) NOT NULL DEFAULT '',
  `full_name` varchar(255) NOT NULL DEFAULT '',
  `address` varchar(255) NOT NULL DEFAULT '',
  `phone` varchar(127) NOT NULL DEFAULT '',
  `level` enum('','user','admin') NOT NULL DEFAULT '',
  `email_confirmed` tinyint(1) DEFAULT '0',
  `udate` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`uid`),
  UNIQUE KEY `uname` (`uname`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2011-12-12  4:57:22

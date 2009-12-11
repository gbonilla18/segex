-- MySQL dump 10.11
--
-- Host: localhost    Database: group_2_test
-- ------------------------------------------------------
-- Server version	5.0.77

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
-- Table structure for table `annotates`
--

DROP TABLE IF EXISTS `annotates`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `annotates` (
  `rid` int(10) NOT NULL,
  `gid` int(10) NOT NULL,
  PRIMARY KEY  (`rid`,`gid`),
  KEY `gid` (`gid`),
  CONSTRAINT `annotates_ibfk_3` FOREIGN KEY (`rid`) REFERENCES `probe` (`rid`) ON DELETE CASCADE,
  CONSTRAINT `annotates_ibfk_4` FOREIGN KEY (`gid`) REFERENCES `gene` (`gid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `experiment`
--

DROP TABLE IF EXISTS `experiment`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `experiment` (
  `eid` int(3) NOT NULL auto_increment,
  `sid2` int(3) NOT NULL,
  `sid1` int(3) NOT NULL,
  `stid` int(1) default NULL,
  `public` tinyint(1) NOT NULL default '0',
  PRIMARY KEY  (`eid`),
  KEY `sid1` (`sid1`),
  KEY `sid2` (`sid2`),
  KEY `stid` (`stid`),
  CONSTRAINT `experiment_ibfk_1` FOREIGN KEY (`stid`) REFERENCES `study` (`stid`) ON UPDATE CASCADE,
  CONSTRAINT `experiment_ibfk_2` FOREIGN KEY (`sid2`) REFERENCES `sample` (`sid`) ON UPDATE CASCADE,
  CONSTRAINT `experiment_ibfk_3` FOREIGN KEY (`sid1`) REFERENCES `sample` (`sid`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=31 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `gene`
--

DROP TABLE IF EXISTS `gene`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `gene` (
  `gid` int(11) NOT NULL auto_increment,
  `seqname` varchar(200) default NULL,
  `accnum` varchar(30) default NULL,
  `description` varchar(1022) default NULL,
  `gene_note` varchar(1022) default NULL,
  `pid` int(11) NOT NULL,
  PRIMARY KEY  (`gid`),
  UNIQUE KEY `tgp` (`seqname`,`accnum`,`pid`),
  KEY `accnum` (`accnum`),
  KEY `seqname` (`seqname`(18)),
  KEY `pid` (`pid`),
  CONSTRAINT `gene_ibfk_1` FOREIGN KEY (`pid`) REFERENCES `platform` (`pid`)
) ENGINE=InnoDB AUTO_INCREMENT=2564138 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `microarray`
--

DROP TABLE IF EXISTS `microarray`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `microarray` (
  `eid` int(3) NOT NULL,
  `rid` int(10) NOT NULL,
  `ratio` double default NULL,
  `foldchange` double default NULL,
  `pvalue` double default NULL,
  `intensity2` double default NULL,
  `intensity1` double default NULL,
  PRIMARY KEY  (`eid`,`rid`),
  KEY `rid` (`rid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `platform`
--

DROP TABLE IF EXISTS `platform`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `platform` (
  `pid` int(11) NOT NULL auto_increment,
  `pname` varchar(20) NOT NULL,
  `def_p_cutoff` double default NULL,
  `def_f_cutoff` double default NULL,
  `species` varchar(255) default NULL,
  PRIMARY KEY  (`pid`),
  UNIQUE KEY `pname` (`pname`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `probe`
--

DROP TABLE IF EXISTS `probe`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `probe` (
  `rid` int(11) NOT NULL auto_increment,
  `reporter` varchar(30) NOT NULL,
  `probe_sequence` varchar(100) default NULL,
  `pid` int(11) NOT NULL,
  `note` varchar(1022) default NULL,
  PRIMARY KEY  (`rid`),
  UNIQUE KEY `reporter_pid` (`reporter`,`pid`),
  KEY `pid` (`pid`),
  CONSTRAINT `probe_ibfk_1` FOREIGN KEY (`pid`) REFERENCES `platform` (`pid`)
) ENGINE=InnoDB AUTO_INCREMENT=3810375 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `sample`
--

DROP TABLE IF EXISTS `sample`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `sample` (
  `sid` int(3) NOT NULL auto_increment,
  `genotype` varchar(15) NOT NULL,
  `sex` enum('M','F') NOT NULL,
  `description` varchar(100) NOT NULL,
  PRIMARY KEY  (`sid`)
) ENGINE=InnoDB AUTO_INCREMENT=61 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `sessions`
--

DROP TABLE IF EXISTS `sessions`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `sessions` (
  `id` char(32) NOT NULL,
  `a_session` text NOT NULL,
  UNIQUE KEY `id` (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `study`
--

DROP TABLE IF EXISTS `study`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `study` (
  `stid` int(1) NOT NULL auto_increment,
  `description` varchar(100) NOT NULL default 'none',
  `pubmed` varchar(20) NOT NULL,
  `pid` int(11) default NULL,
  PRIMARY KEY  (`stid`),
  KEY `pid` (`pid`),
  CONSTRAINT `study_ibfk_1` FOREIGN KEY (`pid`) REFERENCES `platform` (`pid`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `users` (
  `uid` int(10) unsigned NOT NULL auto_increment,
  `uname` varchar(60) NOT NULL,
  `pwd` char(40) NOT NULL,
  `email` varchar(60) NOT NULL,
  `full_name` varchar(100) NOT NULL,
  `address` varchar(200) default NULL,
  `phone` varchar(60) default NULL,
  `level` enum('unauth','user','admin') NOT NULL default 'unauth',
  `email_confirmed` tinyint(1) default '0',
  PRIMARY KEY  (`uid`),
  UNIQUE KEY `uname` (`uname`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2009-12-11 18:19:42

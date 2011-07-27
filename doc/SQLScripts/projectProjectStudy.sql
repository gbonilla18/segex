-- MySQL dump 10.11
--
-- Host: localhost    Database: segex_dev
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
-- Table structure for table `project`
--

DROP TABLE IF EXISTS `project`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `project` (
  `prid` int(10) NOT NULL auto_increment,
  `prname` varchar(255) NOT NULL default 'New Project',
  `prdesc` varchar(1023) NOT NULL default '',
  `manager` int(10) unsigned default NULL,
  PRIMARY KEY  (`prid`),
  UNIQUE KEY `prname` (`prname`),
  KEY `manager` (`manager`),
  CONSTRAINT `project_ibfk_1` FOREIGN KEY (`manager`) REFERENCES `users` (`uid`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Dumping data for table `project`
--

LOCK TABLES `project` WRITE;
/*!40000 ALTER TABLE `project` DISABLE KEYS */;
INSERT INTO `project` VALUES (1,'Liver Sexual Dimorphism','',NULL),(2,'Xenoestrogens','',NULL),(3,'Cancer Therapy','',NULL);
/*!40000 ALTER TABLE `project` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ProjectStudy`
--

DROP TABLE IF EXISTS `ProjectStudy`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `ProjectStudy` (
  `prid` int(10) NOT NULL,
  `stid` int(10) NOT NULL,
  PRIMARY KEY  (`prid`,`stid`),
  KEY `prid` (`prid`),
  KEY `stid` (`stid`),
  CONSTRAINT `ProjectStudy_ibfk_1` FOREIGN KEY (`prid`) REFERENCES `project` (`prid`) ON DELETE CASCADE,
  CONSTRAINT `ProjectStudy_ibfk_2` FOREIGN KEY (`stid`) REFERENCES `study` (`stid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Dumping data for table `ProjectStudy`
--

LOCK TABLES `ProjectStudy` WRITE;
/*!40000 ALTER TABLE `ProjectStudy` DISABLE KEYS */;
INSERT INTO `ProjectStudy` VALUES (1,1),(1,2),(1,3),(1,4),(1,5),(1,6),(1,7),(1,8),(1,16),(1,19),(1,26),(2,9),(2,10),(2,11),(2,12),(2,18),(2,24),(2,27),(2,28),(2,29),(3,13),(3,14),(3,15),(3,20),(3,21),(3,23);
/*!40000 ALTER TABLE `ProjectStudy` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2011-07-27 20:54:04

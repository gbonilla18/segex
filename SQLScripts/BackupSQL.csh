#/bin/sh

#Remove the 4th file.
rm /var/www/SQLScripts/Backup4.sql

#Rename 3rd to 4th.
cp /var/www/SQLScripts/Backup3.sql /var/www/SQLScripts/Backup4.sql

#Rename 2nd to 3rd.
cp /var/www/SQLScripts/Backup2.sql /var/www/SQLScripts/Backup3.sql

#Rename 1st to 2nd.
cp /var/www/SQLScripts/Backup1.sql /var/www/SQLScripts/Backup2.sql

#Dump the database file.
mysqldump group_2 -u root -pWELCHgrape55 > /var/www/SQLScripts/Backup1.sql


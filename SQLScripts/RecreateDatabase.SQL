mysql -u root group_2 < /home/mmcduffie/WaxmanSQL/sql_prod.dump -p
mysql -u root group_2 < /var/www/SQLScripts/ModifyExperimentTable.SQL -p
mysql -u root group_2 < /var/www/SQLScripts/ModifyPlatformTable.SQL -p
mysql -u root group_2 < /var/www/SQLScripts/FixGeneNullColumns.SQL -p
mysql -u root group_2 < /var/www/SQLScripts/AddAutoIncrementFields.SQL -p

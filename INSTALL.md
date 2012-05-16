INSTALL
======

Table of Contents
-----------------

1. [Linux](#1-linux)

   1.1. [Software Install on Linux](#11-software-install-on-linux)

   1.2. [Database Setup on Linux](#12-database-setup-mysql-on-linux)

2. [Mac OS X](#2-mac-os-x)

   2.1. [Software Install on Mac OS X](#21-software-install-mac-os-x)

   2.2. [Database Setup on Mac OS X](#database-setup-mysql-on-mac-os-x)

3. [APPENDIX A: Cloning Segex from GitHub repository](#appendix-a-cloning-segex-from-github-repository)


# 1. Linux

## 1.1. Software Install on Linux

### Install dependencies
Upgrade your `cpan` executable and install/upgrade all of the required packages:

	sudo /usr/bin/cpan Bundle::CPAN

	sudo /usr/bin/cpan Apache::Session::MySQL CGI::Carp CGI::Cookie \
	  Config::General DBD::mysql DBI Data::Dumper Data::UUID Digest::SHA1 \
	  Email::Address Exception::Class Exception::Class::DBI Hash::Merge JSON \
	  JSON::XS Lingua::EN::Inflect List::Util Mail::Send Math::BigFloat Math::BigInt \
	  Readonly Scalar::Util Storable Text::Autoformat Text::CSV Text::CSV_XS \
	  Tie::IxHash URI::Escape

Repeating the second command will help you confirm whether all of the required
Perl packages were installed successfully.


### Copy files
If you choose to create soft links instead, add `FollowSymLinks` directive to
the Apache configuration file (either local `.htaccess` or the top-level
`httpd.conf` depending on your setup) for both CGI_ROOT and DOCUMENTS_ROOT
directories. Note: this assumes you have downloaded [YUI
2](http://developer.yahoo.com/yui/2/) to `~/tarballs/yui.tgz`.

	# CGI_ROOT
	
	# /cgi-bin/segex
	cd /var/www/cgi-bin
	sudo cp -R ~/segex/cgi-bin segex
	sudo cp ~/segex/segex.conf.sample segex/segex.conf
	
	# DOCUMENTS_ROOT
	
	# /yui
	cd /var/www/
	tar xvzf ~/tarballs/yui.tgz .
	
	# /segex/
	mkdir segex
	cd segex
	
	# /segex/css
	sudo cp -R ~/segex/css .
	
	# /segex/images
	sudo cp -R ~/segex/images .
	
	# /segex/js
	sudo cp -R ~/segex/js .


### Change Segex configuration file
In the configuration file located at `cgi-bin/segex.conf`, check that path to
default mailer program (sendmail, postfix, etc) is set correctly. On Linux Cent
OS, this path is `/usr/sbin`:

	mailer_path = "/usr/sbin"

Set up a log file where program error messages would go to. The default path to
the log file is set in the following line:

	debug_log_path = "/var/www/error_log/segex_log"

Change that path if necessary and create the log file and set up appropriate
permissions to let Apache write to the file:

	cd /var/www/error_log/
	sudo touch segex_log
	sudo chown nobody:nobody segex_log

If you do not wish to redirect warnings and error messages, comment out the line
which begins with `debug_log_path`.

For production version, change values for `debug_errors_to_browser` and
`debug_caller_info` to `"no"`. This is important because Segex error messages
may contain sensitive information such as user names, and you do not want
everyone to see them.


### Configure web server
If `AllowOverride` is set in your main Apache configuration file (on CentOS
Linux it is `/etc/httpd/conf/httpd.conf`), you will have to modify `.htaccess`
file in the `cgi-bin/` directory to reflect the correct URI path to `index.cgi`.
This is because the `.htaccess` file included in Segex distribution enables URI
rewriting, and without verifying that the path it uses is correct, URIs may be
rewritten incorrectly:

Here is example of the `AllowOverride` setting in `httpd.conf` that enables
overrides:

	<Directory "/var/www/cgi-bin">
	   AllowOverride Options FileInfo
	   ...

Here is the line in `cgi-bin/.htaccess` that may need to be changed (for
example, if you call your segex executable directory "segex2", you would have to
change "segex" to "segex2" below:

	RewriteRule ^$ /cgi-bin/segex/index.cgi





## 1.2. Database Setup (MySQL) on Linux


### Allow searches on three-letter words
[Optional] To allow for full-text searches on three-letter words and acronyms
such as DNA, RNA, etc., edit file called `my.cnf` (CentOS: `/etc/my.cnf`) and
add the following line(s) under section `[mysqld]`:

	[mysqld]
	# Allow full-text indexes on three-letter words such as DNA, RNA, etc.
	ft_min_word_len=3

Next, restart MySQL server:

	sudo service mysqld restart


### Create empty database and corresponding user account
Note: in the default MySQL installation, the root password is empty (simply hit
enter to proceed).

	mysql -u root -p
	> CREATE DATABASE segex;
	> CREATE USER 'segex_user'@'localhost' IDENTIFIED BY 'segex_user_password';
	> GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE, CREATE TEMPORARY TABLES
	  ON segex.* TO 'segex_user'@'localhost';

Do not forget to change 'segex_user_password' password above to something different.

### Update Segex configuration file
Update `cgi-bin/segex.conf` file with the database, user, and password
information specified in the previous step.


### Load table definitions and data
To set up from scratch (with empty tables):

	cat sql/table_defs.sql | mysql segex -u root -p

To load tables plus data from backup:

	# Restore from backup
	gunzip -c segex.2012.05.07.sql.gz | mysql segex -u root -p

Note that you can use the converse of this command to backup a database. In the
example below, the `--routines` option is necessary because otherwise the
`mysqldump` command will not back up stored MySQL procedures and functions.

	# Create database backup
	mysqldump --routines segex -u root -p | gzip -c > segex.`date "+%Y-%m-%d"`.sql.gz


# 2. Mac OS X

## 2.1. Software Install (Mac OS X)

### Install dependencies. 
You need to have a C compiler installed (GCC comes with Xcode) and configured.
To upgrade your `cpan` executable and install/upgrade all of the required
packages:

	sudo /usr/bin/cpan Bundle::CPAN

	sudo /usr/bin/cpan Apache::Session::MySQL CGI::Carp CGI::Cookie \
	  Config::General DBD::mysql DBI Data::Dumper Data::UUID Digest::SHA1 \
	  Email::Address Exception::Class Exception::Class::DBI Hash::Merge JSON \
	  JSON::XS Lingua::EN::Inflect List::Util Mail::Send Math::BigFloat Math::BigInt \
	  Readonly Scalar::Util Storable Text::Autoformat Text::CSV Text::CSV_XS \
	  Tie::IxHash URI::Escape

Repeating the second command will help you confirm whether all of the required
Perl packages were installed successfully.

Note: If you are running Mac OS X 10.6 and have Xcode 4 installed, you no longer
have PPC assembler required to build CPAN packages. To work around this, you can
either (a) go to the corresponding subdirectory in `~/.cpan/build`, remove all
references to PPC architecture (e.g. `-arch ppc`) and reinstall package with
`sudo make` and `sudo make install`. To ensure CPAN can see your module, type
`install My::Module` in the CPAN shell and press <Enter>. You should see a
message, "My::Module is up to date (vx.xx)".  Alternatively (b), create the
following symlinks:

	sudo ln -s \
	/Developer/Platforms/iPhoneOS.platform/Developer/usr/libexec/gcc/darwin/ppc \
	/Developer/usr/libexec/gcc/darwin

	sudo ln -s \
	/Developer/Platforms/iPhoneOS.platform/Developer/usr/libexec/gcc/darwin/ppc \
	/usr/libexec/gcc/darwin


### Set up mailer
The Mail::Send Perl module can use either Sendmail or Postfix. The
current version of Segex relies on a default mailer, which can be either
Sendmail or Postfix depending on the system. On my Mac OS X Snow Leopard, the
default mailer is Postfix.

#### GMAIL EMAIL RELAY USING POSTFIX ON MAC OS X 
(Adapted with some changes after: http://www.riverturn.com/blog/?p=239)

##### 1. Create the Simple Authentication and Security Layer (SASL) password file.

	sudo vi /etc/postfix/sasl_passwd

Enter the following and save the file:

	smtp.gmail.com:587 your_name@gmail.com:your_password

##### 2. Create a Postfix lookup table for SASL.

	sudo postmap /etc/postfix/sasl_passwd

This creates a binary file called `/etc/postfix/sasl_passwd.db`. When done, you
can delete the `/etc/postfix/sasl_passwd` created in the previous step, to
prevent the plain-text password from being discovered by an attacker (Postfix
will use the `.db` file from now on):

	sudo rm /etc/postfix/sasl_passwd

Also, there is no need for anyone but root to have read access to the database:

	sudo chmod 600 /etc/postfix/sasl_passwd.db

##### 3. Configure Postfix

	sudo vi /etc/postfix/main.cf

By default, everything is commented out. You can just append the following to
the end of file and then save it:

	# Minimum Postfix-specific configurations.
	mydomain_fallback = localhost
	mail_owner = _postfix
	setgid_group = _postdrop
	relayhost=smtp.gmail.com:587

	# Enable SASL authentication in the Postfix SMTP client.
	smtp_sasl_auth_enable=yes
	smtp_sasl_password_maps=hash:/etc/postfix/sasl_passwd
	smtp_sasl_security_options=

	# Enable Transport Layer Security (TLS), i.e. SSL.
	smtp_use_tls=yes
	smtp_tls_security_level=encrypt
	tls_random_source=dev:/dev/urandom

##### 4. Test that everything is OK
Run `sudo postfix start` or, if the process is already running, run `sudo
postfix reload`. If you need to view mail queue, type `mailq` in the terminal.
To clear the mail queue, run `sudo postsuper -d ALL`.


### Copy files
If you choose to create soft links instead, add `FollowSymLinks` directive to
the Apache configuration file (either local `.htaccess` or the top-level
`httpd.conf` depending on your setup) for both CGI_ROOT and DOCUMENTS_ROOT
directories. Note: this assumes you have downloaded [YUI
2](http://developer.yahoo.com/yui/2/) to `~/tarballs/yui.tgz`.

	# CGI_ROOT

	# /cgi-bin/segex
	cd /Library/WebServer/CGI-Executables
	sudo cp -R ~/segex/cgi-bin segex
	sudo cp ~/segex/segex.conf.sample segex/segex.conf

	# DOCUMENTS_ROOT

	# /yui
	cd /Library/WebServer/Documents
	tar xvzf ~/tarballs/yui.tgz .

	# /segex/
	mkdir segex
	cd segex

	# /segex/css
	sudo cp -R ~/segex/css .

	# /segex/images
	sudo cp -R ~/segex/images .

	# /segex/js
	sudo cp -R ~/segex/js .


### Change Segex configuration file
In the configuration file (located at `cgi-bin/segex.conf`), check that path to
default mailer program (sendmail, postfix, etc) is set correctly. On Mac OS X,
this path is /usr/sbin.

	mailer_path = "/usr/sbin"

Set up a log file where Segex error messages would go to. The default path to
the log file is set in the following line:

	debug_log_path = "/var/www/error_log/segex_log"

Change that path if necessary and create the log file and set up appropriate
permissions to let Apache write to the file:

	cd /var/www/error_log/
	sudo touch segex_log
	sudo chown www:wheel segex_log

If you do not wish to redirect warnings and error messages, comment out the line
which begins with `debug_log_path`.

For production version, change values for `debug_errors_to_browser` and
`debug_caller_info` to `"no"`. This is important because Segex error messages
may contain sensitive information such as user names, and you do not want
everyone to see them.


### Configure web server
If `AllowOverride` is set in your main Apache configuration file (on my Mac it
is `/etc/apache2/httpd.conf`), you will have to modify `.htaccess` file in
`cgi-bin/` directory to reflect the correct URI path to `index.cgi`. This is
because the `.htaccess` file included in Segex distribution enables URI
rewriting, and without verifying that the path it uses is correct, URIs may be
rewritten incorrectly:

Here is example of `AllowOverride` setting in httpd.conf that enables overrides:

	<Directory "/Library/WebServer/CGI-Executables">
	   AllowOverride Options FileInfo
	   ...

Here is the line in `cgi-bin/.htaccess` that may need to be changed (for
example, if you call your segex executable directory "segex2", you would have to
change "segex" to "segex2" below:

	RewriteRule ^$ /cgi-bin/segex/index.cgi


## Database setup (MySQL) on Mac OS X

### Allow searches on three-letter words
[Optional] To allow for full-text searches on three-letter words and acronyms
such as DNA, RNA, etc., copy file called `my-huge.cnf` from 
`/usr/local/mysql/support-files/` into `/etc/`, renaming it to `my.cnf`:

	sudo cp /usr/local/mysql/support-files/my-huge.cnf /etc/my.cnf

Next, add the following line(s) under section called `[mysqld]` to the newly
created `my.cnf` file:

	[mysqld]
	# Allow full-text indexes on three-letter words such as DNA, RNA, etc.
	ft_min_word_len=3

Next, restart MySQL server via System Preferences.


### Create empty database and corresponding user account
Note: in the default MySQL installation, the root password is empty (simply
press enter to proceed).

	mysql -u root -p
	> CREATE DATABASE segex;
	> CREATE USER 'segex_user'@'localhost' IDENTIFIED BY 'segex_user_password';
	> GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE, CREATE TEMPORARY TABLES
	  ON segex.* TO 'segex_user'@'localhost';

Do not forget to change segex_user_password to something different.

### Update Segex configuration file
Update cgi-bin/segex.conf file with correct database, user, and password
info from the previous step.


### Load table definitions and data
To set up from scratch (with empty tables):

	cat sql/table_defs.sql | mysql segex -u root -p

To load tables plus data from backup:

	# Restore from backup
	gunzip -c segex.sql.gz | mysql segex -u root -p

Note that you can use the converse of this command to backup a database. In the
example below, the `--routines` option is necessary because otherwise mysqldump
command will not back up stored MySQL procedures and functions.

	# Create database backup
	mysqldump --routines segex -u root -p | gzip -c > segex.`date "+%Y-%m-%d"`.sql.gz


# APPENDIX A: Cloning Segex from GitHub repository

## 1. Download and install git
Download a git package using your favorite package manager or compile it from
source, sign up with [GitHub.com](http://github.com/), then follow [the GitHub
instructions](http://help.github.com/linux-set-up-git/) to register your SSH
keys with GitHub:

## 2. Clone Segex from GitHub repository
Once done with installing git, simply clone the GitHub repository using the
following command (this will create a directory called "segex"):

	git clone git@github.com:escherba/segex.git

You can then cd to the newly created directory and switch between branches
(currently there are two branches: "master" and "develop"):

	cd segex/
	git checkout develop
	git checkout master

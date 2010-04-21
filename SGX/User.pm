=head1 NAME

SGX::User

=head1 SYNOPSIS

  use SGX::User;

  # create an instance:
  # -   $dbh must be an active database handle
  # -   3600 is 60 * 60 s = 1 hour (session time to live)
  # -   check_ip determines whether user IP is verified
  # -   cookie_name can be anything
  #
  my $s = SGX::User -> new (-handle          =>$dbh, 
                       -expire_in       =>3600,
                       -check_ip        =>1,
                       -cookie_name     =>'chocolate_chip');

  # restore previous session if it exists
  $s->restore;

  # delete previous session, active session, or both if both exist --
  # useful for user logout for example
  $s->destroy;

  $s->authenticate($username, $password, \$error_string);

  # $login_uri must be in this form: /cgi-bin/my/path/index.cgi?a=login
  $s->reset_password($username, $project_name, $login_uri, \$error_string);

  $s->commit;	# necessary to make a cookie. Also flushes the session data

  # You can create several instances of this class at the same time. The 
  # @SGX::Cookie::cookies array will contain the cookies created by all instances
  # of the SGX::User or SGX::Cookie classes. If the array reference is sent to CGI::header, for 
  # example, as many cookies will be created as there are members in the array.
  #
  # To send a cookie to the user:
  $q = new CGI;
  print $q->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);

  # more code ...

  # is_authorized('admin') checks whether the session user has the credential 'admin'
  if ($s->is_authorized('admin')) {
          # do admin stuff
  } else {
          print 'have to be logged in!';
  }

=head1 DESCRIPTION

This is mainly an interface to the Apache::Session module with
focus on user management.

The table `sessions' is created as follows:
  CREATE TABLE sessions (
    id CHAR(32) NOT NULL UNIQUE,
    a_session TEXT NOT NULL
  );

The table `users' is created as follows:
  CREATE TABLE `users` (
    `uid` int(10) unsigned NOT NULL auto_increment,
    `uname` varchar(60) NOT NULL,
    `pwd` char(40) NOT NULL,
    `email` varchar(60) NOT NULL,
    `full_name` varchar(100) NOT NULL,
    `address` varchar(200) default NULL,
    `phone` varchar(60) default NULL,
    `level` enum('unauth','user','admin') NOT NULL,
    `email_confirmed` tinyint(1) default '0',
    PRIMARY KEY  (`uid`),
    UNIQUE KEY `uname` (`uname`)
  ) ENGINE=InnoDB

=head1 AUTHORS

Written by Eugene Scherba <escherba@gmail.com>

=head1 SEE ALSO

http://search.cpan.org/~chorny/Apache-Session-1.88/Session.pm
http://search.cpan.org/dist/perl/pod/perlmodstyle.pod

=head1 COPYRIGHT

Copyright (c) 2009 Eugene Scherba

=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::User;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.09';
$VERSION = eval $VERSION;

use base qw/SGX::Cookie/;
use Digest::SHA1 qw/sha1_hex/;
use Mail::Send;
use SGX::Debug;
use SGX::Session;	# for email confirmation

# Variables declared as "our" within a class (package) scope will be shared between
# all instances of the class *and* can be addressed from the outside like so:
#
#   my $var = $PackageName::var;
#   my $array_reference = \@PackageName::array;
#

sub authenticate {
	# Queries the `users' table in the database for matching username and password hash.
	# Passwords are not stored in the database directly; instead, an SHA1 hash is being used.
	# SHA1 gives relatively decent level of security, but it is possible to crack it given enough
	# computing resources. NSA does not recommend this hash since 2005 when it was first cracked.
	#
	my ($self, $username, $password, $error) = @_;

        if (!defined($username) || $username eq '') {
                $$error = 'No username specified';  
                return 0;
        }
        if (!defined($password) || $password eq '') {
                $$error = 'No password specified';  
                return 0;
        }

	$password = sha1_hex($password);
	my $sth = $self->{dbh}->prepare('select level from users where uname=? and pwd=?')
		or die $self->{dbh}->errstr;
	my $rowcount = $sth->execute($username, $password) or die $self->{dbh}->errstr;

	if ($rowcount == 1) {
		# user found in the database
		my $level = $sth->fetchrow_array;
		$sth->finish;

		# get a new session handle
		$self->fresh;
		# 1. save user info into the session object
		$self->{object}->{username} = $username;
		$self->{object}->{user_level} = $level;
		# 2. copy user info to class variables
		$self->{data}->{username} = $username;
		$self->{data}->{user_level} = $level;
		# flush the session and prepare the cookie
		#$self->restore;

		return 1;
	} else {
		# user not found in the database
		$sth->finish;
		$$error = 'Login incorrect';
		return 0;
	}
}
sub reset_password {
	# password is reset and the new password is emailed to the
	# (previously validated) email address stored for the
	# corresponding username.
	# $login_uri is the full URI of the login script plus the command to show the form
	# to change a password
	my ($self, $username, $project_name, $login_uri, $error) = @_;

	if (!defined($username) || $username eq '') {
		$$error = 'No username specified';
		return 0;
	}

	my $sth = $self->{dbh}->prepare('select full_name, email from users where uname=? and email_confirmed=1')
		or die $self->{dbh}->errstr;
	my $rowcount = $sth->execute($username)
		or die $self->{dbh}->errstr;

	if ($rowcount == 1) {
		# user found in the database
		my $u = $sth->fetchrow_hashref;
		$sth->finish;

		# generate a 40-character string using hash on user IP and rand() function
		my $new_pwd = sha1_hex($ENV{REMOTE_ADDR} . rand);

		# email the password
		my $msg = Mail::Send->new(Subject=>"Your New $project_name Password", To=>$u->{email});
		$msg->add('From',('NOREPLY'));
		my $fh = $msg->open;
		print $fh 'Hi '.$u->{full_name}.",

This is your new $project_name password:

$new_pwd

Please copy the above password in full and follow the link below to login to $project_name and to change this password to one of your preference:

$login_uri

If you do not think you have requested a new password to be emailed to you, please notify the $project_name team.

- $project_name team";
		$fh->close or die 'Could not send email';

		# update the database
		$new_pwd = sha1_hex($new_pwd);
		my $rows_affected = $self->{dbh}->do(sprintf(
			'update users set pwd=%s where uname=%s', 
			$self->{dbh}->quote($new_pwd), 
			$self->{dbh}->quote($username))
		)
			or die $self->{dbh}->errstr;
		assert($rows_affected == 1);
		#if ($rows_affected == 1) {
		#	$self->{dbh}->commit or die $self->{dbh}->errstr;
		#} else {
		#	$self->{dbh}->rollback or die $self->{dbh}->errstr;
		#}

		return 1;
	} else {
		# user not found in the database
		$sth->finish;
		$$error = "The specified username does not exist in the database or the corresponding email address has not been verified";
		return 0;
	}
}
sub change_password {
	my ($self, $old_password, $new_password1, $new_password2, $error) = @_;

        if (!defined($old_password) || $old_password eq '') {
                $$error = 'Old password not specified';
                return 0;
        }
        if (!defined($new_password1) || $new_password1 eq '') {
                $$error = 'New password not specified';
                return 0;
        }
        if (!defined($new_password2) || $new_password2 eq '') {
                $$error = 'New password not confirmed';
                return 0;
        }
        if ($new_password1 ne $new_password2) {
                $$error = 'New password and its confirmation do not match';
                return 0;
        }
        if ($new_password1 eq $old_password) {
                $$error = 'The new and the old passwords you entered are the same.';
                return 0;
        }
	$new_password1 = sha1_hex($new_password1);
	$old_password = sha1_hex($old_password);
	my $username = $self->{data}->{username};
	assert($username);

	my $rows_affected = $self->{dbh}->do(sprintf(
		'update users set pwd=%s where uname=%s and pwd=%s',
		$self->{dbh}->quote($new_password1),
		$self->{dbh}->quote($username),
		$self->{dbh}->quote($old_password))
	)
		or die $self->{dbh}->errstr;

	if ($rows_affected == 1) {
		return 1;
	} else {
		if ($rows_affected == 0) {
			$$error = 'The password was not changed. Please make sure you entered your old password correctly.';
		} else {
			assert(undef);	# should never happen
		}
		return 0;
	}
}
sub change_email {
        my ($self, $password, $email1, $email2, $project_name, $login_uri, $error) = @_;

        if (!defined($password) || $password eq '') {
                $$error = 'Password not specified';
                return 0;
        }
        if (!defined($email1) || $email1 eq '') {
                $$error = 'Email not specified';
                return 0;
        }
        if (!defined($email2) || $email2 eq '') {
                $$error = 'Email not confirmed';
                return 0;
        }
        if ($email1 ne $email2) {
                $$error = 'Email and its confirmation do not match';
                return 0;
        }
        $password = sha1_hex($password);
        my $username = $self->{data}->{username};
        assert($username);

        my $rows_affected = $self->{dbh}->do(sprintf(
		'update users set email=%s, email_confirmed=0 where uname=%s and pwd=%s and email!=%s',
		$self->{dbh}->quote($email1),
		$self->{dbh}->quote($password),
		$self->{dbh}->quote($email1))
	)
                or die $self->{dbh}->errstr;

        if ($rows_affected == 1) {
	        $self->send_verify_email($project_name, $username, $username, $email1, $login_uri);
                return 1;
        } else {
                if ($rows_affected == 0) {
                        $$error = 'The email was not changed. Please make sure you entered your password correctly and that your new email address is different from your old one.';
                } else {
                        assert(undef);  # should never happen
                }
                return 0;
        }
}
sub register_user {
	my ($self, $username, $password1, $password2, $email1, $email2, $full_name, $address, $phone, $project_name, $login_uri, $error) = @_;
# For a user to be registered, he/she must be approved by an admin.
# Valid email address is not required, however when an email *is*
# entered, it must be verified, otherwise the user will not be
# able to reset a password without admin help.
#
# If the user enters or changes an email address, a validation message is sent to
# this address with a link and a special code that is valid only for
# 48 hours. When the user clicks on this link, he/she is presented with
# a login page. After the user enters the name and the password,
# the email validation is complete.
#
# To accomplish this, the "secret code" is embedded in the URL being emailed
# to the user. At the same time, a new session is opened (so that the "secret code"
# is actually the session_id) with expiration time 48 * 3600. the url looks like 
#
# http://mydomain/my/path/index.cgi?a=verifyEmail&code=343ytgsr468das
#
# On being sent a verifyEmail command, index.cgi checks the logged-in status
# of a user (which is independent from is_authorized() because the user may not have
# yet obtained authorization from the site admin). // NOTE: write a method is_loggedIn() //
# If a user is logged in, username is compared with the username from the 48-hr session.
# This is done via opening two session objects at once.
#
	if (!defined($username) || $username eq '') {
                $$error = 'Username not specified';
                return 0;
        }
	if (!defined($password1) || $password1 eq '') {
                $$error = 'Password not specified';
                return 0;
        }
        if (!defined($password2) || $password2 eq '') {
                $$error = 'Password not confirmed';
                return 0;
        }
        if ($password1 ne $password2) {
                $$error = 'Password and its confirmation do not match';
                return 0;
        }
        if (!defined($email1) || $email1 eq '') {
                $$error = 'Email not specified';
                return 0;
        }
        if (!defined($email2) || $email2 eq '') {
                $$error = 'Email not confirmed';
                return 0;
        }
        if ($email1 ne $email2) {
                $$error = 'Email and its confirmation do not match';
                return 0;
        }
	if (!defined($full_name) || $full_name eq '') {
                $$error = 'Full name not specified';
                return 0;
        }
	my $sth = $self->{dbh}->prepare('select count(*) from users where uname=?')
		or die $self->{dbh}->errstr;
	my $rowcount = $sth->execute($username) or die $self->{dbh}->errstr;
	assert($rowcount == 1);
	my $user_found = $sth->fetchrow_array;
	$sth->finish;
	if ($user_found) {
		$$error = "The user $username already exists in the database";
		return 0;
	}

	$password1 = sha1_hex($password1);

	my $rows_affected = $self->{dbh}->do(sprintf(
		'insert into users set uname=%s, pwd=%s, email=%s, full_name=%s, address=%s, phone=%s',
		$self->{dbh}->quote($username),
		$self->{dbh}->quote($password1),
		$self->{dbh}->quote($email1),
		$self->{dbh}->quote($full_name),
		$self->{dbh}->quote($address),
		$self->{dbh}->quote($phone))
	)
		or die $self->{dbh}->errstr;

	assert($rows_affected == 1);

	$self->send_verify_email($project_name, $full_name, $username, $email1, $login_uri);
	return 1;
}
sub send_verify_email {
	my ($self, $project_name, $full_name, $username, $email, $login_uri) = @_;
        my $s = SGX::Session->new(-handle	=>$self->{dbh},
				  -expire_in	=>3600*48,
				  -check_ip	=>0,
				  -id		=>undef);
        $s->open;
        $s->{object}->{username} = $username;   # make the session object store the username
        if ($s->commit) {

                # email the confirmation link
                my $msg = Mail::Send->new(Subject=>"Please confirm your email address with $project_name", To=>$email);
                $msg->add('From',('NOREPLY'));
                my $fh = $msg->open;
                print $fh 'Hi '.$full_name.",

You have recently applied for user access to $project_name. Please click on the link below to confirm your email address with $project_name. This is will be the email address $project_name administrators will use to contact you.

$login_uri&sid=".$s->{data}->{_session_id}."

If you have never heard of $project_name, please ignore this message or notify the $project_name team if you receive it repeatedly.

- $project_name team";
                $fh->close or die 'Could not send email';
        }
}
sub verify_email {
	my ($self, $username) = @_;
	if ($self->{data}->{username} ne $username) {
		return 0;
	}
	my $rows_affected = $self->{dbh}->do(sprintf(
		'update users set email_confirmed=1 WHERE uname=%s',
		$self->{dbh}->quote($username))
	)
		or die $self->{dbh}->errstr;

	assert($rows_affected == 1);
	return 1;
}
sub is_authorized {
	# checks whether the currently logged-in user has the required credentials
	# returns 1 if yes, 0 if no
	#
        my ($self, $req_user_level) = @_;
	if (defined($self->{data}->{user_level})) {
		if ($req_user_level eq 'admin') {
			if ($self->{data}->{user_level} eq 'admin')
			{ return 1; }
		} elsif ($req_user_level eq 'user') {
			if ($self->{data}->{user_level} eq 'admin' ||
			    $self->{data}->{user_level} eq 'user')
			{ return 1; }
		} elsif ($req_user_level eq 'unauth') {
			if ($self->{data}->{user_level} eq 'admin' ||
 			    $self->{data}->{user_level} eq 'user' ||
			    $self->{data}->{user_level} eq 'unauth')
			{ return 1; }
		}
	}
        return 0;
}
1; # for require

__END__

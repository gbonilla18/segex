
=head1 NAME

SGX::User

=head1 SYNOPSIS

To create an instance:
(1) $dbh must be an active database handle
(2) 3600 is 60 * 60 s = 1 hour (session time to live)
(3) check_ip determines whether user IP is verified
(4) cookie_name can be anything

    use SGX::User;
    my $s = SGX::User -> new (
        -handle      => $dbh, 
        -expire_in   => 3600,
        -check_ip    => 1,
        -cookie_name => 'chocolate_chip'
    );

To restore previous session if it exists
    $s->restore;

To delete previous session, active session, or both if both exist -- useful when user
logs out, for example:

    $s->destroy;

    $s->authenticate($username, $password, \$error_string);

Note: $login_uri must be in this form: /cgi-bin/my/path/index.cgi?a=login

    $s->reset_password($username, $project_name, $login_uri, \$error_string);

To make a cookie and flush session data:
    $s->commit;

You can create several instances of this class at the same time. The 
@SGX::Cookie::cookies array will contain the cookies created by all instances of 
the SGX::User or SGX::Cookie classes. If the array reference is sent to CGI::header,
for example, as many cookies will be created as there are members in the array.

To send a cookie to the user:

    $q = new CGI;
    print $q->header(
        -type=>'text/html',
        -cookie=>\@SGX::Cookie::cookies
    );

Note: is_authorized('admin') checks whether the session user has the credential 'admin'

    if ($s->is_authorized('admin')) {
        # do admin stuff...
    } else {
        print 'have to be logged in!';
    }

=head1 DESCRIPTION

This is mainly an interface to the Apache::Session module with focus on user management.

For a user to be registered, he/she must be approved by an admin.  Valid email address 
is not required, however when an email *is* entered, it must be verified, otherwise the 
user will not be able to reset a password without admin help.

If the user enters or changes an email address, a validation message is sent to this 
address with a link and a special code that is valid only for 48 hours. When the user 
clicks on this link, he/she is presented with a login page. After the user enters the 
name and the password, the email validation is complete.

To accomplish this, the "secret code" is embedded in the URL being emailed to the user. 
At the same time, a new session is opened (so that the "secret code" is actually the 
session_id) with expiration time 48 * 3600. The url looks like:

http://mydomain/my/path/index.cgi?a=verifyEmail&code=343ytgsr468das

On being sent a verifyEmail command, index.cgi checks the logged-in status of a user 
(which is independent from is_authorized() because the user may not have yet obtained 
authorization from the site admin). If a user is logged in, username is compared with 
the username from the 48-hr session.  This is done via opening two session objects at once.

TODO: write a method is_logged_in()

Passwords are not stored in the database directly; instead, an SHA1 hash is being used.
SHA1 gives relatively decent level of security, but it is possible to crack it given 
enough computing resources. The NSA does not recommend this hash since 2005 when it was 
first cracked.

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

use CGI::Carp qw/croak/;

use vars qw($VERSION);

$VERSION = '0.10';

use base qw/SGX::Cookie/;
use Digest::SHA1 qw/sha1_hex/;
use Mail::Send;
use SGX::Debug;
use SGX::Session;    # for email confirmation

# Variables declared as "our" within a class (package) scope will be shared between
# all instances of the class *and* can be addressed from the outside like so:
#
#   my $var = $PackageName::var;
#   my $array_reference = \@PackageName::array;
#

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  authenticate
#   PARAMETERS:  $self - reference to object instance
#                $username - user name string
#                $password - password string
#                $error - reference to error string
#      RETURNS:  1 on success, 0 on failure
#  DESCRIPTION:  Queries the `users' table in the database for matching username and
#                password hash
#       THROWS:  DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub authenticate {

    my ( $self, $username, $password, $error ) = @_;

    if ( !defined($username) || $username eq '' ) {
        $$error = 'No username specified';
        return 0;
    }
    if ( !defined($password) || $password eq '' ) {
        $$error = 'No password specified';
        return 0;
    }

    $password = sha1_hex($password);
    my $sth =
      $self->{dbh}->prepare('select level from users where uname=? and pwd=?')
      or croak $self->{dbh}->errstr;
    my $rowcount = $sth->execute( $username, $password )
      or croak $self->{dbh}->errstr;

    if ( $rowcount == 1 ) {

        # user found in the database
        my $level = $sth->fetchrow_array;
        $sth->finish;

        # get a new session handle
        $self->fresh;

        # 1. save user info into the session object
        $self->{object}->{username}   = $username;
        $self->{object}->{user_level} = $level;

        # 2. copy user info to class variables
        $self->{data}->{username}   = $username;
        $self->{data}->{user_level} = $level;

        # flush the session and prepare the cookie
        #$self->restore;

        return 1;
    }
    else {

        # user not found in the database
        $sth->finish;
        $$error = 'Login incorrect';
        return 0;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  reset_password
#   PARAMETERS:  $self - reference to object instance
#                $username
#                $project_name
#                $login_uri - the full URI of the login script plus the command to show
#                the formi to change a password
#                $error - reference to error string
#      RETURNS:  1 on success, 0 on failure
#  DESCRIPTION:  Issues a new password and emails it to the user's email address. The
#                email address must be marked as "confirmed" in the "users" table in the
#                dataase.
#       THROWS:  DBI::errstr, Mail::Send::close failure
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub reset_password {

    my ( $self, $username, $project_name, $login_uri, $error ) = @_;

    if ( !defined($username) || $username eq '' ) {
        $$error = 'No username specified';
        return 0;
    }

    my $sth =
      $self->{dbh}->prepare(
        'select full_name, email from users where uname=? and email_confirmed=1'
      ) or croak $self->{dbh}->errstr;
    my $rowcount = $sth->execute($username)
      or croak $self->{dbh}->errstr;

    if ( $rowcount == 1 ) {

        # user found in the database
        my $u = $sth->fetchrow_hashref;
        $sth->finish;

      # generate a 40-character string using hash on user IP and rand() function
        my $new_pwd = sha1_hex( $ENV{REMOTE_ADDR} . rand );

        # email the password
        my $msg = Mail::Send->new(
            Subject => "Your New $project_name Password",
            To      => $u->{email}
        );
        $msg->add( 'From', ('NOREPLY') );
        my $fh = $msg->open;
        my $user_full_name = $u->{full_name};
        print $fh <<"END_RESET_PWD_MSG";
Hi $user_full_name,

This is your new $project_name password:

$new_pwd

Please copy the above password in full and follow the link below to login to $project_name and to change this password to one of your preference:

$login_uri

If you do not think you have requested a new password to be emailed to you, please notify the $project_name administrator.

- $project_name automatic mailer

END_RESET_PWD_MSG
        $fh->close or croak 'Could not send email';

        # update the database
        $new_pwd = sha1_hex($new_pwd);
        my $rows_affected =
          $self->{dbh}->do( 'update users set pwd=? where uname=?',
            undef, $new_pwd, $username )
          or croak $self->{dbh}->errstr;

        assert( $rows_affected == 1 );

        #if ($rows_affected == 1) {
        #    $self->{dbh}->commit or croak $self->{dbh}->errstr;
        #} else {
        #    $self->{dbh}->rollback or croak $self->{dbh}->errstr;
        #}

        return 1;
    }
    else {

        # user not found in the database
        $sth->finish;
        $$error =
"The specified username does not exist in the database or the corresponding email address has not been verified";
        return 0;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  reset_password_text
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub reset_password_text {
    return <<"END_reset_password_text";
A new password has been emailed to you. Once you receive the email message, you will be
able to change the password sent to you by following the link in the email text.
END_reset_password_text
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  change_password
#   PARAMETERS:  ????
#      RETURNS:  1 on success, 0 on failure
#  DESCRIPTION:  
#       THROWS:  DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub change_password {
    my ( $self, $old_password, $new_password1, $new_password2, $error ) = @_;

    if ( !defined($old_password) || $old_password eq '' ) {
        $$error = 'Old password not specified';
        return 0;
    }
    if ( !defined($new_password1) || $new_password1 eq '' ) {
        $$error = 'New password not specified';
        return 0;
    }
    if ( !defined($new_password2) || $new_password2 eq '' ) {
        $$error = 'New password not confirmed';
        return 0;
    }
    if ( $new_password1 ne $new_password2 ) {
        $$error = 'New password and its confirmation do not match';
        return 0;
    }
    if ( $new_password1 eq $old_password ) {
        $$error = 'The new and the old passwords you entered are the same.';
        return 0;
    }
    $new_password1 = sha1_hex($new_password1);
    $old_password  = sha1_hex($old_password);
    my $username = $self->{data}->{username};
    assert($username);

    my $rows_affected =
      $self->{dbh}->do( 'update users set pwd=? where uname=? and pwd=?',
        undef, $new_password1, $username, $old_password )
      or croak $self->{dbh}->errstr;

    if ( $rows_affected == 1 ) {
        return 1;
    }
    else {
        if ( $rows_affected == 0 ) {
            $$error =
'The password was not changed. Please make sure you entered your old password correctly.';
        }
        else {
            assert(undef);    # should never happen
        }
        return 0;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  change_email
#   PARAMETERS:  ????
#      RETURNS:  1 on success, 0 on failure
#  DESCRIPTION:  
#       THROWS:  DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub change_email {
    my ( $self, $password, $email1, $email2, $project_name, $login_uri, $error )
      = @_;

    if ( !defined($password) || $password eq '' ) {
        $$error = 'Password not specified';
        return 0;
    }
    if ( !defined($email1) || $email1 eq '' ) {
        $$error = 'Email not specified';
        return 0;
    }
    if ( !defined($email2) || $email2 eq '' ) {
        $$error = 'Email not confirmed';
        return 0;
    }
    if ( $email1 ne $email2 ) {
        $$error = 'Email and its confirmation do not match';
        return 0;
    }
    $password = sha1_hex($password);
    my $username = $self->{data}->{username};
    assert($username);

    my $rows_affected = $self->{dbh}->do(
'update users set email=?, email_confirmed=0 where uname=? and pwd=? and email!=?',
        undef, $email1, $password, $email1
    ) or croak $self->{dbh}->errstr;

    if ( $rows_affected == 1 ) {
        $self->send_verify_email( $project_name, $username, $username, $email1,
            $login_uri );
        return 1;
    } 
    elsif ( $rows_affected == 0 ) {
            $$error =
'The email was not changed. Please make sure you entered your password correctly and that your new email address is different from your old one.';
            return 0;
    } 
    else {
        # should never happen
        croak 'Internal error occurred';
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  change_email_text
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub change_email_text {
    return <<"END_change_email_text";
You have changed your email address. Please confirm your new email address by clicking
on the link in the message has been sent to the address you provided.
END_change_email_text
}
#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  register_user
#   PARAMETERS:  ????
#      RETURNS:  1 on success, 0 on failure
#  DESCRIPTION:  
#       THROWS:  DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub register_user {
    my (
        $self,   $username,     $password1, $password2,
        $email1, $email2,       $full_name, $address,
        $phone,  $project_name, $login_uri, $error
    ) = @_;

    if ( !defined($username) || $username eq '' ) {
        $$error = 'Username not specified';
        return 0;
    }
    if ( !defined($password1) || $password1 eq '' ) {
        $$error = 'Password not specified';
        return 0;
    }
    if ( !defined($password2) || $password2 eq '' ) {
        $$error = 'Password not confirmed';
        return 0;
    }
    if ( $password1 ne $password2 ) {
        $$error = 'Password and its confirmation do not match';
        return 0;
    }
    if ( !defined($email1) || $email1 eq '' ) {
        $$error = 'Email not specified';
        return 0;
    }
    if ( !defined($email2) || $email2 eq '' ) {
        $$error = 'Email not confirmed';
        return 0;
    }
    if ( $email1 ne $email2 ) {
        $$error = 'Email and its confirmation do not match';
        return 0;
    }
    if ( !defined($full_name) || $full_name eq '' ) {
        $$error = 'Full name not specified';
        return 0;
    }
    my $sth = $self->{dbh}->prepare('select count(*) from users where uname=?')
      or croak $self->{dbh}->errstr;
    my $rowcount = $sth->execute($username) or croak $self->{dbh}->errstr;
    assert( $rowcount == 1 );
    my $user_found = $sth->fetchrow_array();
    $sth->finish();
    if ($user_found) {
        $$error = "The user $username already exists in the database";
        return 0;
    }

    $password1 = sha1_hex($password1);

    my $rows_affected = $self->{dbh}->do(
'insert into users set uname=?, pwd=?, email=?, full_name=?, address=?, phone=?',
        undef,
        $username,
        $password1,
        $email1,
        $full_name,
        $address,
        $phone
    ) or croak $self->{dbh}->errstr;

    assert( $rows_affected == 1 );
    $self->send_verify_email( $project_name, $full_name, $username, $email1,
        $login_uri );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  register_user_text
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub register_user_text {
    return <<"END_register_user_text";
An email message has been sent to the email address you have entered. You should confirm
your email address by clicking on a link included in the email message. Another email 
message has been sent to the administrator(s) of this site. Once your request for access 
is approved, you can start browsing the content hosted on this site.
END_register_user_text
}
#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  send_verify_email
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  DBI::errstr, Mail::Send::close failure
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub send_verify_email {
    my ( $self, $project_name, $full_name, $username, $email, $login_uri ) = @_;
    my $s = SGX::Session->new(
        -handle    => $self->{dbh},
        -expire_in => 3600 * 48,
        -check_ip  => 0,
        -id        => undef
    );
    $s->commence();
    # make the session object store the username
    $s->{object}->{username} = $username;    
    if ( $s->commit() ) {

        # email the confirmation link
        my $msg = Mail::Send->new(
            Subject => "Please confirm your email address with $project_name",
            To      => $email
        );
        $msg->add( 'From', ('NOREPLY') );
        my $fh = $msg->open()
            or croak 'Failed to open default mailer';
        my $session_id = $s->{data}->{_session_id};
        print $fh <<"END_CONFIRM_EMAIL_MSG";
Hi $full_name,

You have recently applied for user access to $project_name. Please click on the link below to confirm your email address with $project_name. You may be asked to enter your username and password if you are not currently logged in.

$login_uri&sid=$session_id

If you have never heard of $project_name, please ignore this message or notify the $project_name administrator if you keep receiving it.

- $project_name automatic mailer

END_CONFIRM_EMAIL_MSG
        $fh->close or croak 'Could not send email';
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  verify_email
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub verify_email {
    my ( $self, $username ) = @_;
    if ( $self->{data}->{username} ne $username ) {
        return 0;
    }
    my $rows_affected =
      $self->{dbh}->do( 'update users set email_confirmed=1 WHERE uname=?',
        undef, $username )
      or croak $self->{dbh}->errstr;

    assert( $rows_affected == 1 );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::User
#       METHOD:  is_authorized
#   PARAMETERS:  $self - reference to object instance
#                $req_user_level - required credential level
#      RETURNS:  1 if yes, 0 if no
#  DESCRIPTION:  checks whether the currently logged-in user has the required
#                credentials
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub is_authorized {

    my ( $self, $req_user_level ) = @_;
    if ( defined( $self->{data}->{user_level} ) ) {
        if ( $req_user_level eq 'admin' ) {
            if ( $self->{data}->{user_level} eq 'admin' ) { return 1; }
        }
        elsif ( $req_user_level eq 'user' ) {
            if (   $self->{data}->{user_level} eq 'admin'
                || $self->{data}->{user_level} eq 'user' )
            {
                return 1;
            }
        }
        elsif ( $req_user_level eq 'unauth' ) {
            if (   $self->{data}->{user_level} eq 'admin'
                || $self->{data}->{user_level} eq 'user'
                || $self->{data}->{user_level} eq 'unauth' )
            {
                return 1;
            }
        }
    }
    return 0;
}
1;    # for require

__END__

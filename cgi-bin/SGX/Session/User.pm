
=head1 NAME

SGX::Session::User

=head1 SYNOPSIS

To create an instance:
(1) $dbh must be an active database handle
(2) 3600 is 60 * 60 s = 1 hour (session time to live)
(3) check_ip determines whether user IP is verified
(4) cookie_name can be anything

    use SGX::Session::User;
    my $s = SGX::Session::User->new (
        dbh         => $dbh, 
        expire_in   => 3600,
        check_ip    => 1,
    );

To restore previous session if it exists
    $s->restore;

To delete previous session, active session, or both if both exist -- useful when
user logs out, for example:

    $s->destroy;

    $s->authenticate($username, $password, \$error_string);

Note: $login_uri must be in this form: /cgi-bin/my/path/index.cgi?a=login

    $s->reset_password($username, $project_name, $login_uri, \$error_string);

To make a cookie and flush session data:
    $s->commit;

You can create several instances of this class at the same time. The
@SGX::Session::Cookie::cookies array will contain the cookies created by all
instances of the SGX::Session::User or SGX::Session::Cookie classes. If the
array reference is sent to CGI::header, for example, as many cookies will be
created as there are members in the array.

To send a cookie to the user:

    $q = new CGI;
    print $q->header(
        -type=>'text/html',
        -cookie=>\@SGX::Session::Cookie::cookies
    );

Note: is_authorized('admin') checks whether the session user has the credential
'admin'.

    if ($s->is_authorized('admin')) {
        # do admin stuff...
    } else {
        print 'have to be logged in!';
    }

=head1 DESCRIPTION

This is mainly an interface to the Apache::Session module with focus on user
management.

For a user to be registered, he/she must be approved by an admin.  Valid email
address is not required, however when an email *is* entered, it must be
verified, otherwise the user will not be able to reset a password without admin
help.

If the user enters or changes an email address, a validation message is sent to
this address with a link and a special code that is valid only for 48 hours.
When the user clicks on this link, he/she is presented with a login page. After
the user enters the name and the password, the email validation is complete.

To accomplish this, the "secret code" is embedded in the URL being emailed to
the user.  At the same time, a new session is opened (so that the "secret code"
is actually the session_id) with expiration time 48 * 3600. The url looks like:

http://mydomain/my/path/index.cgi?a=verifyEmail&code=343ytgsr468das

On being sent a verifyEmail command, index.cgi checks the logged-in status of a
user (which is independent from is_authorized() because the user may not have
yet obtained authorization from the site admin). If a user is logged in,
username is compared with the username from the 48-hr session.  This is done via
opening two session objects at once.

Passwords are not stored in the database directly; instead, an SHA1 hash is
being used.  SHA1 gives relatively decent level of security, but it is possible
to crack it given enough computing resources. The NSA does not recommend this
hash since 2005 when it was first cracked.

The table `sessions' is created as follows:

    CREATE TABLE sessions (
        id CHAR(32) NOT NULL UNIQUE,
        a_session TEXT NOT NULL
    ) ENGINE=InnoDB;

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
    ) ENGINE=InnoDB;

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

package SGX::Session::User;

# :TODO:07/31/2011 15:38:04:es: scan this module for error handling mechanisms
# that involve setting $$error dereferenced variable.  Replace all those cases
# with exceptions.
#
use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.11';

use base qw/SGX::Session::Cookie/;

#use Data::Dumper;
use Digest::SHA1 qw/sha1_hex/;
use Mail::Send;
use SGX::Abstract::Exception;
use SGX::Session::Session;    # for email confirmation
use Email::Address;

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  commit
#   PARAMETERS:  ????
#      RETURNS:  1 on success (session data stored in remote database) or 0 on
#                failure
#  DESCRIPTION:  Overrides parent method: calls parent method first, then bakes
#                a permanent cookie on success if needed
#       THROWS:  no exceptions
#     COMMENTS:  Note that, when subclassing, that overridden methods return
#                the same values on same conditions
#     SEE ALSO:  n/a
#===============================================================================
sub commit {
    my $self = shift;
    if ( $self->SUPER::commit() ) {
        return 1 unless $self->{perm_cookie_modified};
        my $username = $self->{session_stash}->{username};
        return unless defined($username);
        $self->add_cookie(
            -name    => sha1_hex($username),
            -value   => $self->{perm_cookie},
            -expires => '+3M'
        );
        return 1;
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  authenticate
#   PARAMETERS:  $self - reference to object instance
#                $username - user name string
#                $password - password string
#                $error - reference to error string
#      RETURNS:  1 on success, 0 on failure
#
#  DESCRIPTION:  Queries the `users' table in the database for matching username
#  and password hash. Stores full user name in session cookie on login.  Full user
#  name is an example of information that is not critical from security
#  standpoint, which means that (a) it can be stored on the client, and that (b)
#  it should be stored on the client (to save space in the database.  In
#  addition to full user name, data such as name of the working project could
#  also be stored in the session cookie. Note that project names are more likely
#  to change than project ids; so it makes more sense to store only the project
#  id in the permanent cookie storage and keep project name in the session
#  cookie.
#
#       THROWS:  DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub authenticate {

    my ( $self, $username, $password, $error ) = @_;

    if ( !defined($username) || $username eq '' ) {
        $$error = 'No username specified';
        return;
    }
    if ( !defined($password) || $password eq '' ) {
        $$error = 'No password specified';
        return;
    }

    my $sth =
      $self->{dbh}
      ->prepare('select level,full_name from users where uname=? and pwd=?');
    my $row_count = $sth->execute( $username, sha1_hex($password) );

    if ( $row_count != 1 ) {

        # :TODO:07/09/2011 23:58:04:es: Consider using
        # SGX::Abstract::Exception::User::Login to send the error message
        #
        # user not found in the database
        $sth->finish;
        $$error = 'Login incorrect';
        return;
    }

    # user found in the database
    my ( $level, $full_name ) = $sth->fetchrow_array;
    $sth->finish;

    # get a new session handle. This will also delete the old session cookie
    $self->destroy();
    $self->start();

    # Login username and user level are sensitive data: store them remotely.
    # Although newer browser support HTTP-only cookies (not visible to
    # Javascript), we do not want the user to be able to "upgrade" his or her
    # account by modifying the user level in the session cookie for example.

    $self->session_store(
        username   => $username,
        user_level => $level
    );

    # Have the username; can read the permanent cookie now. Note: read permanent
    # cookie before setting session cookie fields here: this helps preserve the
    # flow: database -> session -> (session_cookie, perm_cookie), since reading
    # permanent cookie synchronizes everything in it with the session cookie.
    $self->read_perm_cookie( username => $username );

    # Full user name is not sensitive from database perspective and can be
    # stored on the cliend in a can be stored on the client in a session cookie.
    # Note that there is no need to store it in a permanent cookie on the client
    # because the authentication process will involve a database transaction
    # anyway and a full name can be looked up from there.
    $self->session_cookie_store( full_name => $full_name );

    #$self->restore;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  reset_password
#   PARAMETERS:  $self - reference to object instance
#                $username
#                $project_name
#                $login_uri - the full URI of the login script plus the command
#                to show the form to change a password
#                $error - reference to error string
#      RETURNS:  1 on success, 0 on failure
#  DESCRIPTION:  Issues a new password and emails it to the user's email address.
#                The email address must be marked as "confirmed" in the "users"
#                table in the dataase.
#       THROWS:  Exception::Class::DBI, SGX::Abstract::Exception::Internal::Mail
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub reset_password {

    my ( $self, %param ) = @_;

    my ( $username, $project_name, $login_uri, $error ) =
      @param{qw{username project_name login_uri error}};

    if ( !defined($username) || $username eq '' ) {
        $$error = 'No username specified';
        return;
    }

    my $dbh = $self->{dbh};
    my $sth = $dbh->prepare(
        'select full_name, email from users where uname=? and email_confirmed=1'
    );
    my $rows_found = $sth->execute($username);
    if ( $rows_found == 0 ) {

        # user not found in the database
        $sth->finish;
        $$error =
'The user does not exist in the database or user email address has not been verified';
        return;
    }
    elsif ( $rows_found != 1 ) {

        # should never happen
        $sth->finish;
        SGX::Abstract::Exception::Internal::Duplicate->throw( error =>
              "Expected one user record but encountered $rows_found.\n" );
    }

    # single user found in the database
    my ( $user_full_name, $user_email ) = $sth->fetchrow_array;
    $sth->finish;

    # generate a 40-character string using hash on user IP and rand() function
    my $new_pwd = sha1_hex( $ENV{REMOTE_ADDR} . rand );

    #---------------------------------------------------------------------------
    #  email the password
    #---------------------------------------------------------------------------

    my $msg = Mail::Send->new(
        Subject => "Your New $project_name Password",
        To      => $user_email
    );
    $msg->add( 'From', ('NOREPLY') );
    my $fh = $msg->open()
      or SGX::Abstract::Exception::Internal::Mail->throw(
        error => 'Failed to open default mailer' );
    print $fh <<"END_RESET_PWD_MSG";
Hi $user_full_name,

This is your new $project_name password:

$new_pwd

Please copy the above password in full and follow the link below to login to
$project_name and to change this password to one of your preference:

$login_uri

If you do not think you have requested a new password to be emailed to you,
please notify the $project_name administrator.

- $project_name automatic mailer

END_RESET_PWD_MSG
    $fh->close
      or SGX::Abstract::Exception::Internal::Mail->throw(
        error => 'Failed to send email message' );

 # :TODO:07/31/2011 15:18:30:es: consider using commit/rollback transaction here
    my $rows_affected = $dbh->do( 'update users set pwd=? where uname=?',
        undef, sha1_hex($new_pwd), $username );

    if ( $rows_affected != 1 ) {
        SGX::Abstract::Exception::Internal->throw( error =>
"Expected to find one user with login $username but $rows_affected rows were updated\n"
        );
    }

    return 1;

}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
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
A new password has been emailed to you. Once you receive the email message, you
will be able to change the password sent to you by following the link in the
email text.
END_reset_password_text
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  change_password
#   PARAMETERS:  ????
#      RETURNS:  1 on success, 0 on failure
#  DESCRIPTION:
#       THROWS:  DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub change_password {
    my ( $self, %param ) = @_;

    my ( $old_password, $new_password1, $new_password2, $error ) =
      @param{qw{old_password new_password1 new_password2 error}};

    if ( !defined($old_password) || $old_password eq '' ) {
        $$error = 'Old password not specified';
        return;
    }
    if ( !defined($new_password1) || $new_password1 eq '' ) {
        $$error = 'New password not specified';
        return;
    }
    if ( !defined($new_password2) || $new_password2 eq '' ) {
        $$error = 'New password not confirmed';
        return;
    }
    if ( $new_password1 ne $new_password2 ) {
        $$error = 'New password and its confirmation do not match';
        return;
    }
    if ( $new_password1 eq $old_password ) {
        $$error = 'The new and the old passwords you entered are the same.';
        return;
    }
    $new_password1 = sha1_hex($new_password1);
    $old_password  = sha1_hex($old_password);
    my $username = $self->{session_stash}->{username};
    if ( !defined($username) || $username eq '' ) {
        SGX::Abstract::Exception::Internal->throw( error =>
"Expected to see a defined username in session data but none was found\n"
        );
    }

    my $rows_affected =
      $self->{dbh}->do( 'update users set pwd=? where uname=? and pwd=?',
        undef, $new_password1, $username, $old_password );

    if ( $rows_affected == 0 ) {
        $$error =
'The password was not changed. Please try again and make sure you entered your old password correctly.';
    }
    elsif ( $rows_affected > 1 ) {
        SGX::Abstract::Exception::Internal::Duplicate->throw( error =>
              "Expected one user record but encountered $rows_affected.\n" );
    }
    return $rows_affected;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  change_email
#   PARAMETERS:  ????
#      RETURNS:  1 on success, 0 on failure
#  DESCRIPTION:
#       THROWS:  DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub change_email {
    my ( $self, %param ) = @_;

    # extract values from a hash of named arguments and place them into an array
    my ( $password, $email1, $email2, $project_name, $login_uri, $error ) =
      @param{qw{password email1 email2 project_name login_uri error}};

    if ( !defined($password) || $password eq '' ) {
        $$error = 'Password not specified';
        return;
    }
    if ( !defined($email1) || $email1 eq '' ) {
        $$error = 'Email not specified';
        return;
    }
    if ( !defined($email2) || $email2 eq '' ) {
        $$error = 'Email not confirmed';
        return;
    }
    if ( $email1 ne $email2 ) {
        $$error = 'Email and its confirmation do not match';
        return;
    }

    # Parsing email address with Email::Address->parse() has the side effect of
    # untainting user-entered email (applicable when CGI script is run in taint
    # mode with -T switch).
    my ($email_handle) = Email::Address->parse($email1);
    if ( !defined($email_handle) ) {
        $$error = 'Email address provided is not in valid format';
        return;
    }
    my $email_address = $email_handle->address;

    $password = sha1_hex($password);
    my $username = $self->{session_stash}->{username};
    if ( !defined($username) || $username eq '' ) {
        SGX::Abstract::Exception::Internal->throw( error =>
"Expected to see a defined username in session data but none was found\n"
        );
    }

    my $full_name = $self->{session_cookie}->{full_name};

    my $rows_affected = $self->{dbh}->do(
'update users set email=?, email_confirmed=0 where uname=? and pwd=? and email != ?',
        undef, $email_address, $username, $password, $email_address
    );

    if ( $rows_affected == 1 ) {
        $self->send_verify_email(
            project_name => $project_name,
            full_name    => $full_name,
            username     => $username,
            email        => $email_address,
            login_uri    => $login_uri
        );
        return 1;
    }
    elsif ( $rows_affected == 0 ) {
        $$error = <<"END_noEmailChangeMsg";
The email was not changed. Please make sure you entered your password correctly
and that your new email address is different from your old one.
END_noEmailChangeMsg
        return;
    }
    else {

        # should never happen
        SGX::Abstract::Exception::Internal::Duplicate->throw( error =>
              "Expected one user record but encountered $rows_affected.\n" );
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
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
You have changed your email address. An email message has been sent to your new
email address that will ask you to confirm your new address. You will need to
confirm your new email address, which you can do simply by clicking on a link
provided in the message.
END_change_email_text
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  register_user
#   PARAMETERS:  ????
#      RETURNS:  1 on success, 0 on failure
#  DESCRIPTION:
#       THROWS:  DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub register_user {
    my ( $self, %param ) = @_;

    my (
        $username,     $password1, $password2, $email1,
        $email2,       $full_name, $address,   $phone,
        $project_name, $login_uri, $error
      )
      = @param{
        qw{username password1 password2 email1 email2 full_name address phone project_name login_uri error}
      };

    if ( !defined($username) || $username eq '' ) {
        $$error = 'Username not specified';
        return;
    }
    if ( !defined($password1) || $password1 eq '' ) {
        $$error = 'Password not specified';
        return;
    }
    if ( !defined($password2) || $password2 eq '' ) {
        $$error = 'Password not confirmed';
        return;
    }
    if ( $password1 ne $password2 ) {
        $$error = 'Password and its confirmation do not match';
        return;
    }
    if ( !defined($full_name) || $full_name eq '' ) {
        $$error = 'Full name not specified';
        return;
    }
    if ( !defined($email1) || $email1 eq '' ) {
        $$error = 'Email not specified';
        return;
    }
    if ( !defined($email2) || $email2 eq '' ) {
        $$error = 'Email not confirmed';
        return;
    }
    if ( $email1 ne $email2 ) {
        $$error = 'Email and its confirmation do not match';
        return;
    }

    # Parsing email address with Email::Address->parse() has the side effect of
    # untainting user-entered email (applicable when CGI script is run in taint
    # mode with -T switch).
    my ($email_handle) = Email::Address->parse($email1);
    if ( !defined($email_handle) ) {
        $$error = 'Email address provided is not in valid format';
        return;
    }
    my $email_address = $email_handle->address;

    my $sth = $self->{dbh}->prepare('select count(*) from users where uname=?');
    my $row_count = $sth->execute($username);
    my ($user_found) = $sth->fetchrow_array;
    $sth->finish();
    if ($user_found) {
        $$error = "The user $username already exists in the database";
        return;
    }

    my $rows_affected = $self->{dbh}->do(
'insert into users set uname=?, pwd=?, email=?, full_name=?, address=?, phone=?',
        undef,
        $username,
        sha1_hex($password1),
        $email_address,
        $full_name,
        $address,
        $phone
    );

    $self->send_verify_email(
        project_name => $project_name,
        full_name    => $full_name,
        username     => $username,
        email        => $email_address,
        login_uri    => $login_uri
    );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
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
An email message has been sent to the email address you have entered. You should
confirm your email address by clicking on a link included in the email message.
Another email message has been sent to the administrator(s) of this site. Once
your request for access is approved, you can start browsing the content hosted
on this site.
END_register_user_text
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  send_verify_email
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  DBI::errstr, Mail::Send::close failure
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub send_verify_email {
    my ( $self, %param ) = @_;

    my ( $project_name, $full_name, $username, $email, $login_uri ) =
      @param{qw{project_name full_name username email login_uri}};

    my $hours_to_expire = 48;

    my $s = SGX::Session::Session->new(
        dbh       => $self->{dbh},
        expire_in => 3600 * $hours_to_expire,
        check_ip  => 0
    );

    $s->start();

    # make the session object store the username
    $s->session_store( username => $username );

    return unless $s->commit();

    #---------------------------------------------------------------------------
    #  email the confirmation link
    #---------------------------------------------------------------------------

    my $msg = Mail::Send->new(
        Subject => "Please confirm your email address with $project_name",
        To      => $email
    );
    $msg->add( 'From', ('NOREPLY') );
    my $fh = $msg->open()
      or SGX::Abstract::Exception::Internal::Mail->throw(
        error => 'Failed to open default mailer' );
    my $session_id = $s->get_session_id();
    print $fh <<"END_CONFIRM_EMAIL_MSG";
Hi $full_name,

You have recently applied for user access to $project_name. Please click on the
link below to confirm your email address with $project_name. You may be asked to
enter your username and password if you are not currently logged in.

$login_uri&sid=$session_id

This link will expire in $hours_to_expire hours.

If you have never heard of $project_name, please ignore this message or notify
the $project_name administrator if you keep receiving it.

- $project_name automatic mailer

END_CONFIRM_EMAIL_MSG
    $fh->close
      or SGX::Abstract::Exception::Internal::Mail->throw(
        error => 'Failed to send email message' );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
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
    if ( $self->{session_stash}->{username} ne $username ) {
        return;
    }
    my $rows_affected =
      $self->{dbh}->do( 'update users set email_confirmed=1 WHERE uname=?',
        undef, $username );

    if ( $rows_affected != 1 ) {
        SGX::Abstract::Exception::Internal->throw( error =>
"Expected to find one user record for login $username but $rows_affected were found.\n"
        );
    }
    return $rows_affected;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  perm_cookie_store
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Updates the session cookie first and then duplicates the data
#                to the permanent cookie
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub perm_cookie_store {
    my ( $self, %param ) = @_;
    if ( $self->session_cookie_store(%param) ) {
        while ( my ( $key, $value ) = each(%param) ) {
            $self->{perm_cookie}->{$key} = $value;
        }
        $self->{perm_cookie_modified} = 1;
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  read_perm_cookie
#   PARAMETERS:  OPTIONAL:
#                username => $username
#      RETURNS:  ????
#  DESCRIPTION:  Looks up permanent cookie name from current user name (cookie
#                name is an SHA1 digest of user name) and copies its values to
#                the transient session cookie.
#       THROWS:  no exceptions
#     COMMENTS:  Should only be called after username has been established
#     SEE ALSO:  n/a
#===============================================================================
sub read_perm_cookie {
    my ( $self, %param ) = @_;

    # try to get the username from the parameter list first; if no username
    # given then turn to session data.
    my $username = $param{username};
    $username = $self->{session_stash}->{username} unless defined($username);

    my $cookie_name = sha1_hex($username);
    my $cookies_ref = $self->{fetched_cookies};

    # in hash context, CGI::Cookie::value returns a hash
    my %val = eval { $cookies_ref->{$cookie_name}->value };

    #$self->{perm_cookie_value} = \%val;
    if (%val) {

        # copy all data from the permanent cookie to session cookie
        # so we don't have to read permanent cookie every time
        $self->session_cookie_store(%val);

        # hash has members (is not empty)
        return 1;
    }
    else {

        # hash is empty
        return;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
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
    if ( !defined( $self->{session_stash} ) ) {
        return;
    }
    my $current_level = $self->{session_stash}->{user_level};
    if ( !defined($current_level) ) {
        return;
    }
    if ( $req_user_level eq 'admin' ) {
        if ( $current_level eq 'admin' ) {
            return 1;
        }
    }
    elsif ( $req_user_level eq 'user' ) {
        if (   $current_level eq 'admin'
            || $current_level eq 'user' )
        {
            return 1;
        }
    }
    elsif ( $req_user_level eq 'unauth' ) {
        if (   $current_level eq 'admin'
            || $current_level eq 'user'
            || $current_level eq 'unauth' )
        {
            return 1;
        }
    }
    return;
}

1;    # for require

__END__

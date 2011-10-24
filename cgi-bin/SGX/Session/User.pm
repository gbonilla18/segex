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

use Readonly ();
use Digest::SHA1 qw/sha1_hex/;
require Mail::Send;
require Email::Address;

use SGX::Debug;
use SGX::Abstract::Exception ();
require SGX::Session::Base;    # for email confirmation
use SGX::Util qw/jam/;

# minimum password length (in characters)
Readonly::Scalar my $MIN_PWD_LENGTH => 6;

Readonly::Hash my %user_rank => (

    # :TODO:10/14/2011 11:54:35:es: This mapping will be replaced by actual
    # numeric values in the database.
    'anonym' => -1,
    ''       => 0,
    'user'   => 1,
    'admin'  => 2
);

#===  FUNCTION  ================================================================
#         NAME:  get_user_rank
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_user_rank {
    my $level = shift;
    return $user_rank{$level};
}

#===  FUNCTION  ================================================================
#         NAME:  static_auth
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub static_auth {

    # first argument: scalar
    my $current_level = shift;
    $current_level = 'anonym' if not defined $current_level;

    # second argument: tuple or scalar
    my $req_user_level = shift;

    my $num_current_level   = $user_rank{$current_level};
    my $req_user_level_type = ref $req_user_level;
    if ( $req_user_level_type eq '' ) {

        # authorized if current level is larger or equal to required
        my $num_req_user_level = $user_rank{$req_user_level};

        return ( defined($num_current_level)
              && defined($num_req_user_level)
              && $num_current_level >= $num_req_user_level )
          ? 1
          : ();
    }
    elsif ( $req_user_level_type eq 'ARRAY' ) {

        # authorized if current level lies in the required range
        my ( $req_level_from, $req_level_to ) = @$req_user_level;
        my $level_from = $user_rank{$req_level_from};
        my $level_to   = $user_rank{$req_level_to};

        return ( defined($num_current_level)
              && defined($level_from)
              && defined($level_to)
              && $num_current_level >= $level_from
              && $num_current_level <= $level_to )
          ? 1
          : ();
    }
    else {
        SGX::Exception::Internal->throw( error =>
              'Unknown reference type in argument to User::is_authorized' );
    }
}

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
#  it should be stored on the client (to save space in the database).  In
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
    return $self->authenticateFromDB(
        {
            username => $username,
            password => $password
        },
        reset_session => 1,
        error_string  => $error
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  authenticateFromDB
#   PARAMETERS:  ????
#      RETURNS:  True value on success, false value on failure
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub authenticateFromDB {
    my ( $self, $login, %args ) = @_;

    my ( $username, $password ) = @$login{qw(username password)};

    # default: true
    my $reset_session =
      ( exists $args{reset_session} )
      ? $args{reset_session}
      : 1;

    my $error_string;
    my $error = ( $args{error_string} ) ? $args{error_string} : \$error_string;

    #---------------------------------------------------------------------------
    #  get user info triple from the database
    #---------------------------------------------------------------------------
    my $query =
      ( defined $password )
      ? 'select uid, level, full_name, email from users where uname=? and pwd=?'
      : 'select uid, level, full_name, email from users where uname=?';

    my @params =
        ( defined $password )
      ? ( $username, sha1_hex($password) )
      : ($username);

    my $dbh       = $self->{dbh};
    my $sth       = $dbh->prepare($query);
    my $row_count = $sth->execute(@params);
    if ( $row_count < 1 ) {

        # user not found in the database
        $sth->finish;
        $self->destroy();
        $$error = 'Login incorrect';
        return;
    }
    elsif ( $row_count > 1 ) {

        # throw Internal::Duplicate exception
        $sth->finish;
        $self->destroy();
        SGX::Exception::Internal::Duplicate->throw(
            error => "Expected one user record but encountered $row_count.\n" );
    }

    # user found in the database
    my ( $user_id, $user_level, $user_full_name, $user_email ) =
      $sth->fetchrow_array;
    $sth->finish;
    $self->{_user_id} = $user_id;

    #---------------------------------------------------------------------------
    #  authenticate
    #---------------------------------------------------------------------------
    # :TRICKY:08/08/2011 10:09:29:es: We invalidate previous session id by
    # calling destroy() followed by start() to prevent Session Fixation
    # vulnerability: https://www.owasp.org/index.php/Session_Fixation

    if ($reset_session) {

        # get a new session handle. This will also delete the old session cookie
        $self->destroy();
        $self->start();
    }

    # Login username and user level are sensitive data: we only store them
    # remotely as part of session data. Note: by setting user_level field in
    # session data, we grant the owner of the current session access to the site
    # under that specific authorization level. In other words, this is the
    # specific line where the "magic" act of granting access happens. Note that
    # we only grant access to a new session handle, destroying the old one.
    return
      unless $self->session_store(
        username   => $username,
        user_level => $user_level
      );

    # Note: read permanent cookie before setting session cookie fields here:
    # this helps preserve the flow: database -> session -> (session_cookie,
    # perm_cookie), since reading permanent cookie synchronizes everything in it
    # with the session cookie.
    $self->read_perm_cookie($username);

    # Full user name is not sensitive from database perspective and can be
    # stored on the cliend in a can be stored on the client in a session cookie.
    # Note that there is no need to store it in a permanent cookie on the client
    # because the authentication process will involve a database transaction
    # anyway and a full name can be looked up from there.
    $self->session_cookie_store(
        full_name => $user_full_name,
        email     => $user_email
    );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  restore
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides SGX::Session::Cookie::restore
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub restore {
    my ( $self, $id ) = @_;
    return unless $self->SUPER::restore($id);

    # do not perform all of the confirmation nonsense when dealing with sessions
    # restored from cookies (i.e. for which no session id was provided).
    return 1 unless defined($id);

    # confirm username
    my $username = $self->{session_stash}->{username};

    #---------------------------------------------------------------------------
    #  authenticate from username
    #---------------------------------------------------------------------------
    return $self->authenticateFromDB( { username => $username },
        reset_session => 0 );
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
#       THROWS:  Exception::Class::DBI, SGX::Exception::Internal::Mail
#     COMMENTS:
# # :TODO:08/08/2011 12:26:07:es: rename this function to something else because
# no password is actually being reset anymore.
#
#     SEE ALSO:  n/a
#===============================================================================
sub reset_password {
    my $self  = shift;
    my %param = @_;

    my ( $username_or_email, $project_name, $login_uri, $error ) =
      @param{qw{username_or_email project_name login_uri error}};

    my ($email_handle) = Email::Address->parse($username_or_email);
    my ( $lvalue => $rvalue ) =
        ( defined $email_handle )
      ? ( 'email' => $email_handle->address )
      : ( 'uname' => $username_or_email );

    if ( !defined($rvalue) || $rvalue eq '' ) {
        $$error = 'You did not provide your login ID or a valid email address.';
        return;
    }

    # :TODO:08/08/2011 13:57:26:es: Can abstract out a method
    # $self->getSingleUser($uname, {pwd => '...', email_confirmed => 0..1}) --
    # see similar code in $self->authenticateFromDB().
    my $dbh = $self->{dbh};
    my $sth = $dbh->prepare(
"select uid, uname, level, full_name, email from users where $lvalue=? and email_confirmed=1"
    );
    my $rows_found = $sth->execute($rvalue);
    if ( $rows_found < 1 ) {

        # user not found in the database
        $sth->finish;
        $$error =
'The user does not exist in the database or user email address has not been verified';
        return;
    }
    elsif ( $rows_found > 1 ) {

        # several users found (e.g. when two or more users share the same email
        # address).
        $sth->finish;
        $$error =
"Cannot fulfill the request to reset password: more than one user were found matching $lvalue=$rvalue.\n";
        return;
    }

    # single user found in the database
    my ( $user_id, $username, $user_level, $user_full_name, $user_email ) =
      $sth->fetchrow_array;
    $sth->finish;
    $self->{_user_id} = $user_id;

    #---------------------------------------------------------------------------
    #  email a temporary access link
    #---------------------------------------------------------------------------

    my $hours_to_expire = 48;

    my $s = SGX::Session::Base->new(
        dbh       => $self->{dbh},
        expire_in => 3600 * $hours_to_expire,
        check_ip  => 1
    );

    $s->start();

    # :TRICKY:08/08/2011 12:29:42:es: This is were we grant previously existing
    # access level to a special URL and then send this URL to the user's email
    # address.
    $s->session_store(
        username   => $username,
        user_level => $user_level,
        change_pwd => 1
    );

    return unless $s->commit();
    my $session_id = $s->get_session_id();

    my $msg = Mail::Send->new(
        Subject => "Your Request to Change Your $project_name Password",
        To      => $user_email
    );
    $msg->add( 'From', 'no-reply' );
    my $fh = $msg->open()
      or SGX::Exception::Internal::Mail->throw(
        error => 'Failed to open default mailer' );
    print $fh <<"END_RESET_PWD_MSG";
Hi $user_full_name,

Please follow the link below to login to $project_name where you can change your
password to one of your preference:

$login_uri&sid=$session_id

This link will expire in $hours_to_expire hours.

If you think you have received this email by mistake, please notify the
$project_name administrator.

- $project_name automatic mailer

END_RESET_PWD_MSG

    $fh->close()
      or SGX::Exception::Internal::Mail->throw(
        error => 'Failed to send email message' );

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
A message has been sent to your email address. Once you receive the message, you 
will be able to login by clicking on the link provided. After clicking on the 
link, please set up your new password immediately using the Change Password 
form.
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

    my $require_old = !defined( $self->{session_stash}->{change_pwd} );

    my ( $old_password, $new_passwords, $error ) =
      @param{qw{old_password new_passwords error}};

    if ( $require_old && !defined($old_password) ) {
        $$error = 'You did not provide your current password';
        return;
    }
    if ( @$new_passwords < 2 ) {
        $$error =
'You did not provide a new password. You need to enter a new password twice to prevent an accidental typo.';
        return;
    }
    my $new_password = jam @$new_passwords;
    if ( !defined($new_password) ) {
        $$error = 'New password and its confirmation do not match';
        return;
    }
    if ( length($new_password) < $MIN_PWD_LENGTH ) {
        $$error =
          "New password must be at least $MIN_PWD_LENGTH characters long";
        return;
    }
    if ( $require_old and $new_password eq $old_password ) {
        $$error = 'The new and the old passwords you entered are the same.';
        return;
    }
    my $username = $self->{session_stash}->{username};
    if ( !defined($username) || $username eq '' ) {
        SGX::Exception::Internal->throw( error =>
"Expected to see a defined username in session data but none was found\n"
        );
    }

    my $query =
      ($require_old)
      ? 'update users set pwd=? where uname=? and pwd=?'
      : 'update users set pwd=? where uname=?';

    my @params =
        ($require_old)
      ? ( sha1_hex($new_password), $username, sha1_hex($old_password) )
      : ( sha1_hex($new_password), $username );

    my $dbh = $self->{dbh};
    my $rows_affected = $dbh->do( $query, undef, @params );

    if ( $rows_affected < 1 ) {
        $$error =
'The password was not changed. Please try again and make sure you entered your old password correctly.';
        return;
    }
    elsif ( $rows_affected > 1 ) {
        SGX::Exception::Internal::Duplicate->throw( error =>
              "Expected one user record but encountered $rows_affected.\n" );
        return;
    }

    # We try to shorten the time window where the user is allowed to change his
    # or her password without having to enter the old password. We do this by
    # allowing the user to change the password only once upon a reset password
    # request.
    $self->session_delete(qw(change_pwd));

    # The cleanse() method basically changes the session id while keeping the
    # same session data that we have currently set. Changing the session id will
    # also automatically delete the old session cookie.
    return $self->cleanse();
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
    my ( $password, $emails, $project_name, $login_uri, $error ) =
      @param{qw{password emails project_name login_uri error}};

    if ( !defined($password) ) {
        $$error = 'Password not specified';
        return;
    }
    if ( @$emails < 2 ) {
        $$error =
'You did not provide an email address. You need to enter an email address twice to prevent an accidental typo.';
        return;
    }
    my $email = jam @$emails;
    if ( !defined($email) ) {
        $$error =
          'Email address you entered and its confirmation do not match.';
        return;
    }

    # Parsing email address with Email::Address->parse() has the side effect of
    # untainting user-entered email (applicable when CGI script is run in taint
    # mode with -T switch).
    my ($email_handle) = Email::Address->parse($email);
    if ( !defined($email_handle) ) {
        $$error =
'You did not provide an email address or the email address entered is not in a valid format.';
        return;
    }
    my $email_address = $email_handle->address;

    $password = sha1_hex($password);
    my $username = $self->{session_stash}->{username};
    if ( !defined($username) || $username eq '' ) {
        SGX::Exception::Internal->throw( error =>
"Expected to see a defined username in session data but none was found\n"
        );
    }

    my $full_name = $self->{session_cookie}->{full_name};

    my $rows_affected = $self->{dbh}->do(
'update users set email=?, email_confirmed=0 where uname=? and pwd=? and email != ?',
        undef, $email_address, $username, $password, $email_address
    );

    if ( $rows_affected == 1 ) {
        return $self->send_verify_email(
            project_name => $project_name,
            full_name    => $full_name,
            username     => $username,
            email        => $email_address,
            login_uri    => $login_uri
        );
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
        SGX::Exception::Internal::Duplicate->throw( error =>
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
        $username, $passwords,    $emails,    $full_name, $address,
        $phone,    $project_name, $login_uri, $error
      )
      = @param{
        qw/username passwords emails full_name address phone project_name login_uri error/
      };

    if ( !defined($username) || $username eq '' ) {
        $$error = 'Username not specified';
        return;
    }

    if ( @$passwords < 2 ) {
        $$error =
'You did not provide a new password. You need to enter a new password twice to prevent an accidental typo.';
        return;
    }
    my $password = jam @$passwords;
    if ( !defined($password) ) {
        $$error = 'New password and its confirmation do not match';
        return;
    }
    if ( length($password) < $MIN_PWD_LENGTH ) {
        $$error =
          "New password must be at least $MIN_PWD_LENGTH characters long";
        return;
    }
    if ( !defined($full_name) || $full_name eq '' ) {
        $$error = 'Full name not specified';
        return;
    }
    if ( @$emails < 2 ) {
        $$error =
'You did not provide an email address. You need to enter an email address twice to prevent an accidental typo.';
        return;
    }
    my $email = jam @$emails;
    if ( !defined($email) ) {
        $$error =
          'Email address you entered and its confirmation do not match.';
        return;
    }

    my $dbh = $self->{dbh};

    # Parsing email address with Email::Address->parse() has the side effect of
    # untainting user-entered email (applicable when CGI script is run in taint
    # mode with -T switch).
    my ($email_handle) = Email::Address->parse($email);
    if ( !defined($email_handle) ) {
        $$error =
'You did not provide an email address or the email address entered is not in a valid format.';
        return;
    }
    my $email_address = $email_handle->address;

    my $sth       = $dbh->prepare('select count(*) from users where uname=?');
    my $row_count = $sth->execute($username);
    my ($user_found) = $sth->fetchrow_array;
    $sth->finish();
    if ($user_found) {
        $$error = "The user $username already exists in the database";
        return;
    }

    my $rows_affected = $dbh->do(
'insert into users set uname=?, pwd=?, email=?, full_name=?, address=?, phone=?',
        undef,
        $username,
        sha1_hex($password),
        $email_address,
        $full_name,
        $address,
        $phone
    );

    return $self->send_verify_email(
        project_name => $project_name,
        full_name    => $full_name,
        username     => $username,
        email        => $email_address,
        login_uri    => $login_uri
    );
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

    my $s = SGX::Session::Base->new(
        dbh       => $self->{dbh},
        expire_in => 3600 * $hours_to_expire,
        check_ip  => 1
    );

    $s->start();

    # make the session object store the username
    $s->session_store( username => $username );

    return unless $s->commit();
    my $session_id = $s->get_session_id();

    #---------------------------------------------------------------------------
    #  email the confirmation link
    #---------------------------------------------------------------------------

    my $msg = Mail::Send->new(
        Subject => "Please confirm your email address with $project_name",
        To      => $email
    );
    $msg->add( 'From', 'no-reply' );
    my $fh = $msg->open()
      or SGX::Exception::Internal::Mail->throw(
        error => 'Failed to open default mailer' );
    print $fh <<"END_CONFIRM_EMAIL_MSG";
Hi $full_name,

You have recently applied for user access to $project_name. Please click on the
link below to confirm your email address with $project_name.

$login_uri&sid=$session_id

This link will expire in $hours_to_expire hours.

If you think you have received this email by mistake, please notify the
$project_name administrator.

- $project_name automatic mailer

END_CONFIRM_EMAIL_MSG

    $fh->close()
      or SGX::Exception::Internal::Mail->throw(
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
        SGX::Exception::Internal->throw( error =>
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
    my ( $self, $username ) = @_;

    # try to get the username from the parameter list first; if no username
    # given then turn to session data.
    $username = $self->{session_stash}->{username} unless defined($username);

    my $cookie_name = sha1_hex($username);
    my $cookies_ref = $self->{fetched_cookies};

    # in hash context, CGI::Cookie::value returns a hash
    my %val = eval { $cookies_ref->{$cookie_name}->value };

    if (%val) {

        # copy all data from the permanent cookie to session cookie
        # so we don't have to read permanent cookie every time
        $self->session_cookie_store(%val);

        # for each key/value combo, execute appropriate subroutine if "entailer"
        # is found in the perm2cookie table
        my $perm2session = $self->{perm2session};
        while ( my ( $key, $value ) = each(%val) ) {
            if ( my $entailer = $perm2session->{$key} ) {
                $self->session_cookie_store( $entailer->($value) );
            }
        }

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
#   PARAMETERS:  $self           - reference to object instance
#                $req_user_level - required credential level (either scalar
#                representing range [$scalar, +Inf) or tuple representing range
#                [$scalar1, $scalar2]).
#      RETURNS:  1 if golden, 0 if not logged in, -1 if logged in with different
#                privileges from required ones.
#  DESCRIPTION:  checks whether the currently logged-in user has the required
#                credentials
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub is_authorized {
    my ( $self, $req_user_level ) = @_;

    # do not authorize if request level is undefined
    return if not defined $req_user_level;

    # otherwise we need session information to compare requested permission
    # level with the current one.
    my $session_level = ( $self->{session_stash} || {} )->{user_level};

    return static_auth( $session_level, $req_user_level )
      ? 1
      : ( ( defined $session_level ) ? -1 : 0 );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  get_user_id
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Session only stores user login name -- not the numeric id which
#                exists in the database. This function returns the latter given
#                the former.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_user_id {
    my $self = shift;

    # first see if cached value is available
    my $user_id = $self->{_user_id};
    return $user_id if defined $user_id;

    # attempt to retrieve by login name which is stored in session data
    my $username = $self->{session_stash}->{username};
    if ( defined $username ) {
        my $dbh = $self->{dbh};
        my $sth = $dbh->prepare('select uid from users where uname=?');
        my $rc  = $sth->execute($username);
        $user_id = $sth->fetchrow_array;
        $sth->finish;
    }

    # cache the returned value
    $self->{_user_id} = $user_id;
    return $user_id;
}

1;    # for require

__END__


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

    if ($s->is_authorized('admin') == 1) {
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
        `level` enum('','user','admin') NOT NULL,
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



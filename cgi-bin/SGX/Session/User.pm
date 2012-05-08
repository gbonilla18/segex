package SGX::Session::User;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.12';

use base qw/SGX::Session::Cookie/;

use Readonly ();
require Mail::Send;
require Email::Address;

use SGX::Debug;
use SGX::Abstract::Exception ();
require SGX::Session::Base;    # for email confirmation
use SGX::Util qw/car equal uniq/;

Readonly::Scalar my $TABLE          => 'users';
Readonly::Scalar my $PRIMARY_KEY    => 'uid';
Readonly::Scalar my $MIN_PWD_LENGTH => 6;
Readonly::Hash my %user_rank        => (

    # :TODO:10/14/2011 11:54:35:es: This mapping could be replaced by actual
    # numeric values in the database.
    'anonym'   => -1,
    'nogrants' => 0,
    'readonly' => 1,
    'user'     => 2,
    'admin'    => 3
);

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
            -name    => $self->encrypt($username),
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
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Overrides Session::Base::authenticate
#     SEE ALSO:  n/a
#===============================================================================
sub authenticate {
    my ( $self, $args ) = @_;
    my $session_id = $args->{session_id};
    return ( defined($session_id) && $session_id ne '' )
      ? $self->SUPER::authenticate($args)
      : $self->authenticateFromDB($args);
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  authenticateFromDB
#   PARAMETERS:  $self - reference to object instance
#               {
#                username => user name string
#                password => password string
#                reset_session => whether to destroy existing session and start
#                               a new one on successful login
#                }
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
sub authenticateFromDB {
    my ( $self, $args ) = @_;

    my ( $username, $password ) = @$args{qw(username password)};
    ( defined($username) && $username ne '' )
      or SGX::Exception::User->throw( error => 'No username provided' );

    # convert password to SHA1 hash right away
    $password = $self->encrypt($password);

    # default: true
    my $reset_session =
      ( exists $args->{reset_session} )
      ? $args->{reset_session}
      : 1;

    #---------------------------------------------------------------------------
    #  get user record
    #---------------------------------------------------------------------------
    my $udata = eval {
        $self->select_users(
            select => [ $PRIMARY_KEY, qw/level full_name email/ ],
            where  => {
                uname => $username,
                ( defined($password) ? ( pwd => $password ) : () )
            },
            ensure_single => 1
        )->[0];
    };
    my $exception;
    if ( $exception =
        Exception::Class->caught('SGX::Exception::Internal::Duplicate') )
    {
        $self->destroy();
        if ( $exception->{records_found} == 0 ) {
            SGX::Exception::User->throw( error => 'Login incorrect' );
        }
        else {
            $exception->rethrow;
        }
    }
    elsif ( $exception = Exception::Class->caught() ) {
        $self->destroy();
        if ( eval { $exception->can('rethrow') } ) {
            $exception->rethrow;
        }
        else {
            SGX::Exception::Internal->throw( error => "$exception" );
        }
    }

    #---------------------------------------------------------------------------
    #  authenticate
    #---------------------------------------------------------------------------
    if ($reset_session) {

        # :TRICKY:08/08/2011 10:09:29:es: We invalidate previous session id by
        # calling destroy() followed by start() to prevent Session Fixation
        # vulnerability: https://www.owasp.org/index.php/Session_Fixation

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
    SGX::Exception::Internal::Session->throw(
        error => 'Could not store session info' )
      unless $self->session_store(
        username   => $username,
        user_level => $udata->{level},
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
        full_name => $udata->{full_name},
        email     => $udata->{email}
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

    #---------------------------------------------------------------------------
    #  authenticate against database
    #---------------------------------------------------------------------------
    my $username = $self->{session_stash}->{username};
    if (
        my $ret = $self->authenticateFromDB(
            { username => $username, reset_session => 0 }
        )
      )
    {
        $self->update_user(
            set           => { email_confirmed => 1 },
            where         => { uname           => $username },
            ensure_single => 1
        );
        return $ret;
    }
    else {
        return;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  reset_password
#   PARAMETERS:  $self - reference to object instance
#                $username
#                $project_name
#                $login_uri - the full URI of the login script plus the command
#                to show the form to change a password
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
    my ( $self, %args ) = @_;

    my ( $username_or_email, $project_name, $login_uri, $new_user ) =
      @args{qw{username_or_email project_name login_uri new_user}};

    my ($email_handle) = Email::Address->parse($username_or_email);
    my ( $lvalue => $rvalue ) =
        ( defined $email_handle )
      ? ( 'email' => $email_handle->address )
      : ( 'uname' => $username_or_email );

    ( defined($rvalue) && $rvalue ne '' )
      or SGX::Exception::User->throw( error =>
          'You did not provide your login ID or a valid email address.' );

    # Do not check for duplicates: duplicates could only mean that there are two
    # usernames for the same email address. In that case, pick the first user
    # record returned by the DBI and send an email.
    my $udata = eval {
        $self->select_users(
            select => [qw/uname level full_name email/],
            where  => {
                $lvalue => $rvalue,
                ( $new_user ? () : ( email_confirmed => 1 ) )
            },
            ensure_single => 1
        )->[0];
    };
    my $exception;
    if ( $exception =
        Exception::Class->caught('SGX::Exception::Internal::Duplicate') )
    {
        if ( $exception->{records_found} < 1 ) {
            SGX::Exception::User->throw( error =>
'User name does not exist in the database or user email address has not been verified'
            );
        }
        else {

            # at least one user found
            $udata = $exception->{data}->[0];
        }
    }
    elsif ( $exception = Exception::Class->caught() ) {
        if ( eval { $exception->can('rethrow') } ) {
            $exception->rethrow;
        }
        else {
            SGX::Exception::Internal->throw( error => "$exception" );
        }
    }

    #---------------------------------------------------------------------------
    # Set up a new session for data store
    #---------------------------------------------------------------------------
    my $hours_to_expire = 48;
    my $s               = SGX::Session::Base->new(
        dbh       => $self->{dbh},
        expire_in => 3600 * $hours_to_expire,
        check_ip  => 1
    );
    $s->start();
    $s->session_store(
        username   => $udata->{uname},
        user_level => $udata->{level},
        change_pwd => 1
    );
    return unless $s->commit();
    my $session_id = $s->get_session_id();

    #---------------------------------------------------------------------------
    #  email a temporary access link
    #---------------------------------------------------------------------------
    my $subject =
      $new_user
      ? "Your account was created for you on $project_name"
      : "Your request to change your $project_name password";
    my $user_name =
      ( defined( $udata->{full_name} ) && $udata->{full_name} ne '' )
      ? $udata->{full_name}
      : $udata->{uname};
    $self->send_email(
        config => {
            Subject => $subject,
            To      => $udata->{email}
        },
        message => <<"END_RESET_PWD_MSG");
Hi $user_name,

Please follow the link below to login to $project_name where you can change your
password to one of your preference:

$login_uri&sid=$session_id

$project_name keeps your passwords private. This link will expire in
$hours_to_expire hours.

If you believe you have received this message by mistake, please notify the
$project_name administrator.

- $project_name automatic mailer

END_RESET_PWD_MSG

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
link, please set up your new password using the Change Password form.
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

    my ( $old_password, $new_passwords ) =
      @param{qw{old_password new_passwords}};

    ( !$require_old || defined($old_password) )
      or SGX::Exception::User->throw(
        error => 'You did not provide your current password' );

    ( @$new_passwords > 1 )
      or SGX::Exception::User->throw( error =>
'You did not provide a new password. You need to enter a new password twice to prevent an accidental typo.'
      );

    ( equal @$new_passwords )
      or SGX::Exception::User->throw(
        error => 'New password and its confirmation do not match' );

    my $new_password = car @$new_passwords;
    ( length($new_password) >= $MIN_PWD_LENGTH )
      or SGX::Exception::User->throw( error =>
          "New password must be at least $MIN_PWD_LENGTH characters long" );

    ( !$require_old || $new_password ne $old_password )
      or SGX::Exception::User->throw(
        error => 'The new and the old passwords you entered are the same.' );

    $new_password = $self->encrypt($new_password);
    $old_password = $self->encrypt($old_password);

    my $username = $self->{session_stash}->{username};
    ( defined($username) && $username ne '' )
      or SGX::Exception::Internal->throw( error =>
          "Expected a defined username in session data but none was found\n" );

    $self->update_user(
        set   => { pwd => $new_password },
        where => {
            uname => $username,
            ( $require_old ? ( pwd => $old_password ) : () )
        },
        ensure_single => 1
    );

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
    my ( $passwords, $emails, $project_name, $login_uri ) =
      @param{qw{passwords emails project_name login_uri}};

    my $username = $self->{session_stash}->{username};
    ( defined($username) && $username ne '' )
      or SGX::Exception::Internal->throw(
        error => 'No user name in session data: session could be corrupt' );

    ( @$passwords > 0 )
      or
      SGX::Exception::User->throw( error => 'You did not provide a password' );
    ( equal @$passwords )
      or SGX::Exception::User->throw( error =>
          'The password your entered does not match the confirmation password'
      );
    my $password = $self->encrypt( car @$passwords );
    if (
        !$self->count_users(
            where => {
                uname => $username,
                pwd   => $password
            }
        )
      )
    {
        SGX::Exception::User->throw( error =>
'The password you entered isn\'t a valid password for this account'
        );
    }

    ( @$emails > 0 )
      or SGX::Exception::User->throw(
        error => 'You did not provide an email address' );
    ( equal @$emails )
      or SGX::Exception::User->throw( error =>
'The email address you entered does not match the confirmation address'
      );
    my $email = car @$emails;

    # Parsing email address with Email::Address->parse() has the side effect of
    # untainting user-entered email (applicable when CGI script is run in taint
    # mode with -T switch).
    my ($email_handle) = Email::Address->parse($email);
    defined($email_handle)
      or SGX::Exception::User->throw( error =>
'You did not provide an email address or the email address entered is not in a valid format'
      );

    #---------------------------------------------------------------------------
    #  Send email message
    #---------------------------------------------------------------------------
    return $self->send_verify_email(
        {
            project_name    => $project_name,
            full_name       => $self->{session_cookie}->{full_name},
            username        => $username,
            email_address   => $email_handle->address,
            password_hash   => $password,
            user_level      => ( $self->{session_stash} || {} )->{user_level},
            login_uri       => $login_uri,
            hours_to_expire => 48
        }
    );
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
An email message has been sent to the email address you entered. To complete
changing your email address, please confirm that the email address is yours by
clicking on the link provided in the email message.
END_change_email_text
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  select_users
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Primitive ORM-like mechanism for returning record objects as an
#                ordered list.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub select_users {
    my ( $self, %args ) = @_;

    # arguments
    my $select_fields = $args{select};
    my $where_fields  = $args{where};
    my $ensure_single = $args{ensure_single};

    # SQL statement
    my $sql =
        'SELECT '
      . join( ',', uniq @$select_fields )
      . " FROM $TABLE WHERE "
      . join( ' AND ', map { "$_=?" } keys %$where_fields );

    # database handle
    my $dbh = $self->{dbh};
    my $sth = $dbh->prepare($sql);

    # fill out @data array with row records
    $sth->execute( values(%$where_fields) );
    my @data;
    while ( my $row = $sth->fetchrow_hashref ) {
        push @data, $row;
    }
    my $records_found = scalar(@data);
    $sth->finish;
    if ( $ensure_single && $records_found != 1 ) {
        SGX::Exception::Internal::Duplicate->throw(
            error => "Expected to find one user but $records_found were found",
            records_found => $records_found,
            data          => \@data
        );
    }
    return \@data;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  insert_user
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub insert_user {
    my ( $self, %args ) = @_;

    # arguments
    my $set_fields = $args{set};
    delete $set_fields->{$PRIMARY_KEY};

    # SQL statement
    my $sql =
      "INSERT INTO $TABLE SET " . join( ',', map { "$_=?" } keys %$set_fields );

    # database handle
    my $dbh           = $self->{dbh};
    my $sth           = $dbh->prepare($sql);
    my $rows_affected = int( $sth->execute( values %$set_fields ) );
    $sth->finish;

    if ( $rows_affected == 0 ) {

        # no user inserted
        SGX::Exception::User->throw( error =>
              'Can\'t add user: user may already exist in the database' );
    }
    elsif ( $rows_affected != 1 ) {

        # should never get here
        SGX::Exception::Internal::Duplicate->throw(
            error =>
              "Expected to insert one record but $rows_affected were inserted",
            records_found => $rows_affected
        );
    }

    return $dbh->last_insert_id( undef, undef, $TABLE, $PRIMARY_KEY );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  update_user
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub update_user {
    my ( $self, %args ) = @_;

    # arguments
    my $set_fields    = $args{set};
    my $where_fields  = $args{where};
    my $ensure_single = $args{ensure_single};

    # SQL statement
    my $sql =
        "UPDATE $TABLE SET "
      . join( ',', map { "$_=?" } keys %$set_fields )
      . ' WHERE '
      . join( ' AND ', map { "$_=?" } keys %$where_fields );

    # database handle
    my $dbh = $self->{dbh};
    my $sth = $dbh->prepare($sql);

    # turn off automatic commits to allow for rollback
    my $old_AutoCommit = $dbh->{AutoCommit};
    $dbh->{AutoCommit} = 0;

    my $rows_affected = eval {
        int( $sth->execute( values(%$set_fields), values(%$where_fields) ) );
    };
    if ( my $exception = Exception::Class->caught() ) {
        $sth->finish;
        $dbh->rollback;
        $dbh->{AutoCommit} = $old_AutoCommit;
        if ( eval { $exception->can('rethrow') } ) {
            $exception->rethrow;
        }
        else {
            SGX::Exception::Internal->throw( error => "$exception" );
        }
    }
    elsif ( $rows_affected == 0 ) {
        $sth->finish;
        $dbh->rollback;
        $dbh->{AutoCommit} = $old_AutoCommit;
        SGX::Exception::User->throw(
            error => 'Can\'t update user: User not found' );
    }
    elsif ( $ensure_single && $rows_affected != 1 ) {

        # From DBI docs: "For a non-SELECT statement, execute returns the number
        # of rows affected, if known. If no rows were affected, then execute
        # returns "0E0", which Perl will treat as 0 but will regard as true.
        # Note that it is not an error for no rows to be affected by a
        # statement. If the number of rows affected is not known, then execute
        # returns -1."
        $sth->finish;
        $dbh->rollback;
        $dbh->{AutoCommit} = $old_AutoCommit;
        SGX::Exception::Internal::Duplicate->throw(
            error => "Encountered $rows_affected user records but expected one",
            records_found => $rows_affected
        );
    }

    $sth->finish;
    $dbh->commit;
    $dbh->{AutoCommit} = $old_AutoCommit;

    return $rows_affected;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  count_users
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub count_users {
    my ( $self, %args ) = @_;

    # arguments
    my $where_fields = $args{where};

    # SQL statement
    my $sql = "SELECT COUNT(*) FROM $TABLE WHERE "
      . join( ' AND ', map { "$_=?" } keys %$where_fields );

    # database handle
    my $dbh = $self->{dbh};
    my $sth = $dbh->prepare($sql);
    $sth->execute( values(%$where_fields) );
    my ($user_count) = $sth->fetchrow_array;
    $sth->finish;

    return int($user_count);
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

    my ( $username, $passwords, $emails, $full_name, $project_name, $login_uri )
      = @param{qw/username passwords emails full_name project_name login_uri/};

    ( defined($username) && $username ne '' )
      or SGX::Exception::User->throw( error => 'Username not specified' );

    ( @$passwords > 1 )
      or SGX::Exception::User->throw( error =>
'You did not provide a new password. You need to enter a new password twice to prevent an accidental typo.'
      );

    ( equal @$passwords )
      or SGX::Exception::User->throw(
        error => 'New password and its confirmation do not match' );

    my $password = car @$passwords;
    ( length($password) >= $MIN_PWD_LENGTH )
      or SGX::Exception::User->throw( error =>
          "New password must be at least $MIN_PWD_LENGTH characters long" );

    ( defined($full_name) && $full_name ne '' )
      or SGX::Exception::User->throw( error => 'Full name not specified' );

    ( @$emails > 1 )
      or SGX::Exception::User->throw( error =>
'You did not provide an email address. You need to enter an email address twice to prevent an accidental typo.'
      );

    ( equal @$emails )
      or SGX::Exception::User->throw( error =>
          'Email address you entered and its confirmation do not match.' );

    my $email = car @$emails;

    # Parsing email address with Email::Address->parse() has the side effect of
    # untainting user-entered email (applicable when CGI script is run in taint
    # mode with -T switch).
    my ($email_handle) = Email::Address->parse($email);
    defined($email_handle)
      or SGX::Exception::User->throw( error =>
'You did not provide an email address or the email address entered is not in a valid format.'
      );

    #---------------------------------------------------------------------------
    #  Send email message
    #---------------------------------------------------------------------------
    return $self->send_verify_email(
        {
            project_name    => $project_name,
            full_name       => $full_name,
            username        => $username,
            password_hash   => $self->encrypt($password),    # SHA1 hash
            email_address   => $email_handle->address,
            login_uri       => $login_uri,
            hours_to_expire => 48
        }
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
An email message has been sent to the email address you entered. To complete
your registration, please confirm your email address by clicking on the link
provided in the email message.
END_register_user_text
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  open_mailer
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub send_email {
    my ( $self, %args ) = @_;

    # arguments
    my $config  = $args{config}  || {};
    my $message = $args{message} || '';

    # set up file handle
    my $fh = eval {
        my $msg = Mail::Send->new(%$config);
        $msg->add( 'From', 'no-reply' );
        $msg->open();
    } or do {
        if ( my $exception = Exception::Class->caught() ) {
            if ( eval { $exception->can('rethrow') } ) {
                $exception->rethrow();
            }
            else {
                SGX::Exception::Internal::Mail->throw( error => "$exception" );
            }
        }
        else {

            # email filehandle evaluated to false
            SGX::Exception::Internal::Mail->throw(
                error => 'Could not set up mailer' );
        }
    };

    # print body
    print $fh $message;

    # send message
    $fh->close()
      or SGX::Exception::Internal::Mail->throw(
        error => 'Failed to send email message' );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::User
#       METHOD:  notify_admins
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  Mail::Send::close failure
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub notify_admins {
    my ( $self, %args ) = @_;

    # arguments
    my $user         = $args{user}         || {};
    my $user_uri     = $args{user_uri}     || '';
    my $project_name = $args{project_name} || '';

    my $user_name =
      ( defined( $user->{full_name} ) && $user->{full_name} ne '' )
      ? "$user->{full_name} (login name: $user->{uname})"
      : "$user->{uname}";

    my $admins = $self->select_users(
        select        => [qw/uname full_name email/],
        where         => { level => 'admin' },
        ensure_single => 0
    );

    #---------------------------------------------------------------------------
    #  attempt to email the confirmation link to every admin
    #---------------------------------------------------------------------------
    foreach my $admin (@$admins) {
        my $admin_name =
          ( defined( $admin->{full_name} ) && $admin->{full_name} ne '' )
          ? $admin->{full_name}
          : $admin->{uname};
        $self->send_email(
            config => {
                Subject => "A new user has registered with $project_name",
                To      => $admin->{email}
            },
            message => <<"END_CONFIRM_EMAIL_MSG");
Hi $admin_name,

A user $user_name has signed up to $project_name. At present, the user cannot
access or modify any data on $project_name. Please grant this user the
appropriate permissions by visiting the following page (login may be required):

$user_uri

If you believe you have received this message by mistake, please notify the
$project_name administrator.

- $project_name automatic mailer
END_CONFIRM_EMAIL_MSG
    }

    return 1;
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
    my $self = shift;
    my $data = shift;

    # defaults
    my $hours_to_expire = ( $data->{hours_to_expire} + 0 ) || 48;

    # start new session and get session id
    my $s = SGX::Session::Base->new(
        dbh       => $self->{dbh},
        expire_in => 3600 * $hours_to_expire,
        check_ip  => 1
    );
    $s->start();
    defined( my $session_id = $s->get_session_id() )
      or SGX::Exception::Internal::Session->throw(
        error => 'Undefined session id' );

    #---------------------------------------------------------------------------
    #  attempt to email the confirmation link
    #---------------------------------------------------------------------------
    $self->send_email(
        config => {
            Subject =>
              "Please confirm your email address with $data->{project_name}",
            To => $data->{email_address}
        },
        message => <<"END_CONFIRM_EMAIL_MSG");
Hi $data->{full_name},

Please confirm your email address with $data->{project_name} by clicking on the
link below:

$data->{login_uri}&_sid=$session_id

This link will expire in $hours_to_expire hours.

If you believe you have received this message by mistake, please notify the
$data->{project_name} administrator.

- $data->{project_name} automatic mailer
END_CONFIRM_EMAIL_MSG

    # Now back to dealing with session
    # store the username in the session object
    $s->session_store(
        username   => $data->{username},
        password   => $data->{password_hash},    # SHA1 hash
        email      => $data->{email_address},
        full_name  => $data->{full_name},
        user_level => $data->{user_level}
    );

    # commit session to database/storage
    $s->commit()
      or SGX::Exception::Internal::Session->throw(
        error => 'Cannot store session data' );

    return 1;
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
    $username = $self->{session_stash}->{username}
      unless defined($username);

    my $cookie_name = $self->encrypt($username);
    my $cookies_ref = $self->{fetched_cookies};

    # in hash context, CGI::Cookie::value returns a hash
    my %val = eval { $cookies_ref->{$cookie_name}->value };

    if (%val) {

        # copy all data from the permanent cookie to session cookie
        # so we don't have to read permanent cookie every time
        $self->session_cookie_store(%val);

        # for each key/value combo, execute appropriate subroutine if code block
        # is found in the perm2cookie table
        my $perm2session = $self->{perm2session};
        while ( my ( $key, $value ) = each(%val) ) {
            if ( my $lambda = $perm2session->{$key} ) {
                $self->session_cookie_store( $lambda->($value) );
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
    my $self = shift;
    my %args = @_;

    # default level is 'nogrants'
    my $req_user_level = $args{level} || 'nogrants';

    # do not authorize if request level is undefined
    #return unless defined $req_user_level;

    # otherwise we need session information to compare requested permission
    # level with the current one.
    my $session_level = ( $self->{session_stash} || {} )->{user_level};

    return static_auth( $session_level, $req_user_level )
      ? 1
      : ( defined($session_level) ? -1 : 0 );
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
    $current_level = 'anonym' unless defined $current_level;

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
    return SGX::Exception::Internal->throw(
        error => 'Unknown reference type in argument to User::is_authorized' );
}

1;

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

    $s->authenticate({username => $uname, password => $pwd});

Note: $login_uri must be in this form: /cgi-bin/my/path/index.cgi?a=login

    $s->reset_password($username, $project_name, $login_uri);

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



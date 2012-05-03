package SGX::Profile;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

use SGX::Debug;
use URI::Escape qw/uri_unescape uri_escape/;
use SGX::Util qw/car/;

{

    package SGX::DropDownData;

    use strict;
    use warnings;

    #use SGX::Debug
    use SGX::Abstract::Exception ();
    require Tie::IxHash;

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  new
#   PARAMETERS:  0) $self  - object instance
#                1) $dbh   - database handle
#                2) $query - SQL query string (with or without placeholders)
#      RETURNS:  $self
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  :NOTE:06/01/2011 03:32:37:es: preparing query once during
#                  construction
#     SEE ALSO:  n/a
#===============================================================================
    sub new {
        my ( $class, $dbh, $query ) = @_;

        my $sth = $dbh->prepare($query)
          or SGX::Exception::Internal->throw( error => $dbh->errstr );

        my $self = {
            _dbh  => $dbh,
            _sth  => $sth,
            _tied => undef,
            _hash => {},
        };

        # Tying the hash using Tie::IxHash module allows us to keep hash
        # keys ordered
        $self->{_tied} = tie( %{ $self->{_hash} }, 'Tie::IxHash' );

        bless $self, $class;
        return $self;
    }

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  clone
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is a copy constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
    sub clone {
        my $self = shift;

        my $clone = {
            _dbh  => $self->{_dbh},
            _sth  => $self->{_sth},
            _tied => undef,
            _hash => {},
        };

        # Tying the hash using Tie::IxHash module allows us to keep hash
        # keys ordered
        $clone->{_tied} = tie( %{ $clone->{_hash} }, 'Tie::IxHash' );

        # now fill the new hash
        $clone->{_tied}->Push( %{ $self->{_hash} } );

        bless $clone, ref $self;
        return $clone;
    }

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  loadDropDownValues
#   PARAMETERS:  $self
#                @params - array of parameters to be used to fill placeholders
#                in the query statement
#      RETURNS:  reference to drop down data stored in key-value format (hash)
#  DESCRIPTION:  loads values by executing query
#       THROWS:  no exceptions
#     COMMENTS:  :NOTE:06/01/2011 03:31:28:es: allowing this method to be
#                 executed more than once
#     SEE ALSO:  http://search.cpan.org/~chorny/Tie-IxHash-1.22/lib/Tie/IxHash.pm
#===============================================================================
    sub loadDropDownValues {
        my ( $self, @params ) = @_;

        my $rc = $self->{_sth}->execute(@params)
          or SGX::Exception::Internal->throw( error => $self->{_dbh}->errstr );

        my @sthArray = @{ $self->{_sth}->fetchall_arrayref };

        $self->{_sth}->finish;

        my $hash_ref = $self->{_hash};
        foreach (@sthArray) {
            my $k = $_->[0];
            SGX::Exception::Internal->throw(
                error => "Conflicting key '$k' in output hash" )
              if exists $hash_ref->{$k};
            $hash_ref->{$k} = $_->[1];
        }

        return $hash_ref;
    }

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  Push
#   PARAMETERS:  0) $self
#                1) list of key-value pairs, e.g. Push('0' => 'All Values', ...)
#      RETURNS:  Same as Tie::IxHash::Push
#  DESCRIPTION:  Add key-value array to hash using Tie::IxHash object
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
    sub Push {
        my ( $self, @rest ) = @_;
        return $self->{_tied}->Push(@rest);
    }

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  Unshift
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Wraps the Unshift method in Tie::IxHash
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
    sub Unshift {
        my ( $self, @rest ) = @_;
        return $self->{_tied}->Unshift(@rest);
    }

    1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, @param ) = @_;
    my $self = $class->SUPER::new(@param);

    $self->set_attributes(
        _title => 'My Profile',

        # model
        _curr_proj   => '',
        _projectList => {}
    );
    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    $self->SUPER::init();

    $self->set_attributes( _permission_level => 'anonym' );
    $self->register_actions(

       # default profile page is useless at any level below nogrants.
       # change/verify email and password is useless at any level below nogrants
        '' => {
            head => 'default_head',
            body => 'default_body',
            perm => 'nogrants'
        },
        form_changePassword => {
            body => 'form_changePassword_body',
            perm => 'nogrants'
        },
        changePassword => {
            head => 'changePassword_head',
            perm => 'nogrants'
        },
        form_changeEmail => {
            body => 'form_changeEmail_body',
            perm => 'nogrants'
        },
        changeEmail => {
            head => 'changeEmail_head',
            perm => 'nogrants'
        },
        verifyEmail => { head => 'verifyEmail_head', perm => 'nogrants' },
        logout      => { head => 'logout_head',      perm => 'nogrants' },

        # projects are useless at any level below readonly
        chooseProject => {
            head => 'chooseProject_head',
            body => 'chooseProject_body',
            perm => 'readonly'
        },
        changeProjectTo => {
            head => 'changeProjectTo_head',
            body => 'chooseProject_body',
            perm => 'readonly'
        },

        # have to allow 'forgot password' functionality to anonymous users
        form_resetPassword => {
            head => 'default_head',
            body => 'form_resetPassword_body',
            perm => 'anonym'
        },
        resetPassword => { head => 'resetPassword_head', perm => 'anonym' },

        # register user and login are allowed to anonymous users *only*
        form_registerUser => {
            head => 'default_head',
            body => 'form_registerUser_body',
            perm => [ 'anonym', 'anonym' ]
        },
        registerUser =>
          { head => 'registerUser_head', perm => [ 'anonym', 'anonym' ] },
        form_login => {
            head => 'default_head', # cannot leave this field empty since
                                    # in that case the system will lookup
                                    # default action ('') for its head hook
                                    # (default_head), and default action in this
                                    # module requires user to be logged in and
                                    # will redirect back to form_login causing
                                    # an infinite loop.
            body => 'form_login_body',
            perm => [ 'anonym', 'anonym' ]
        },
        login => { head => 'login_head', perm => [ 'anonym', 'anonym' ] }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  logout_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub logout_head {
    my $self = shift;
    my $s    = $self->{_UserSession};
    $s->destroy;
    $self->redirect( $self->url( -absolute => 1 ) );
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {
    my $self = shift;
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};
    my $url_absolute = $q->url( -absolute => 1 );

    return $q->h2('My Profile'),
      (
        ( $self->is_authorized( level => 'user' ) == 1 )
        ? $q->p(
            $q->a(
                {
                    -href  => $url_absolute . '?a=profile&b=chooseProject',
                    -title => 'Choose Project'
                },
                'Choose Project'
            )
          )
        : ''
      ),
      $q->p(
        $q->a(
            {
                -href  => $url_absolute . '?a=profile&b=form_changePassword',
                -title => 'Change Password'
            },
            'Change Password'
        )
      ),
      $q->p(
        $q->a(
            {
                -href  => $url_absolute . '?a=profile&b=form_changeEmail',
                -title => 'Change Email'
            },
            'Change Email'
        )
      );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  changeEmail_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub changeEmail_head {
    my $self = shift;
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};

    my $error_string;
    if (
        $s->change_email(
            password     => car( $q->param('password') ),
            emails       => [ $q->param('email') ],
            project_name => 'Segex',
            login_uri    => $q->url( -full => 1 ) . '?a=verifyEmail',
            error        => \$error_string
        )
      )
    {
        $self->set_action('');    # default page: profile
        $self->add_message( $s->change_email_text() );
    }
    else {
        $self->add_message( { -class => 'error' }, $error_string );
        $self->set_action('form_changeEmail');    # change email form
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  login_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub login_head {
    my $self = shift;
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};

    my $error_string;
    if (
        defined($s)
        and $s->authenticate(
            car( $q->param('username') ),
            car( $q->param('password') ),
            \$error_string
        )
        and $self->is_authorized() == 1
      )
    {

        my $destination =
          ( defined( $q->url_param('next') ) )
          ? uri_unescape( $q->url_param('next') )
          : undef;
        if (   defined($destination)
            && $destination ne $q->url( -absolute => 1 )
            && $destination !~ m/(?:&|\?|&amp;)b=login(?:\z|&|#)/
            && $destination !~ m/(?:&|\?|&amp;)b=form_login(?:\z|&|#)/ )
        {

            # will send a redirect header, so commit the session to data
            # store now
            $s->commit() if defined $s;

            # if the user is heading to a specific placce, pass him/her
            # along, otherwise continue to the main page (script_name)
            # do not add nph=>1 parameter to redirect() because that
            # will cause it to crash
            $self->redirect( $q->url( -base => 1 ) . $destination );
        }
        else {
            $self->set_action('');    # default page: profile
        }
    }
    else {

        # error: show corresponding form again
        $self->add_message( { -class => 'error' }, $error_string );
        $self->set_action('form_login');
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  form_login_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_login_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    my $uri = $q->url( -absolute => 1, -query => 1 );

    # do not want to logout immediately after login
    $uri = $q->url( -absolute => 1 )
      if $uri =~ m/(?:&|\?|&amp;)b=logout(?:\z|&|#)/;
    my $destination = uri_escape(
        ( defined $q->url_param('next') )
        ? $q->url_param('next')
        : $uri
    );
    return $q->h2('Login to Segex'),
      $q->start_form(
        -accept_charset => 'utf-8',
        -method         => 'POST',
        -action         => $q->url( -absolute => 1 )
          . "?a=profile&b=login&next=$destination",
        -onsubmit =>
          'return validate_fields(this, [\'username\',\'password\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'username' }, 'Login name:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'username',
                -id        => 'username',
                -maxlength => 40,
                -title     => 'Enter your login id'
            )
        ),
        $q->dt( $q->label( { -for => 'password' }, 'Password:' ) ),
        $q->dd(
            $q->password_field(
                -name      => 'password',
                -id        => 'password',
                -maxlength => 40,
                -title     => 'Enter your login password'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(

            #form_error($error_string),
            $q->submit(
                -name  => 'login',
                -id    => 'login',
                -class => 'button black bigrounded',
                -value => 'Login',
                -title => 'Click submit to login'
            ),
            $q->span( { -class => 'separator' }, ' / ' ),
            $q->a(
                {
                    -href => $q->url( -absolute => 1 )
                      . '?a=profile&b=form_resetPassword',
                    -title => 'Click here if you forgot your password.'
                },
                'I Forgot My Password'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  registerUser_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub registerUser_head {
    my $self = shift;
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};

    my $errors_encountered = 0;
    eval {
        $s->register_user(
            username     => car( $q->param('username') ),
            passwords    => [ $q->param('password') ],
            emails       => [ $q->param('email') ],
            full_name    => car( $q->param('full_name') ),
            address      => car( $q->param('address') ),
            phone        => car( $q->param('phone') ),
            project_name => 'Segex',
            login_uri    => $q->url( -full => 1 ) . '?a=profile&b=verifyEmail'
        );
    } or do {
        if ( my $exception = Exception::Class->caught() ) {
            my $msg = eval { $exception->error } || "$exception";
            $self->add_message( { -class => 'error' }, $msg );
        }
        else {
            $self->add_message( { -class => 'error' },
                'No user record created' );
        }
        $errors_encountered++;
    };

    if ($errors_encountered) {
        $self->set_action('form_registerUser');  # show corresponding form again
    }
    else {
        $self->add_message( $s->register_user_text() );
        $self->set_action('');                   # show default/profile page
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  form_registerUser_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_registerUser_body {

    my $self = shift;
    my $q    = $self->{_cgi};

    # user cannot be logged in
    return $q->h2('Apply for Access to Segex'),
      $q->start_form(
        -accept_charset => 'utf-8',
        -method         => 'POST',
        -action => $q->url( -absolute => 1 ) . '?a=profile&b=registerUser',
        -onsubmit =>
"return validate_fields(this, ['username','password1','password2','email1','email2']);"
      ),
      $q->dl(
        $q->dt(
            $q->label(
                { -class => 'optional', -for => 'full_name' },
                'Your Full Name:'
            )
        ),
        $q->dd(
            $q->textfield(
                -name  => 'full_name',
                -id    => 'full_name',
                -size  => 30,
                -title => 'Enter your first and last names here (optional)'
            ),
            $q->p(
                { -class => 'hint visible' },
                'Enter your first and last names here'
            )
        ),
        $q->dt( $q->label( { -for => 'username' }, 'Login name:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'username',
                -id    => 'username',
                -title => 'Enter your future login id'
            ),
            $q->p(
                { -class => 'hint visible' },
                'Choose a short name for login purposes'
            )
        ),
        $q->dt( $q->label( { -for => 'password1' }, 'Password:' ) ),
        $q->dd(
            $q->password_field(
                -name      => 'password',
                -id        => 'password1',
                -maxlength => 40,
                -title     => 'Enter your future password'
            ),
            '&nbsp;&nbsp;',
            $q->label(
                { for => 'password2' },
                $q->strong('Retype to confirm:')
            ),
            $q->password_field(
                -name      => 'password',
                -id        => 'password2',
                -maxlength => 40,
                -title     => 'Type your password again for confirmation'
            ),
            $q->p(
                { -class => 'hint visible' },
'Passwords must be at least 6 characters long. Please choose a password that is hard to guess and which contains letters as well as digits.'
            )
        ),
        $q->dt( $q->label( { -for => 'email1' }, 'Email:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'email',
                -id    => 'email1',
                -title => 'Enter your email address here (must be valid)'
            ),
            '&nbsp;&nbsp;',
            $q->label( { -for => 'email2' }, $q->strong('Retype to confirm:') ),
            $q->textfield(
                -name  => 'email',
                -id    => 'email2',
                -title => 'Type your email address again for confirmation'
            ),
            $q->p(
                { -class => 'hint visible' },
'Registering your email address with Segex will allow you to retrieve your password in case you forget it.'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(

            #form_error($error_string),
            $q->submit(
                -name  => 'registerUser',
                -id    => 'registerUser',
                -class => 'button black bigrounded',
                -value => 'Register',
                -title => 'Submit this registration form'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  form_resetPassword_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub resetPassword_head {
    my $self = shift;
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};

    my $error_string;
    if (
        $s->reset_password(
            username_or_email => car( $q->param('username') ),
            project_name      => 'Segex',
            login_uri         => $q->url( -full => 1 )
              . '?a=profile&b=form_changePassword',
            error => \$error_string
        )
      )
    {
        $self->set_action('form_login');
        $self->add_message( $s->reset_password_text() );
    }
    else {

        # error: show corresponding form again
        $self->add_message( { -class => 'error' }, $error_string );
        $self->set_action('form_resetPassword');
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  form_resetPassword_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_resetPassword_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->h2('I Forgot My Password'),
      $q->start_form(
        -accept_charset => 'utf-8',
        -method         => 'POST',
        -action   => $q->url( -absolute => 1 ) . '?a=profile&b=resetPassword',
        -onsubmit => 'return validate_fields(this, [\'username\']);'
      ),
      $q->dl(
        $q->dt(
            $q->label( { -for => 'username' }, 'Login name or email address:' )
        ),
        $q->dd(
            $q->textfield(
                -name  => 'username',
                -id    => 'username',
                -title => 'Enter your login ID or email address'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(

            #form_error($error_string),
            $q->submit(
                -name  => 'resetPassword',
                -id    => 'resetPassword',
                -class => 'button black bigrounded',
                -value => 'Reset my password',
                -title => <<"END_forgotPassword"
Click to issue a new password and send a message containing the new password to 
the email address registered under your login name.
END_forgotPassword
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  verifyEmail_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub verifyEmail_head {
    my $self = shift;
    my ( $dbh, $q, $s ) = @$self{qw/_dbh _cgi _UserSession/};

    require SGX::Session::Base;
    my $t = SGX::Session::Base->new(
        dbh       => $dbh,
        expire_in => 3600 * 48,
        check_ip  => 0
    );
    if ( $t->restore( car( $q->param('sid') ) ) ) {
        if ( $s->verify_email( $t->{session_stash}->{username} ) ) {
            $self->add_message('Success! You email address has been verified.');
        }
        $self->set_action('');    # default page: profile
        $t->destroy();
        return 1;
    }
    else {

        # redirect to main page
        $self->redirect( $self->url( -absolute => 1 ) );
        return;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  changePassword_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub changePassword_head {
    my $self = shift;
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};

    my $error_string;
    if (
        !$s->change_password(
            old_password  => car( $q->param('old_password') ),
            new_passwords => [ $q->param('new_password') ],
            error         => \$error_string
        )
      )
    {
        $self->add_message( { -class => 'error' }, $error_string );
        $self->set_action('form_changePassword');    # change password form
        return 1;
    }
    $self->set_action('');                           # default page: profile
    $self->add_message(
        'Success! Your password has been changed to the one you provided.');
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  form_changePassword_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_changePassword_body {
    my $self = shift;
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};

    # user has to be logged in
    my $require_old = !defined( $s->{session_stash}->{change_pwd} );
    return $q->h2('Change Password'),
      $q->start_form(
        -accept_charset => 'utf-8',
        -method         => 'POST',
        -action   => $q->url( -absolute => 1 ) . '?a=profile&b=changePassword',
        -onsubmit => (
            ($require_old)
            ? "return validate_fields(this, ['old_password','new_password1','new_password2']);"
            : "return validate_fields(this, ['new_password1','new_password2']);"
        )
      ),
      $q->dl(
        ($require_old)
        ? (
            $q->dt( $q->label( { -for => 'old_password' }, 'Old Password:' ) ),
            $q->dd(
                $q->password_field(
                    -name      => 'old_password',
                    -id        => 'old_password',
                    -maxlength => 40,
                    -title     => 'Enter your old password here'
                )
            )
          )
        : (),
        $q->dt( $q->label( { -for => 'new_password1' }, 'New Password:' ) ),
        $q->dd(
            $q->password_field(
                -name      => 'new_password',
                -id        => 'new_password1',
                -maxlength => 40,
                -title => 'Enter the new password you would like to change to'
            )
        ),
        $q->dt(
            $q->label( { -for => 'new_password2' }, 'Confirm New Password:' )
        ),
        $q->dd(
            $q->password_field(
                -name      => 'new_password',
                -id        => 'new_password2',
                -maxlength => 40,
                -title     => 'Type the new password again to confirm it'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(

            #form_error($error_string),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Change password',
                -title => 'Click to change your current password to the new one'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Profile
#       METHOD:  form_changeEmail_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_changeEmail_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    # user has to be logged in
    return $q->h2('Change Email Address'),
      $q->start_form(
        -accept_charset => 'utf-8',
        -method         => 'POST',
        -action => $q->url( -absolute => 1 ) . '?a=profile&b=changeEmail',
        -onsubmit =>
          'return validate_fields(this, [\'password\',\'email1\',\'email2\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'password' }, 'Password:' ) ),
        $q->dd(
            $q->password_field(
                -name      => 'password',
                -id        => 'password',
                -maxlength => 40,
                -title     => 'Enter your current user password'
            )
        ),
        $q->dt( $q->label( { -for => 'email1' }, 'New Email Address:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'email',
                -id    => 'email1',
                -title => 'Enter your new email address'
            )
        ),
        $q->dt( $q->label( { -for => 'email2' }, 'Confirm New Address:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'email',
                -id    => 'email2',
                -title => 'Confirm your new email address'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(

            #form_error($error_string),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Change email',
                -title => 'Submit form'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  changeProjectTo_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub changeProjectTo_head {
    my $self = shift;

    $self->chooseProject_init();
    $self->changeToCurrent();

    # load data for the form
    $self->loadProjectData();

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  chooseProject_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub chooseProject_head {
    my $self = shift;

    # default action -- only load data for the form
    $self->chooseProject_init();
    $self->loadProjectData();

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  changeToCurrent
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub changeToCurrent {
    my $self = shift;
    my $s    = $self->{_UserSession};

    # store id in a permanent cookie (also gets copied to the
    # session cookie automatically)
    $s->perm_cookie_store( curr_proj => $self->{_curr_proj} );

    # no need to store the working project name in permanent storage
    # (only store the working project id there) -- store it only in
    # the session cookie (which is read every time session is
    # initialized).
    $s->session_cookie_store( proj_name => $self->getProjectName() );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Only load form data and URL parameters here -- do not
#                undertake anything here that would cause change of external
#                state.
#     SEE ALSO:  n/a
#===============================================================================
sub chooseProject_init {
    my $self = shift;
    my ( $q, $s ) = @$self{qw{_cgi _UserSession}};

    # First tries to get current project id from the CGI parameter; failing
    # that, looks it up from the session cookie.

    my $curr_proj = car( $q->param('proj') );
    $self->{_curr_proj} =
      defined($curr_proj)
      ? $curr_proj
      : $s->{session_cookie}->{curr_proj};

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  loadProjectData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Display a list of projects
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadProjectData {
    my $self = shift;

    my $sql = 'SELECT prid, prname FROM project ORDER BY prname ASC';
    my $projectDropDown = SGX::DropDownData->new( $self->{_dbh}, $sql );

    $projectDropDown->Push( '' => '@All Projects' );
    $self->{_projectList} = $projectDropDown->loadDropDownValues();

    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  getProjectName
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  We choose empty string to mean 'All projects'
#     SEE ALSO:  n/a
#===============================================================================
sub getProjectName {
    my $self = shift;
    my $dbh  = $self->{_dbh};

    my $curr_proj = $self->{_curr_proj};

    return '' unless defined($curr_proj);
    my $sth = $dbh->prepare('SELECT prname FROM project WHERE prid=?');
    my $rc  = $sth->execute($curr_proj);
    if ( $rc != 1 ) {
        $sth->finish;
        return '';
    }
    my ($full_name) = $sth->fetchrow_array;
    $sth->finish;
    return $full_name;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  chooseProject_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Render the HTML form for changing current project
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub chooseProject_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #Load the study dropdown to choose which experiments to load into table.
    return $q->h2('Select working project'),
      $q->start_form(
        -accept_charset => 'utf-8',
        -method         => 'POST',
        -action  => $q->url( -absolute => 1 ) . '?a=profile&b=changeProjectTo',
        -enctype => 'application/x-www-form-urlencoded'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'proj' }, 'Project:' ) ),
        $q->dd(
            $q->popup_menu(
                -name    => 'proj',
                -id      => 'proj',
                -values  => [ keys %{ $self->{_projectList} } ],
                -labels  => $self->{_projectList},
                -default => $self->{_curr_proj},
                -title   => 'Select a project from the list'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Change',
                -title => 'Change your working project to the selected one'
            )
        )
      ),
      $q->end_form;
}

1;

=head1 NAME

SGX::Profile

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


package SGX::Profile;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

use SGX::Abstract::Exception ();
use URI::Escape qw/uri_unescape uri_escape/;
use SGX::Util qw/car/;
require SGX::Model::DropDownData;

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides Strategy::Base::new
#       THROWS:  no exceptions
#     COMMENTS:  Recover session from id in the sid CGI parameter, or, if the
#     sid parameter is not set, from cookie, or, if cookie is not found, start a
#     new session.
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, %args ) = @_;

    my $config = $args{config} || {};
    my $q      = $config->{_cgi};
    my $self   = $class->SUPER::new(
        config               => $config,
        restore_session_from => ( car $q->param('sid') )
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
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};

    $self->set_attributes(
        _title            => 'My Profile',
        _permission_level => 'anonym'
    );

    # :TRICKY:05/04/2012 14:08:38:es: For all actions in this module, "head"
    # attribute cannot be empty unless their permission level is "nogrants".
    # This is because, if the head attribute of an action is empty/undefined,
    # the dispatcher code will lookup default action ('') and use its head hook
    # "default_head". The default action is currently set to "nogrants" (user
    # has to be logged in), and thus having empty "head" attribute will result
    # in dispatcher redirecting back to form_login causing an infinite loop.
    $self->register_actions(

        '' => {

            # default profile page is useless at any level below nogrants.
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
            perm => 'anonym'
        },
        logout => { head => 'logout_head', perm => 'nogrants' },

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

            head => 'default_head',
            body => 'form_login_body',
            perm => 'anonym'
        },
        login => { head => 'login_head', perm => 'anonym' }
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

    my $sid = car $q->url_param('_sid');
    if ( defined $sid ) {

        # destroy existing session if its id doesn't match
        my $current_sid = $s->get_session_id();
        if ( !defined($current_sid) || $current_sid ne $sid ) {
            $s->destroy();
        }

        if ( defined $q->param('login') ) {

    #---------------------------------------------------------------------------
    #  Sent here from login form, also have sid
    #---------------------------------------------------------------------------
            my $username = car $q->param('username');
            my $password = car $q->param('password');

            eval {
                $s->authenticate(
                    {
                        username   => $username,
                        password   => $password,
                        session_id => $sid
                    }
                );
            } or do {
                my $exception;
                if (
                    $exception = Exception::Class->caught(
                        'SGX::Exception::Session::Expired')
                  )
                {

                    # Give more specific reason error message instead of the
                    # default 'Your session has expired.'
                    $self->add_message(
                        { -class => 'error' },
'Your session has expired. Please log in to Segex to continue.'
                    );
                    $self->set_action('form_login');
                    return 1;
                }
                elsif ( $exception =
                    Exception::Class->caught('SGX::Exception::User') )
                {

                    # User error: show the same form with the same action URI to
                    # allow user to reenter his/her credentials.
                    $self->add_message( { -class => 'error' },
                        $exception->error );
                    $self->{_form_login_action} =
                      '?a=profile&b=changeEmail&_sid=' . $sid;
                    $self->set_action('form_login');
                    return 1;
                }
                else {

                    # No error or internal error
                    $exception = Exception::Class->caught();
                    my $msg =
                         eval { $exception->error }
                      || "$exception"
                      || 'Unknown error';
                    warn $msg;    ## no critic
                    $self->add_message(
                        { -class => 'error' },
'Failed to process your login. If you are an administrator, see error log for details of this error.'
                    );
                    $self->set_action('');
                    return 1;
                }
            };
            $self->add_message('User credentials authenticated.');

    #---------------------------------------------------------------------------
    #  now actually change email
    #---------------------------------------------------------------------------
            eval {
                $s->update_user(
                    set => {
                        email_confirmed => 1,
                        email           => $s->{session_cookie}->{email}
                    },
                    where => {
                        uname => $username,
                        pwd   => $s->encrypt($password)
                    },
                    ensure_single => 1
                );
            } or do {
                my $exception = Exception::Class->caught();
                my $msg =
                     eval { $exception->error }
                  || "$exception"
                  || 'Unknown error';
                warn $msg;    ## no critic
                $self->add_message(
                    { -class => 'error' },
'Failed to change email. If you are an administrator, see error log for details of this error.'
                );
                $self->set_action('');
                return 1;
            };

            # restore session
            $s->renew();

            # on success show default page (user profile)
            $self->add_message(
'Success! You have changed your email address registered with Segex.'
            );
            $self->set_action('');
            return 1;
        }
        else {

    #---------------------------------------------------------------------------
    #  Have sid, show login form
    #---------------------------------------------------------------------------
            $self->add_message(
'Please enter your username and password to finish changing your email address.'
            );
            $self->{_form_login_action} =
              '?a=profile&b=changeEmail&_sid=' . $sid;
            $self->set_action('form_login');
            return 1;
        }
    }
    else {
        eval {
            $s->change_email(
                passwords    => [ $q->param('password') ],
                emails       => [ $q->param('email') ],
                project_name => 'Segex',
                login_uri => $q->url( -full => 1 ) . '?a=profile&b=changeEmail'
            );
        } or do {
            my $exception = Exception::Class->caught();
            my $msg =
              eval { $exception->error } || "$exception" || 'Unknown error';
            $self->add_message( { -class => 'error' }, $msg );

            # show corresponding form again
            $self->set_action('form_changeEmail');
            return 1;
        };

        $self->add_message( $s->change_email_text() );
        $self->set_action('');    # default page: profile
        return 1;
    }
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

    #---------------------------------------------------------------------------
    #  Attempt login
    #---------------------------------------------------------------------------
    eval {
        $s->authenticate(
            {
                username => car( $q->param('username') ),
                password => car( $q->param('password') ),
            }
        );
    } or do {

    #---------------------------------------------------------------------------
    #  Exception condition
    #---------------------------------------------------------------------------
        my $exception;
        if ( $exception = Exception::Class->caught('SGX::Exception::User') ) {

            # User error: show corresponding form again
            $self->add_message( { -class => 'error' }, $exception->error );
            $self->set_action('form_login');
            return 1; ## do show body
        }
        else {

            # No error or internal error
            $exception = Exception::Class->caught();
            my $msg =
              eval { $exception->error } || "$exception" || 'Unknown error';
            warn $msg;    ## no critic
            $self->add_message(
                { -class => 'error' },
'Failed to process your login. If you are an administrator, see error log for details of this error.'
            );
            $self->set_action('');
            return 1; ## do show body
        }
    };

    #---------------------------------------------------------------------------
    #  Unauthorized
    #---------------------------------------------------------------------------
    if ( $self->is_authorized() != 1 ) {
        $self->add_message( { -class => 'error' }, 'Login failed.' );
        $self->set_action('form_login');
        return 1;
    }

    #---------------------------------------------------------------------------
    #  Login OK
    #---------------------------------------------------------------------------
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
    my $form_login_action =
      defined( $self->{_form_login_action} )
      ? $self->{_form_login_action}
      : "?a=profile&b=login&next=$destination";

    return $q->h2('Login to Segex'),
      $q->start_form(
        -accept_charset => 'ISO-8859-1',
        -method         => 'POST',
        -action         => $q->url( -absolute => 1 ) . $form_login_action,
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
            $q->submit(
                -name  => 'login',
                -id    => 'login',
                -class => 'button black bigrounded',
                -value => 'Login',
                -title => 'Click to sign in to Segex'
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

    my $sid = car $q->url_param('_sid');
    if ( defined $sid ) {

        # destroy existing session if its id doesn't match
        my $current_sid = $s->get_session_id();
        if ( !defined($current_sid) || $current_sid ne $sid ) {
            $s->destroy();
        }

        if ( defined $q->param('login') ) {

    #---------------------------------------------------------------------------
    #  Sent here from login form, also have sid
    #---------------------------------------------------------------------------
            my $username = car $q->param('username');
            my $password = car $q->param('password');

            eval {
                $s->authenticate(
                    {
                        username   => $username,
                        password   => $password,
                        session_id => $sid
                    }
                );
            } or do {
                my $exception;
                if (
                    $exception = Exception::Class->caught(
                        'SGX::Exception::Session::Expired')
                  )
                {

                    # Give more specific reason error message instead of the
                    # default 'Your session has expired.'
                    $self->add_message(
                        { -class => 'error' },
'Your session has expired. Please log in to Segex to continue.'
                    );
                    $self->set_action('form_login');
                    return 1;
                }
                elsif ( $exception =
                    Exception::Class->caught('SGX::Exception::User') )
                {

                    # User error: show the same form with the same action URI to
                    # allow user to reenter his/her credentials.
                    $self->add_message( { -class => 'error' },
                        $exception->error );
                    $self->{_form_login_action} =
                      '?a=profile&b=registerUser&_sid=' . $sid;
                    $self->set_action('form_login');
                    return 1;
                }
                else {

                    # No error or internal error
                    $exception = Exception::Class->caught();
                    my $msg =
                         eval { $exception->error }
                      || "$exception"
                      || 'Unknown error';
                    warn $msg;    ## no critic
                    $self->add_message(
                        { -class => 'error' },
'Failed to process your login. If you are an administrator, see error log for details of this error.'
                    );
                    $self->set_action('');
                    return 1;
                }
            };
            $self->add_message('Authentication OK');

    #---------------------------------------------------------------------------
    #  now actually register the user
    #---------------------------------------------------------------------------
            my $user = {
                uname           => $username,
                pwd             => $s->encrypt($password),
                email           => $s->{session_cookie}->{email},
                full_name       => $s->{session_cookie}->{full_name},
                email_confirmed => 1
            };
            my $user_id = eval { $s->insert_user( set => $user ) };
            if ( my $exception = Exception::Class->caught() ) {
                my $msg =
                     eval { $exception->error }
                  || "$exception"
                  || 'Unknown error';
                warn $msg;    ## no critic
                $self->add_message(
                    { -class => 'error' },
'Failed to process your login. If you are an administrator, see error log for details of this error.'
                );
                $self->set_action('');
                return 1;
            }

            # Notify administrators about this user's registration
            $s->notify_admins(
                user         => $user,
                project_name => 'Segex',
                user_uri     => $q->url( -full => 1 ) . "?a=users&id=$user_id"
            );

            # Grant basic access (we actually call this level 'nogrants' because
            # it does not let one perform any SQL statements on data).
            $s->session_store( user_level => 'nogrants' );
            $s->renew();

            # on success show default page (user profile)
            $self->add_message(<<"END_notify_comment");
Success! You are now registered with Segex. Please wait until one of the
administrators (who have been automatically notified about your registration)
grants you appropriate permissions so you can access the data on this site.
END_notify_comment
            $self->set_action('');
            return 1;
        }
        else {

    #---------------------------------------------------------------------------
    #  Have sid, show login form
    #---------------------------------------------------------------------------
            $self->add_message(
'Please enter your username and password to complete the registration process.'
            );
            $self->{_form_login_action} =
              '?a=profile&b=registerUser&_sid=' . $sid;
            $self->set_action('form_login');
            return 1;
        }
    }
    else {
        eval {
            $s->register_user(
                username     => car( $q->param('username') ),
                passwords    => [ $q->param('password') ],
                emails       => [ $q->param('email') ],
                full_name    => car( $q->param('full_name') ),
                project_name => 'Segex',
                login_uri => $q->url( -full => 1 ) . '?a=profile&b=registerUser'
            );
        } or do {
            my $exception = Exception::Class->caught();
            my $msg =
              eval { $exception->error } || "$exception" || 'Unknown error';
            $self->add_message( { -class => 'error' }, $msg );

            # show corresponding form again
            $self->set_action('form_registerUser');
            return 1;
        };

        $self->add_message( $s->register_user_text() );
        $self->set_action('');    # show default/profile page
        return 1;
    }
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
        -accept_charset => 'ISO-8859-1',
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
                'Type your first and last names here.'
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
                'Choose a short name you will use to sign in to Segex.'
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
                { -for => 'password2' },
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
'Passwords must be at least six characters long. Please choose a password that is difficult to guess.'
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
                'Email address to send regisration link to.'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Register',
                -title => 'Submit this form'
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

    eval {
        $s->reset_password(
            username_or_email => car( $q->param('username') ),
            project_name      => 'Segex',
            login_uri         => $q->url( -full => 1 )
              . '?a=profile&b=form_changePassword'
        );
    } or do {

    #---------------------------------------------------------------------------
    #  Reset failed
    #---------------------------------------------------------------------------
        my $exception;
        if ( $exception = Exception::Class->caught('SGX::Exception::User') ) {

            # User error: show corresponding form again
            $self->set_action('form_resetPassword');
            $self->add_message( { -class => 'error' }, $exception->error );
            return 1;
        }
        elsif ( $exception = Exception::Class->caught() ) {

            # Internal error
            my $msg =
              eval { $exception->error } || "$exception" || 'Unknown error';
            warn $msg;    ## no critic
            $self->add_message(
                { -class => 'error' },
'Failed to process password reset. If you are an administrator, see error log for details of this error.'
            );
            $self->set_action('');
            return 1;
        }
        else {

            # No error
            $self->add_message( { -class => 'error' },
                'Failed to reset password.' );
            $self->set_action('form_login');
            return 1;
        }
    };

    #---------------------------------------------------------------------------
    #  Reset OK
    #---------------------------------------------------------------------------
    $self->set_action('form_login');
    $self->add_message( $s->reset_password_text() );
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

    return $q->h2('Request to Change Password'),
      $q->start_form(
        -accept_charset => 'ISO-8859-1',
        -method         => 'POST',
        -action   => $q->url( -absolute => 1 ) . '?a=profile&b=resetPassword',
        -onsubmit => 'return validate_fields(this, [\'username\']);'
      ),
      $q->dl(
        $q->dt(
            $q->label( { -for => 'username' }, 'Your login or email address:' )
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
            $q->submit(
                -name  => 'resetPassword',
                -id    => 'resetPassword',
                -class => 'button black bigrounded',
                -value => 'Send me a link to change password',
                -title => 'Click to request to change your password.'
            )
        )
      ),
      $q->end_form;
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

    eval {
        $s->change_password(
            old_password  => car( $q->param('old_password') ),
            new_passwords => [ $q->param('new_password') ]
        );
    } or do {
        my $exception;
        if ( $exception = Exception::Class->caught('SGX::Exception::User') ) {

            # User error: show corresponding form again
            $self->add_message( { -class => 'error' }, $exception->error );
            $self->set_action('form_changePassword');    # change password form
            return 1;
        }
        elsif ( $exception = Exception::Class->caught() ) {

            # Internal error
            my $msg =
              eval { $exception->error } || "$exception" || 'Unknown error';
            warn $msg;                                   ## no critic
            $self->add_message(
                { -class => 'error' },
'Failed to change password. If you are an administrator, see error log for details of this error.'
            );
            $self->set_action('');
            return 1;
        }
        else {

            # No error
            $self->add_message( { -class => 'error' },
                'Changing password failed.' );
            $self->set_action('form_login');
            return 1;
        }
    };
    $self->set_action('');    # default page: profile
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
        -accept_charset => 'ISO-8859-1',
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
            ),
            $q->label(
                { -for => 'new_password2' },
                $q->strong('Retype to confirm:')
            ),
            $q->password_field(
                -name      => 'new_password',
                -id        => 'new_password2',
                -maxlength => 40,
                -title     => 'Type the new password again to confirm it'
            ),
            $q->p(
                { -class => 'hint visible' },
'Passwords must be at least six characters long. Please choose a password that is difficult to guess.'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
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
        -accept_charset => 'ISO-8859-1',
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
            ),
            '&nbsp;&nbsp;',
            $q->label( { -for => 'email2' }, $q->strong('Retype to confirm:') ),
            $q->textfield(
                -name  => 'email',
                -id    => 'email2',
                -title => 'Confirm your new email address'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
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
    my $projectDropDown = SGX::Model::DropDownData->new( $self->{_dbh}, $sql );

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
        -accept_charset => 'ISO-8859-1',
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


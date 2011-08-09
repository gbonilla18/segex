#!/usr/bin/perl -wT

use strict;
use warnings;

# CGI options: -nosticky option prevents CGI.pm from printing hidden .cgifields
# inside a form. We do not add qw/:standard/ because we use object-oriented
# style.
use CGI 2.47 qw/-nosticky -private_tempfiles/;

#use CGI::Pretty 2.47 qw/-nosticky/;
use Carp;    # croak exported automatically
use Switch;
use URI::Escape;
use Tie::IxHash;

#---------------------------------------------------------------------------
# Custom modules in SGX directory
#---------------------------------------------------------------------------
use lib qw/./;
use SGX::Debug;                    # all debugging code goes here
use SGX::Config;                   # all configuration for our project goes here
use SGX::Session::User 0.07;       # user authentication, sessions and cookies
use SGX::Session::Session 0.08;    # email verification

#---------------------------------------------------------------------------
#  User Authentication
#---------------------------------------------------------------------------
my $softwareVersion = '0.2.4';

my $dbh = sgx_db_connect();
my $s   = SGX::Session::User->new(
    dbh       => $dbh,
    expire_in => 3600,             # expire in 3600 seconds (1 hour)
    check_ip  => 1
);

my $q = CGI->new();

$s->restore( $q->param('sid') );    # restore old session if it exists

#---------------------------------------------------------------------------
#  Main
#---------------------------------------------------------------------------
my $error_string;
my $title;

# :TODO:08/07/2011 16:05:55:es: Allow each page to specify its own CSS includes
# aka it is currently done with Javascript source files.
my $css = [
    { -src => YUI_BUILD_ROOT . '/reset-fonts/reset-fonts.css' },
    { -src => YUI_BUILD_ROOT . '/container/assets/skins/sam/container.css' },
    { -src => YUI_BUILD_ROOT . '/button/assets/skins/sam/button.css' },
    { -src => YUI_BUILD_ROOT . '/paginator/assets/skins/sam/paginator.css' },
    { -src => YUI_BUILD_ROOT . '/datatable/assets/skins/sam/datatable.css' },
    { -src => CSS_DIR . '/style.css' }
];

my @js_src_yui;
my @js_src_code = ( { -src => 'form.js' } );

my %controller_context = (
    dbh          => $dbh,
    cgi          => $q,
    user_session => $s,
    js_src_yui   => \@js_src_yui,
    js_src_code  => \@js_src_code,
    title        => \$title
);

# this will be a reference to a subroutine that displays the main content
my $content;

# Action constants can evaluate to anything, but must be different from already defined actions.
# One can also use an enum structure to formally declare the input alphabet of all possible actions,
# but then the URIs would not be human-readable anymore.
# ===== User Management ==================================
# this is simply a prefix, FORM.WHATEVS does NOT do the function, just show input form.
use constant FORM           => 'form_';
use constant LOGIN          => 'login';
use constant LOGOUT         => 'logout';
use constant DEFAULT_ACTION => '';
use constant UPDATEPROFILE  => 'updateProfile';
use constant CHANGEPASSWORD => 'changePassword';
use constant CHANGEEMAIL    => 'changeEmail';
use constant RESETPASSWORD  => 'resetPassword';
use constant REGISTER       => 'registerUser';
use constant VERIFYEMAIL    => 'verifyEmail';
use constant QUIT           => 'quit';
use constant SHOWSCHEMA     => 'showSchema';
use constant HELP           => 'help';
use constant ABOUT          => 'about';

# map actions ('?a=' URL parameter) to modules
my %dispatch_table = (

    # :TODO:08/07/2011 20:39:03:es: come up with nouns to replace verbs for
    # better REST conformance
    #
    # verbs
    uploadAnnot        => 'SGX::UploadAnnot',
    uploadData         => 'SGX::UploadData',
    chooseProject      => 'SGX::ChooseProject',
    outputData         => 'SGX::OutputData',
    compareExperiments => 'SGX::CompareExperiments',
    findProbes         => 'SGX::FindProbes',
    getTFS             => 'SGX::TFSDisplay',

    # nouns
    platforms   => 'SGX::ManagePlatforms',
    projects    => 'SGX::ManageProjects',
    studies     => 'SGX::ManageStudies',
    experiments => 'SGX::ManageExperiments',
);

my $loadModule;

my $action =
  ( defined( $q->url_param('a') ) ) ? $q->url_param('a') : DEFAULT_ACTION;

#---------------------------------------------------------------------------
#  This is our own super-cool custom dispatcher and dynamic loader
#---------------------------------------------------------------------------
my $module = $dispatch_table{$action};
if ( defined $module ) {
    $loadModule = eval {

        # convert Perl path to system path and load the file
        ( my $file = $module ) =~ s/::/\//g;
        require "$file.pm";    ## no critic
        $module->new(%controller_context);
    } or do {
        my $error = $@;
        croak
          "Error loading module $module. The message returned was:\n\n$error";
    };
    if ( $loadModule->dispatch_js() ) {
        $content = \&module_show_html;
        $action  = undef;                # final state
    }
    else {
        $action = FORM . LOGIN;
    }
}

#---------------------------------------------------------------------------
#  State machine loop -- this will be refactored so that this loop will not be
#  needed...
#---------------------------------------------------------------------------
while ( defined($action) ) {

    # :TRICKY:07/12/2011 14:51:01:es: always undefine $action at the end of
    # your case block, unless you're passing the execution to another case
    # block that will undefine $action on its own. If you don't undefine
    # $action, this loop will go on forever!
    switch ($action) {

    #---------------------------------------------------------------------------
    #  User stuff
    #---------------------------------------------------------------------------
        case FORM . LOGIN {
            if ( $s->is_authorized('unauth') ) {
                $action = DEFAULT_ACTION;
            }
            else {
                $title   = 'Login';
                $content = \&form_login;
                $action  = undef;          # final state
            }
        }
        case LOGIN {
            $s->authenticate( $q->param('username'), $q->param('password'),
                \$error_string );
            if ( $s->is_authorized('unauth') ) {
                require SGX::ChooseProject;
                my $chooseProj = SGX::ChooseProject->new(%controller_context);
                $chooseProj->init();
                $chooseProj->changeToCurrent();

                my $destination =
                  ( defined( $q->url_param('destination') ) )
                  ? uri_unescape( $q->url_param('destination') )
                  : undef;
                if (   defined($destination)
                    && $destination ne $q->url( -absolute => 1 )
                    && $destination !~ m/(?:&|\?|&amp;)a=$action(?:\z|&|#)/
                    && $destination !~
                    m/(?:&|\?|&amp;)a=form_$action(?:\z|&|#)/ )
                {

                    # will send a redirect header, so commit the session to data
                    # store now
                    $s->commit();

                    # if the user is heading to a specific placce, pass him/her
                    # along, otherwise continue to the main page (script_name)
                    # do not add nph=>1 parameter to redirect() because that
                    # will cause it to crash
                    print $q->redirect(
                        -uri    => $q->url( -base => 1 ) . $destination,
                        -status => 302,           # 302 Found
                        -cookie => $s->cookie_array()
                    );

                    # code will keep executing after redirect, so clean up and
                    # force the program to quit
                    $action = QUIT;
                }
                else {
                    $action = DEFAULT_ACTION;
                }
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case LOGOUT {
            if ( $s->is_authorized('unauth') ) {
                $s->destroy;
            }
            $action = DEFAULT_ACTION;
        }
        case FORM . RESETPASSWORD {
            if ( $s->is_authorized('unauth') ) {
                $action = FORM . CHANGEPASSWORD;
            }
            else {
                $title   = 'Reset Password';
                $content = \&form_resetPassword;
                $action  = undef;                  # final state
            }
        }
        case RESETPASSWORD {
            if ( $s->is_authorized('unauth') ) {
                $action = FORM . CHANGEPASSWORD;
            }
            else {
                if (
                    $s->reset_password(
                        username     => $q->param('username'),
                        project_name => PROJECT_NAME,
                        login_uri    => $q->url( -full => 1 ) . '?a=' 
                          . FORM
                          . CHANGEPASSWORD,
                        error => \$error_string
                    )
                  )
                {
                    $title   = 'Reset Password';
                    $content = \&resetPassword_success;
                    $action  = undef;                     # final state
                }
                else {
                    $action = FORM . RESETPASSWORD;
                }
            }
        }
        case FORM . CHANGEPASSWORD {
            if ( $s->is_authorized('unauth') ) {
                $title   = 'Change Password';
                $content = \&form_changePassword;
                $action  = undef;                         # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case CHANGEPASSWORD {
            if ( $s->is_authorized('unauth') ) {
                my $old_password =
                  ( defined $q->param('old_password') )
                  ? $q->param('old_password')
                  : undef;
                if (
                    $s->change_password(
                        old_password  => $old_password,
                        new_password1 => $q->param('new_password1'),
                        new_password2 => $q->param('new_password2'),
                        error         => \$error_string
                    )
                  )
                {
                    $title   = 'Change Password';
                    $content = \&changePassword_success;
                    $action  = undef;                      # final state
                }
                else {
                    $action = FORM . CHANGEPASSWORD;
                }
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case FORM . CHANGEEMAIL {
            if ( $s->is_authorized('unauth') ) {
                $title   = 'Change Email';
                $content = \&form_changeEmail;
                $action  = undef;                # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case CHANGEEMAIL {
            if ( $s->is_authorized('unauth') ) {
                if (
                    $s->change_email(
                        password     => $q->param('password'),
                        email1       => $q->param('email1'),
                        email2       => $q->param('email2'),
                        project_name => PROJECT_NAME,
                        login_uri    => $q->url( -full => 1 ) . '?a='
                          . VERIFYEMAIL,
                        error => \$error_string
                    )
                  )
                {
                    $title   = 'Change Email';
                    $content = \&changeEmail_success;
                    $action  = undef;                   # final state
                }
                else {
                    $action = FORM . CHANGEEMAIL;
                }
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case FORM . REGISTER {
            if ( $s->is_authorized('unauth') ) {
                $action = DEFAULT_ACTION;
            }
            else {
                $title   = 'Sign up';
                $content = \&form_registerUser;
                $action  = undef;                 # final state
            }
        }
        case REGISTER {
            if ( $s->is_authorized('unauth') ) {
                $action = DEFAULT_ACTION;
            }
            else {
                if (
                    $s->register_user(
                        username     => $q->param('username'),
                        password1    => $q->param('password1'),
                        password2    => $q->param('password2'),
                        email1       => $q->param('email1'),
                        email2       => $q->param('email2'),
                        full_name    => $q->param('full_name'),
                        address      => $q->param('address'),
                        phone        => $q->param('phone'),
                        project_name => PROJECT_NAME,
                        login_uri    => $q->url( -full => 1 ) . '?a='
                          . VERIFYEMAIL,
                        error => \$error_string
                    )
                  )
                {
                    $title   = 'Registration';
                    $content = \&registration_success;
                    $action  = undef;                    # final state
                }
                else {
                    $action = FORM . REGISTER;
                }
            }
        }
        case FORM . UPDATEPROFILE {
            if ( $s->is_authorized('unauth') ) {
                $title   = 'My Profile';
                $content = \&form_updateProfile;
                $action  = undef;                        # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case UPDATEPROFILE {
            $action = DEFAULT_ACTION;
        }
        case VERIFYEMAIL {
            if ( $s->is_authorized('unauth') ) {
                my $t = SGX::Session::Session->new(
                    dbh       => $dbh,
                    expire_in => 3600 * 48,
                    check_ip  => 0
                );
                if ( $t->restore( $q->param('sid') ) ) {
                    if ( $s->verify_email( $t->{session_stash}->{username} ) ) {
                        $title   = 'Email Verification';
                        $content = \&verifyEmail_success;
                        $action  = undef;                   # final state
                    }
                    else {
                        $action = DEFAULT_ACTION;
                    }
                    $t->destroy();
                }
                else {

                    # no session tied
                    $action = DEFAULT_ACTION;
                }
            }
            else {
                $action = FORM . LOGIN;
            }
        }

    #---------------------------------------------------------------------------
    #  Protected static pages
    #---------------------------------------------------------------------------
        case SHOWSCHEMA {
            if ( $s->is_authorized('user') ) {
                $title   = 'Database Schema';
                $content = \&schema;
                $action  = undef;               # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }

    #---------------------------------------------------------------------------
    #  Public static pages
    #---------------------------------------------------------------------------
        case HELP {

            # :TODO:08/04/2011 12:29:39:es: Not using Wiki anymore -- correct
            # this.

            # will send a redirect header, so commit the session to data store
            $s->commit();
            print $q->redirect(
                -uri    => $q->url( -base => 1 ) . './html/wiki/',
                -status => 302,           # 302 Found
                -cookie => $s->cookie_array()
            );
            $action = QUIT;
        }
        case ABOUT {
            $title   = 'About';
            $content = \&about_text;
            $action  = undef;          # final state
        }
        case QUIT {

            # perform cleanup and stop execution
            $dbh->disconnect;
            exit;
        }
        else {

            # default action -- DEFAULT_ACTION redirects here
            $title   = 'Main';
            $content = \&main_text;
            $action  = undef;         # final state
        }
    }
}

$s->commit();          # flushes the session data and prepares cookies
$dbh->disconnect();    # do not disconnect before session data are committed

#######################################################################################

# :TODO:08/07/2011 18:56:16:es: Currently the single point of output rule only
# applies to HTTP response body (the formed HTML). It would be desirable to
# make changes to existing code to have the same behavior apply to response
# headers.

# This is the only statement in the entire application that prints HTML body.
print(

    # HTTP response header
    $q->header( -type => 'text/html', -cookie => $s->cookie_array() ),

    # HTTP response body
    (
        cgi_start_html(),
        content_header(),

        # -- do not delete line below -- useful for debugging cookie sessions
        SGX::Debug::dump_cookies_sent_to_user($s),
        $q->div( { -id => 'content' }, &$content() ),
        content_footer(),
        cgi_end_html()
    )
);

#######################################################################################
sub cgi_start_html {

# to add plain javascript code to the header, add the following to the -script array:
# {-type=>'text/javasccript', -code=>$JSCRIPT}
    my @js;
    foreach (@js_src_yui) {
        push @js,
          { -type => 'text/javascript', -src => YUI_BUILD_ROOT . '/' . $_ };
    }
    foreach (@js_src_code) {
        $_->{-type} = 'text/javascript';
        if ( defined( $_->{-src} ) ) {
            $_->{-src} = JS_DIR . '/' . $_->{-src};
        }
        push @js, $_;
    }

    return $q->start_html(
        -title  => PROJECT_NAME . " : $title",
        -style  => $css,
        -script => \@js,
        -class  => 'yui-skin-sam',
        -head   => [
            $q->Link(
                {
                    -type => 'image/x-icon',
                    -href => IMAGES_DIR . '/favicon.ico',
                    -rel  => 'icon'
                }
            ),
            $q->meta(
                {
                    -http_equiv => 'Content-Script-Type',
                    -content    => 'text/javascript'
                }
            ),
            $q->meta(
                {
                    -http_equiv => 'Content-Style-Type',
                    -content    => 'text/css'
                }
            )
        ]
    );
}
#######################################################################################
sub cgi_end_html {

    return $q->end_html;
}
#######################################################################################
sub content_header {
    my $menu_links = build_menu();
    return $q->div(
        { -id => 'header' },
        $q->h1(
            $q->a(
                {
                    -href => $q->url( -absolute => 1 ) . '?a=' . DEFAULT_ACTION,
                    -title => 'Segex home'
                },
                $q->img(
                    {
                        src    => IMAGES_DIR . '/logo.png',
                        width  => 448,
                        height => 108,
                        alt    => PROJECT_NAME,
                        title  => PROJECT_NAME
                    }
                )
            )
        ),
        $q->ul( { -id => 'sidemenu' }, $q->li( build_sidemenu() ) )
      ),
      $q->div(
        { -id => 'menu' },
        map {
            my $links = $menu_links->{$_};
            if (@$links) {
                $q->div( $q->h3($_), $q->ul( $q->li($links) ) );
            }
            else {
                '';
            }
          } keys %$menu_links
      );
}
#######################################################################################
sub form_error {

    # wraps an error message into a <div id='errormsg'> and <p> elements
    # for use in forms
    my $error = shift;
    if ( defined($error) && $error ) {
        return $q->div( { -id => 'errormsg' }, $q->p($error) );
    }
    else {
        return '';
    }
}
#######################################################################################
sub form_login {
    my $uri = $q->url( -absolute => 1, -query => 1 );

    # do not want to logout immediately after login
    $uri = $q->url( -absolute => 1 )
      if $uri =~ m/(?:&|\?|&amp;)a=${\LOGOUT}(?:\z|&|#)/;
    my $destination =
      ( defined( $q->url_param('destination') ) )
      ? $q->url_param('destination')
      : uri_escape($uri);

    return $q->start_form(
        -method => 'POST',
        -action => $q->url( -absolute => 1 ) . '?a=' 
          . LOGIN
          . '&amp;destination='
          . $destination,
        -onsubmit =>
          'return validate_fields(this, [\'username\',\'password\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'username' }, 'Your login id:' ) ),
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
            form_error($error_string),
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
                    -href => $q->url( -absolute => 1 ) . '?a=' 
                      . FORM
                      . RESETPASSWORD,
                    -title => 'Click here if you forgot your password.'
                },
                'I Forgot My Password'
            )
        )
      ),
      $q->end_form;
}
#######################################################################################
sub form_resetPassword {
    return $q->start_form(
        -method   => 'POST',
        -action   => $q->url( -absolute => 1 ) . '?a=' . RESETPASSWORD,
        -onsubmit => 'return validate_fields(this, [\'username\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'username' }, 'Your login id:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'username',
                -id    => 'username',
                -title => 'Enter your login id'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
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
#######################################################################################
sub resetPassword_success {
    return $q->p( $s->reset_password_text() );
}
#######################################################################################
sub registration_success {
    return $q->p( $s->register_user_text() );
}
#######################################################################################
sub form_changePassword {

    # user has to be logged in
    my $require_old = !defined( $s->{session_stash}->{change_pwd} );
    return $q->start_form(
        -method   => 'POST',
        -action   => $q->url( -absolute => 1 ) . '?a=' . CHANGEPASSWORD,
        -onsubmit => sprintf(
'return validate_fields(this, [\'old_password\',\'new_password1\',\'new_password2\']);'

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
                -name      => 'new_password1',
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
                -name      => 'new_password2',
                -id        => 'new_password2',
                -maxlength => 40,
                -title     => 'Type the new password again to confirm it'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(
                -name  => 'changePassword',
                -id    => 'changePassword',
                -class => 'button black bigrounded',
                -value => 'Change password',
                -title => 'Click to change your current password to the new one'
            )
        )
      ),
      $q->end_form;
}
#######################################################################################
sub changePassword_success {
    return $q->p(
        'Success! Your password has been changed to the new one you provided.'
    );
}
#######################################################################################
sub verifyEmail_success {
    return $q->p('Success! You email address has been verified.');
}
#######################################################################################
sub form_changeEmail {

    # user has to be logged in
    return $q->h2('Change Email Address'),
      $q->start_form(
        -method => 'POST',
        -action => $q->url( -absolute => 1 ) . '?a=' . CHANGEEMAIL,
        -onsubmit =>
          'return validate_fields(this, [\'password\',\'email1\',\'email2\']);'
      ),
      $q->dl(
        $q->dt('Password:'),
        $q->dd(
            $q->password_field(
                -name      => 'password',
                -id        => 'password',
                -maxlength => 40,
                -title     => 'Enter your current user password'
            )
        ),
        $q->dt('New Email Address:'),
        $q->dd(
            $q->textfield(
                -name  => 'email1',
                -id    => 'email1',
                -title => 'Enter your new email address'
            )
        ),
        $q->dt('Confirm New Address:'),
        $q->dd(
            $q->textfield(
                -name  => 'email2',
                -id    => 'email2',
                -title => 'Confirm your new email address'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(
                -name  => 'changeEmail',
                -id    => 'changeEmail',
                -class => 'button black bigrounded',
                -value => 'Change email',
                -title => 'Submit form'
            )
        )
      ),
      $q->end_form;
}
#######################################################################################
sub changeEmail_success {
    return $q->p( $s->change_email_text() );
}
#######################################################################################
sub form_updateProfile {

    my $url_absolute = $q->url( -absolute => 1 );
    return $q->h2('My Profile'),
      (
        ( $s->is_authorized('user') )
        ? $q->p(
            $q->a(
                {
                    -href  => $url_absolute . '?a=chooseProject',
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
                -href  => $url_absolute . '?a=' . FORM . CHANGEPASSWORD,
                -title => 'Change Password'
            },
            'Change Password'
        )
      ),
      $q->p(
        $q->a(
            {
                -href  => $url_absolute . '?a=' . FORM . CHANGEEMAIL,
                -title => 'Change Email'
            },
            'Change Email'
        )
      );
}
#######################################################################################
sub form_registerUser {

    # user cannot be logged in
    return $q->start_form(
        -method => 'POST',
        -action => $q->url( absolute => 1 ) . '?a=' . REGISTER,
        -onsubmit =>
'return validate_fields(this, [\'username\',\'password1\',\'password2\',\'email1\',\'email2\',\'full_name\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'username' }, 'Username:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'username',
                -id    => 'username',
                -title => 'Enter your future login id'
            )
        ),
        $q->dt( $q->label( { -for => 'password1' }, 'Password:' ) ),
        $q->dd(
            $q->password_field(
                -name      => 'password1',
                -id        => 'password1',
                -maxlength => 40,
                -title     => 'Enter your future password'
            )
        ),
        $q->dt( $q->label( { -for => 'password2' }, 'Confirm Password:' ) ),
        $q->dd(
            $q->password_field(
                -name      => 'password2',
                -id        => 'password2',
                -maxlength => 40,
                -title     => 'Type your password again for confirmation'
            )
        ),
        $q->dt( $q->label( { -for => 'email1' }, 'Email:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'email1',
                -id    => 'email1',
                -title => 'Enter your email address here (must be valid)'
            )
        ),
        $q->dt( $q->label( { -for => 'email2' }, 'Confirm Email:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'email2',
                -id    => 'email2',
                -title => 'Type your email address again for confirmation'
            )
        ),
        $q->dt( $q->label( { -for => 'full_name' }, 'Full Name:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'full_name',
                -id    => 'full_name',
                -title => 'Enter your first and last names here (optional)'
            )
        ),
        $q->dt( $q->label( { -for => 'address' }, 'Address:' ) ),
        $q->dd(
            $q->textarea(
                -name    => 'address',
                -id      => 'address',
                -rows    => 10,
                -columns => 50,
                -title   => 'Enter your contact address (optional)'
            )
        ),
        $q->dt( $q->label( { -for => 'phone' }, 'Contact Phone:' ) ),
        $q->dd(
            $q->textfield(
                -name  => 'phone',
                -id    => 'phone',
                -title => 'Enter your contact phone number (optional)'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
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
#######################################################################################
sub content_footer {
    return $q->div(
        { -id => 'footer' },
        $q->ul(
            $q->li(
                $q->a(
                    {
                        -href  => 'http://www.bu.edu/',
                        -title => 'Boston University'
                    },
                    'Boston University'
                )
            ),
            $q->li( 'SEGEX version : ' . $softwareVersion )
        )
    );
}

#######################################################################################
sub schema {
    return $q->img(
        {
            src    => IMAGES_DIR . '/schema.png',
            width  => 720,
            height => 720,
            usemap => '#schema_Map',
            id     => 'schema'
        }
    );
}

#######################################################################################
sub module_show_html {
    return $loadModule->dispatch();
}

#===  FUNCTION  ================================================================
#         NAME:  build_side_menu
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_sidemenu {
    my @menu;
    my $url_prefix = $q->url( -absolute => 1 );
    if ( $s->is_authorized('unauth') ) {

        my $proj_name = $s->{session_cookie}->{proj_name};
        my $curr_proj = $s->{session_cookie}->{curr_proj};
        if ( defined($curr_proj) and $curr_proj ne '' ) {
            $proj_name =
              $q->a( { -href => "$url_prefix?a=projects&b=edit&id=$curr_proj" },
                $proj_name );
        }
        else {
            $proj_name = 'All Projects';
        }

        # add unauth options
        push @menu,
          $q->span( { -style => 'color:#999' },
            'Logged in as ' . $s->{session_cookie}->{full_name} );
        push @menu,
          $q->span(
            { -style => 'color:#999' },
            "Current Project: $proj_name ("
              . $q->a( { -href => "$url_prefix?a=chooseProject" }, 'change' )
              . ')'
          );
        push @menu,
          $q->a(
            {
                -href  => "$url_prefix?a=" . FORM . UPDATEPROFILE,
                -title => 'My user profile.'
            },
            'My Profile'
          )
          . $q->span( { -class => 'separator' }, ' / ' )
          . $q->a(
            {
                -href  => "$url_prefix?a=" . LOGOUT,
                -title => 'You are signed in as '
                  . $s->{session_stash}->{username}
                  . '. Click on this link to log out.'
            },
            'Log out'
          );
    }
    else {

        # add top options for anonymous users
        push @menu,
          $q->a(
            {
                -href  => "$url_prefix?a=" . FORM . LOGIN,
                -title => 'Log in'
            },
            'Log in'
          )
          . $q->span( { -class => 'separator' }, ' / ' )
          . $q->a(
            {
                -href  => "$url_prefix?a=" . FORM . REGISTER,
                -title => 'Set up a new account'
            },
            'Sign up'
          );
    }
    push @menu,
      $q->a(
        {
            -href  => "$url_prefix?a=" . ABOUT,
            -title => 'About this site'
        },
        'About'
      );
    push @menu,
      $q->a(
        {
            -href   => "$url_prefix?a=" . HELP,
            -title  => 'Help pages',
            -target => 'new'
        },
        'Help'
      );
    return \@menu;
}

#===  FUNCTION  ================================================================
#         NAME:  about_text
#      PURPOSE:  Show About page content
#   PARAMETERS:  $q - CGI.pm object
#                showSchema => $showSchema - action to display schema
#      RETURNS:  array of strings formed using CGI object
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub about_text {
    my (%param) = @_;
    return $q->h2('About'),
      $q->p(
'The mammalian liver functions in the stress response, immune response, drug metabolism and protein synthesis. Sex-dependent responses to hepatic stress are mediated by pituitary secretion of growth hormone (GH) and the GH-responsive nuclear factors STAT5a, STAT5b and HNF4-alpha. Whole-genome expression arrays were used to examine sexually dimorphic gene expression in mouse livers.'
      ),
      $q->p(
'This SEGEX database provides public access to previously released datasets from the Waxman laboratory, and provides data mining tools and data visualization to query gene expression across several studies and experimental conditions.'
      ),
      $q->p(
'Developed at Boston University as part of the BE768 Biologic Databases course, Spring 2009, G. Benson instructor. Student developers: Anna Badiee, Eugene Scherba, Katrina Steiling and Niraj Trivedi. Faculty advisor: David J. Waxman.'
      ),
      $q->p(
        $q->a(
            { -href => $q->url( -absolute => 1 ) . '?a=' . SHOWSCHEMA },
            'View database schema'
        )
      );
}

#===  FUNCTION  ================================================================
#         NAME:  main_text
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub main_text {
    my (%param) = @_;
    return $q->p(
'The SEGEX database will provide public access to previously released datasets from the Waxman laboratory, and data mining and visualization modules to query gene expression across several studies and experimental conditions.'
      ),
      $q->p(
'This database was developed at Boston University as part of the BE768 Biological Databases course, Spring 2009, G. Benson instructor. Student developers: Anna Badiee, Eugene Scherba, Katrina Steiling and Niraj Trivedi. Faculty advisor: David J. Waxman.'
      );
}

#===  FUNCTION  ================================================================
#         NAME:  build_menu
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Builds the data structure containing main site links under
#                three different categories.
#
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_menu {
    my ( $view, $upload, $manage ) = ( 'Query', 'Upload', 'Manage' );
    my %menu;
    my $menu_t = tie(
        %menu, 'Tie::IxHash',
        $view   => [],
        $manage => [],
        $upload => []
    );
    my $url_prefix = $q->url( -absolute => 1 );

    # add user options
    return \%menu unless $s->is_authorized('user');

    # Query
    push @{ $menu{$view} },
      (
        $q->a(
            {
                -href  => $url_prefix . '?a=compareExperiments',
                -title => 'Compare multiple experiments for significant probes'
            },
            'Compare Experiments'
        ),
        $q->a(
            {
                -href => $url_prefix . '?a=findProbes',
                -title =>
'Search for probes by probe ids, gene symbols, accession numbers'
            },
            'Find Probes'
        ),
        $q->a(
            {
                -href  => $url_prefix . '?a=outputData',
                -title => 'Output Data'
            },
            'Output Data'
        )
      );

    # Manage
    push @{ $menu{$manage} },
      (
        $q->a(
            {
                -href  => $url_prefix . '?a=platforms',
                -title => 'Manage Platforms'
            },
            'Manage Platforms'
        ),
        $q->a(
            {
                -href  => $url_prefix . '?a=experiments',
                -title => 'Manage Experiments'
            },
            'Manage Experiments'
        ),
        $q->a(
            {
                -href  => $url_prefix . '?a=studies',
                -title => 'Manage Studies'
            },
            'Manage Studies'
        ),
        $q->a(
            {
                -href  => $url_prefix . '?a=projects',
                -title => 'Manage Projects'
            },
            'Manage Projects'
        )
      );

    # Upload
    push @{ $menu{$upload} },
      (
        $q->a(
            {
                -href  => $url_prefix . '?a=uploadData',
                -title => 'Upload data to a new experiment'
            },
            'Upload Data'
        ),
        $q->a(
            {
                -href  => $url_prefix . '?a=uploadAnnot',
                -title => 'Upload probe annotations'
            },
            'Upload Annotation'
        )
      );

    # add admin options
    #if ($s->is_authorized('admin')) {
    #}

    return \%menu;
}


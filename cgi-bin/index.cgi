#!/usr/bin/perl -wT

use strict;
use warnings;

# CGI options: -nosticky option prevents CGI.pm from printing hidden .cgifields
# inside a form. We do not add qw/:standard/ because we use object-oriented
# style.
use CGI 2.47 qw/-nosticky -private_tempfiles/;

#use CGI::Pretty 2.47 qw/-nosticky/;
use Switch;
use URI::Escape;
use Carp;
use Tie::IxHash;

#use Time::HiRes qw/clock/;
use Data::Dumper;

#---------------------------------------------------------------------------
# Custom modules in SGX directory
#---------------------------------------------------------------------------
use lib qw/./;

use SGX::Debug;     # all debugging code goes here
use SGX::Config;    # all configuration for our project goes here

use SGX::Session::User 0.07;       # user authentication, sessions and cookies
use SGX::Session::Session 0.08;    # email verification
use SGX::ManagePlatforms;
use SGX::ManageProjects;
use SGX::ManageStudies;
use SGX::ManageExperiments;
use SGX::OutputData;
use SGX::TFSDisplay;
use SGX::FindProbes;
use SGX::ChooseProject;
use SGX::CompareExperiments;
use SGX::UploadData;
use SGX::UploadAnnot;

#---------------------------------------------------------------------------
#  User Authentication
#---------------------------------------------------------------------------
my $softwareVersion = '0.2.4';

my $dbh = sgx_db_connect();
my $s   = SGX::Session::User->new(
    dbh       => $dbh,
    expire_in => 3600,    # expire in 3600 seconds (1 hour)
    check_ip  => 1
);

$s->restore();            # restore old session if it exists

#---------------------------------------------------------------------------
#  Main
#---------------------------------------------------------------------------
my $q = CGI->new();
my $error_string;
my $title;
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
    js_src_code  => \@js_src_code
);

# this will be a reference to a subroutine that displays the main content
my $content;

# Action constants can evaluate to anything, but must be different from already defined actions.
# One can also use an enum structure to formally declare the input alphabet of all possible actions,
# but then the URIs would not be human-readable anymore.
# ===== User Management ==================================
# this is simply a prefix, FORM.WHATEVS does NOT do the function, just show input form.
use constant FORM              => 'form_';
use constant LOGIN             => 'login';
use constant LOGOUT            => 'logout';
use constant DEFAULT_ACTION    => '';
use constant UPDATEPROFILE     => 'updateProfile';
use constant MANAGEPLATFORMS   => 'managePlatforms';
use constant MANAGEPROJECTS    => 'manageProjects';
use constant MANAGESTUDIES     => 'manageStudies';
use constant MANAGEEXPERIMENTS => 'manageExperiments';
use constant OUTPUTDATA        => 'outputData';
use constant CHANGEPASSWORD    => 'changePassword';
use constant CHANGEEMAIL       => 'changeEmail';
use constant CHOOSEPROJECT     => 'chooseProject';
use constant RESETPASSWORD     => 'resetPassword';
use constant REGISTER          => 'registerUser';
use constant VERIFYEMAIL       => 'verifyEmail';
use constant QUIT              => 'quit';

#use constant DUMP               => 'dump';
use constant DOWNLOADTFS        => 'getTFS';
use constant SHOWSCHEMA         => 'showSchema';
use constant HELP               => 'help';
use constant ABOUT              => 'about';
use constant COMPAREEXPERIMENTS => 'compareExperiments';    # submit button text
use constant FINDPROBES         => 'findProbes';            # submit button text
use constant UPLOADANNOT        => 'uploadAnnot';
use constant UPLOADDATA         => 'uploadData';

my $loadModule;

# :TRICKY:08/02/2011 13:10:53:es: need to use url_param instead of param here
# for successful login -- why?
my $action =
  ( defined( $q->url_param('a') ) ) ? $q->url_param('a') : DEFAULT_ACTION;

while ( defined($action) ) {

    # :TRICKY:07/12/2011 14:51:01:es: always undefine $action at the end of
    # your case block, unless you're passing the execution to another case
    # block that will undefine $action on its own. If you don't undefine
    # $action, this loop will go on forever!
    switch ($action) {

    #---------------------------------------------------------------------------
    #  Everything that uses %controller_context
    #---------------------------------------------------------------------------
        case UPLOADANNOT {
            $loadModule = SGX::UploadAnnot->new(%controller_context);
            if ( $loadModule->dispatch_js() ) {
                $content = \&module_show_html;
                $title   = 'Upload Annotations';
                $action  = undef;                  # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case UPLOADDATA {
            $loadModule = SGX::UploadData->new(%controller_context);

            if ( $loadModule->dispatch_js() ) {
                $content = \&module_show_html;
                $title   = 'Upload Data';
                $action  = undef;                  # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case CHOOSEPROJECT {
            $loadModule = SGX::ChooseProject->new(%controller_context);
            if ( $loadModule->dispatch_js() ) {
                $content = \&module_show_html;
                $title   = 'Change Project';
                $action  = undef;                  # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case MANAGEPLATFORMS {
            $loadModule = SGX::ManagePlatforms->new(%controller_context);
            if ( $loadModule->dispatch_js() ) {
                $content = \&module_show_html;
                $title   = 'Platforms';
                $action  = undef;                  # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case MANAGEPROJECTS {
            $loadModule = SGX::ManageProjects->new(%controller_context);
            if ( $loadModule->dispatch_js() ) {
                $content = \&module_show_html;
                $title   = 'Projects';
                $action  = undef;                  # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case MANAGESTUDIES {
            $loadModule = SGX::ManageStudies->new(%controller_context);
            if ( $loadModule->dispatch_js() ) {
                $content = \&module_show_html;
                $title   = 'Studies';
                $action  = undef;                  # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case MANAGEEXPERIMENTS {
            $loadModule = SGX::ManageExperiments->new(%controller_context);
            if ( $loadModule->dispatch_js() ) {
                $content = \&module_show_html;
                $title   = 'Experiments';
                $action  = undef;                  # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case OUTPUTDATA {
            $loadModule = SGX::OutputData->new(%controller_context);
            if ( $loadModule->dispatch_js() ) {
                $content = \&module_show_html;
                $title   = 'Output Data';
                $action  = undef;                  # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case COMPAREEXPERIMENTS {
            $loadModule = SGX::CompareExperiments->new(%controller_context);
            if ( $loadModule->dispatch_js() ) {
                $title   = 'Compare Experiments';
                $content = \&module_show_html;
                $action  = undef;
            }
            else {
                $action = FORM . LOGIN;    # final state
            }
        }
        case FINDPROBES {
            $loadModule = SGX::FindProbes->new(%controller_context);
            if ( $loadModule->dispatch_js() ) {
                $title   = 'Find Probes';
                $content = \&module_show_html;
                $action  = undef;                # final state
            }
            else {
                $action = FORM . LOGIN;
            }
        }
        case DOWNLOADTFS {

            # :TODO:08/04/2011 12:25:51:es: refactor this to use
            # %controller_context
            if ( $s->is_authorized('user') ) {
                $title = 'View Slice';

                push @js_src_yui,
                  (
                    'yahoo-dom-event/yahoo-dom-event.js',
                    'element/element-min.js',
                    'paginator/paginator-min.js',
                    'datasource/datasource-min.js',
                    'datatable/datatable-min.js',
                    'yahoo/yahoo.js'
                  );
                push @js_src_code, { -code => show_tfs_js() };

                $content = \&show_tfs;
                $action  = undef;
            }
            else {
                $action = FORM . LOGIN;
            }
        }

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
                if (
                    $s->change_password(
                        old_password  => $q->param('old_password'),
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
                if ( $t->recover( $q->param('sid') ) ) {
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
            $content = \&about;
            $action  = undef;     # final state
        }
        case QUIT {

            # perform cleanup and stop execution
            $dbh->disconnect;
            exit;
        }
        else {

            # default action -- DEFAULT_ACTION redirects here
            $title   = 'Main';
            $content = \&main;
            $action  = undef;    # final state
        }
    }
}

# flush the session data and prepare the cookie
$s->commit();

# ===== HTML =============================================================

# Normally we can set more than one cookie like this:
# print header(-type=>'text/html',-cookie=>[$cookie1,$cookie2]);
# But because the session object takes over the array, have to do it this way:
#   push @SGX::Session::User::cookies, $cookie2;
# ... and then send the \@SGX::Session::User::cookies array reference to CGI::header() for example.

my $menu_links = build_menu();

print $q->header( -type => 'text/html', -cookie => $s->cookie_array() ),
  cgi_start_html(),
  $q->div(
    { -id => 'header' },
    $q->h1(
        $q->a(
            {
                -href  => $q->url( -absolute => 1 ) . '?a=' . DEFAULT_ACTION,
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

print '<div id="content">';

#---------------------------------------------------------------------------
#  Don't delete commented-out block below: it is meant to be used for
#  debugging user sessions.
#---------------------------------------------------------------------------
#print $q->pre("
#cookies sent to user:
#".Dumper($s->cookie_array())."
#object stored in the \"sessions\" table in the database:
#".Dumper($s->{session_stash})."
#session expires after:    ".$s->{ttl}." seconds of inactivity
#");

# Main part
&$content();

### Ideally, would want to disconnect from the database before any HTML is printed
### but for the purpose of fast integration, putting this statement here.
$dbh->disconnect;

print '</div>';
print footer();
print cgi_end_html();

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
sub main {
    print SGX::Config::main_text($q);
    return 1;
}
#######################################################################################
sub about {
    print SGX::Config::about_text( $q, showSchema => SHOWSCHEMA );
    return 1;
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
    print $q->start_form(
        -method => 'POST',
        -action => $q->url( -absolute => 1 ) . '?a=' 
          . LOGIN
          . '&amp;destination='
          . $destination,
        -onsubmit =>
          'return validate_fields(this, [\'username\',\'password\']);'
      )
      . $q->dl(
        $q->dt( $q->label( { -for => 'username' }, 'Username:' ) ),
        $q->dd( $q->textfield( -name => 'username', -id => 'username' ) ),
        $q->dt( $q->label( { -for => 'password' }, 'Password:' ) ),
        $q->dd(
            $q->password_field(
                -name      => 'password',
                -id        => 'password',
                -maxlength => 40
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(
                -name  => 'login',
                -id    => 'login',
                -class => 'button black bigrounded',
                -value => 'Login'
            ),
            $q->span( { -class => 'separator' }, ' / ' ),
            $q->a(
                {
                    -href => $q->url( -absolute => 1 ) . '?a=' 
                      . FORM
                      . RESETPASSWORD,
                    -title => 'Email me a new password'
                },
                'I Forgot My Password'
            )
        )
      ) . $q->end_form;
    return;
}
#######################################################################################
sub form_resetPassword {
    print $q->start_form(
        -method   => 'POST',
        -action   => $q->url( -absolute => 1 ) . '?a=' . RESETPASSWORD,
        -onsubmit => 'return validate_fields(this, [\'username\']);'
      )
      . $q->dl(
        $q->dt('Username:'),
        $q->dd( $q->textfield( -name => 'username', -id => 'username' ) ),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(
                -name  => 'resetPassword',
                -id    => 'resetPassword',
                -class => 'button black bigrounded',
                -value => 'Email new password'
            ),
            $q->span( { -class => 'separator' }, ' / ' ),
            $q->a(
                {
                    -href  => $q->url( -absolute => 1 ) . '?a=' . FORM . LOGIN,
                    -title => 'Back to login page'
                },
                'Back'
            )
        )
      ) . $q->end_form;
    return;
}
#######################################################################################
sub resetPassword_success {
    print $q->p( $s->reset_password_text() )
      . $q->p(
        $q->a(
            {
                -href  => $q->url( -absolute => 1 ),
                -title => 'Back to login page'
            },
            'Back'
        )
      );
    return;
}
#######################################################################################
sub registration_success {
    print $q->p( $s->register_user_text() )
      . $q->p(
        $q->a(
            {
                -href  => $q->url( -absolute => 1 ),
                -title => 'Back to login page'
            },
            'Back'
        )
      );
    return;
}
#######################################################################################
sub form_changePassword {

    # user has to be logged in
    print $q->start_form(
        -method => 'POST',
        -action => $q->url( -absolute => 1 ) . '?a=' . CHANGEPASSWORD,
        -onsubmit =>
'return validate_fields(this, [\'old_password\',\'new_password1\',\'new_password2\']);'
      )
      . $q->dl(
        $q->dt('Old Password:'),
        $q->dd(
            $q->password_field(
                -name      => 'old_password',
                -id        => 'old_password',
                -maxlength => 40
            )
        ),
        $q->dt('New Password:'),
        $q->dd(
            $q->password_field(
                -name      => 'new_password1',
                -id        => 'new_password1',
                -maxlength => 40
            )
        ),
        $q->dt('Confirm New Password:'),
        $q->dd(
            $q->password_field(
                -name      => 'new_password2',
                -id        => 'new_password2',
                -maxlength => 40
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(
                -name  => 'changePassword',
                -id    => 'changePassword',
                -class => 'button black bigrounded',
                -value => 'Change password'
            ),
            $q->span( { -class => 'separator' }, ' / ' ),
            $q->a(
                {
                    -href => $q->url( -absolute => 1 ) . '?a=' 
                      . FORM
                      . UPDATEPROFILE,
                    -title => 'Back to my profile'
                },
                'Back'
            )
        )
      ) . $q->end_form;
    return;
}
#######################################################################################
sub changePassword_success {
    print $q->p('You have successfully changed your password.')
      . $q->p(
        $q->a(
            {
                -href => $q->url( -absolute => 1 ) . '?a=' 
                  . FORM
                  . UPDATEPROFILE,
                -title => 'Back to my profile'
            },
            'Back'
        )
      );
    return;
}
#######################################################################################
sub verifyEmail_success {
    print $q->p('You email address has been verified.')
      . $q->p(
        $q->a(
            {
                -href => $q->url( -absolute => 1 ) . '?a=' 
                  . FORM
                  . UPDATEPROFILE,
                -title => 'Back to my profile'
            },
            'Back'
        )
      );
    return;
}
#######################################################################################
sub form_changeEmail {

    # user has to be logged in
    print $q->h2('Change Email Address'),
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
                -maxlength => 40
            )
        ),
        $q->dt('New Email Address:'),
        $q->dd( $q->textfield( -name => 'email1', -id => 'email1' ) ),
        $q->dt('Confirm New Address:'),
        $q->dd( $q->textfield( -name => 'email2', -id => 'email2' ) ),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(
                -name  => 'changeEmail',
                -id    => 'changeEmail',
                -class => 'button black bigrounded',
                -value => 'Change email'
            ),
            $q->span( { -class => 'separator' }, ' / ' ),
            $q->a(
                {
                    -href => $q->url( -absolute => 1 ) . '?a=' 
                      . FORM
                      . UPDATEPROFILE,
                    -title => 'Back to my profile'
                },
                'Back'
            )
        )
      ),
      $q->end_form;
    return 1;
}
#######################################################################################
sub changeEmail_success {
    print $q->p( $s->change_email_text() )
      . $q->p(
        $q->a(
            {
                -href => $q->url( -absolute => 1 ) . '?a=' 
                  . FORM
                  . UPDATEPROFILE,
                -title => 'Back to my profile'
            },
            'Back'
        )
      );
    return;
}
#######################################################################################
sub form_updateProfile {

    # user has to be logged in
    print $q->h2('My Profile');

    if ( $s->is_authorized('user') ) {
        print $q->p(
            $q->a(
                {
                    -href  => $q->url( -absolute => 1 ) . '?a=' . CHOOSEPROJECT,
                    -title => 'Choose Project'
                },
                'Choose Project'
            )
        );
    }

    print $q->p(
        $q->a(
            {
                -href => $q->url( -absolute => 1 ) . '?a=' 
                  . FORM
                  . CHANGEPASSWORD,
                -title => 'Change Password'
            },
            'Change Password'
        )
      ),
      $q->p(
        $q->a(
            {
                -href => $q->url( -absolute => 1 ) . '?a=' . FORM . CHANGEEMAIL,
                -title => 'Change Email'
            },
            'Change Email'
        )
      );
    return;
}
#######################################################################################
sub form_registerUser {

    # user cannot be logged in
    print $q->start_form(
        -method => 'POST',
        -action => $q->url( absolute => 1 ) . '?a=' . REGISTER,
        -onsubmit =>
'return validate_fields(this, [\'username\',\'password1\',\'password2\',\'email1\',\'email2\',\'full_name\']);'
      )
      . $q->dl(
        $q->dt('Username:'),
        $q->dd( $q->textfield( -name => 'username', -id => 'username' ) ),
        $q->dt('Password:'),
        $q->dd(
            $q->password_field(
                -name      => 'password1',
                -id        => 'password1',
                -maxlength => 40
            )
        ),
        $q->dt('Confirm Password:'),
        $q->dd(
            $q->password_field(
                -name      => 'password2',
                -id        => 'password2',
                -maxlength => 40
            )
        ),
        $q->dt('Email:'),
        $q->dd( $q->textfield( -name => 'email1', -id => 'email1' ) ),
        $q->dt('Confirm Email:'),
        $q->dd( $q->textfield( -name => 'email2', -id => 'email2' ) ),
        $q->dt('Full Name:'),
        $q->dd( $q->textfield( -name => 'full_name', -id => 'full_name' ) ),
        $q->dt('Address:'),
        $q->dd(
            $q->textarea(
                -name    => 'address',
                -id      => 'address',
                -rows    => 10,
                -columns => 50
            )
        ),
        $q->dt('Phone:'),
        $q->dd( $q->textfield( -name => 'phone', -id => 'phone' ) ),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(
                -name  => 'registerUser',
                -id    => 'registerUser',
                -class => 'button black bigrounded',
                -value => 'Register'
            ),
            $q->span( { -class => 'separator' }, ' / ' ),
            $q->a(
                {
                    -href  => $q->url( -absolute => 1 ) . '?a=' . FORM . LOGIN,
                    -title => 'Back to login page'
                },
                'Back'
            )
        )
      ),
      $q->end_form;
    return;
}
#######################################################################################
sub footer {
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
    print $q->img(
        {
            src    => IMAGES_DIR . '/schema.png',
            width  => 720,
            height => 720,
            usemap => '#schema_Map',
            id     => 'schema'
        }
    );
    return 1;
}

#######################################################################################
#sub dump_table {
#
#    # prints out the entire table in tab-delimited format
#    #
#    my $table    = shift;
#    my $sth      = $dbh->prepare(qq{SELECT * FROM $table});
#    my $rowcount = $sth->execute();
#
#    # print the table head (fieldnames)
#    print join( "\t", @{ $sth->{NAME} } ), "\n";
#
#    # print the data itself
#    while ( my $row = $sth->fetchrow_arrayref ) {
#
#        # NULL elements become undefined -- replace those,
#        # otherwise the error_log will overfill with warnings
#        foreach (@$row) { $_ = '' unless defined; s/\t/ /; }
#        print join( "\t", @$row ), "\n";
#    }
#    $sth->finish;
#    return;
#}
#######################################################################################

sub show_tfs_js {

    if ( defined( $q->param('CSV') ) ) {
        $s->commit();
        my $TFSDisplay =
          SGX::TFSDisplay->new( $dbh, cgi => $q, user_session => $s );
        $TFSDisplay->loadDataFromSubmission();
        $TFSDisplay->getPlatformData();
        $TFSDisplay->loadAllData();
        return $TFSDisplay->displayTFSInfoCSV();
    }
    else {
        my $TFSDisplay =
          SGX::TFSDisplay->new( $dbh, cgi => $q, user_session => $s );
        $TFSDisplay->loadDataFromSubmission();
        $TFSDisplay->loadTFSData();
        return $TFSDisplay->displayTFSInfo();
    }
}
#######################################################################################

sub show_tfs {
    print '<h2 id="summary_caption"></h2>';
    print '<div><a id="summ_astext">View as plain text</a></div>';
    print '<div id="summary_table" class="table_cont"></div>';
    print '<h2 id="tfs_caption"></h2>';
    print '<div><a id="tfs_astext">View as plain text</a></div>';
    print '<div id="tfs_table" class="table_cont"></div>';
    return;
}
#######################################################################################
sub module_show_html {
    $loadModule->dispatch();
    return;
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
            $proj_name = $q->a(
                {
                    -href => "$url_prefix?a=manageProjects&b=edit&id=$curr_proj"
                },
                $proj_name
            );
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
              . $q->a( { -href => $url_prefix . '?a=' . CHOOSEPROJECT },
                'change' )
              . ')'
          );
        push @menu,
          $q->a(
            {
                -href  => $url_prefix . '?a=' . FORM . UPDATEPROFILE,
                -title => 'My user profile.'
            },
            'My Profile'
          )
          . $q->span( { -class => 'separator' }, ' / ' )
          . $q->a(
            {
                -href  => $url_prefix . '?a=' . LOGOUT,
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
                -href  => $url_prefix . '?a=' . FORM . LOGIN,
                -title => 'Log in'
            },
            'Log in'
          )
          . $q->span( { -class => 'separator' }, ' / ' )
          . $q->a(
            {
                -href => $q->url( -absolute => 1 ) . '?a=' . FORM . REGISTER,
                -title => 'Set up a new account'
            },
            'Sign up'
          );
    }
    push @menu,
      $q->a(
        {
            -href  => $url_prefix . '?a=' . ABOUT,
            -title => 'About this site'
        },
        'About'
      );
    push @menu,
      $q->a(
        {
            -href   => $url_prefix . '?a=' . HELP,
            -title  => 'Help pages',
            -target => 'new'
        },
        'Help'
      );
    return \@menu;
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
    if ( $s->is_authorized('user') ) {

        # view
        push @{ $menu{$view} },
          $q->a(
            {
                -href  => $url_prefix . '?a=' . COMPAREEXPERIMENTS,
                -title => 'Select samples to compare'
            },
            'Compare Experiments'
          );
        push @{ $menu{$view} },
          $q->a(
            {
                -href  => $url_prefix . '?a=' . FINDPROBES,
                -title => 'Search for probes'
            },
            'Find Probes'
          );
        push @{ $menu{$view} },
          $q->a(
            {
                -href  => $url_prefix . '?a=' . OUTPUTDATA,
                -title => 'Output Data'
            },
            'Output Data'
          );

        # upload
        push @{ $menu{$upload} },
          $q->a(
            {
                -href  => $url_prefix . '?a=' . UPLOADDATA,
                -title => 'Upload data to a new experiment'
            },
            'Upload Data'
          );
        push @{ $menu{$upload} },
          $q->a(
            {
                -href  => $url_prefix . '?a=' . UPLOADANNOT,
                -title => 'Upload Probe Annotations'
            },
            'Upload Annotation'
          );

        # manage
        push @{ $menu{$manage} },
          $q->a(
            {
                -href  => $url_prefix . '?a=' . MANAGEPLATFORMS,
                -title => 'Manage Platforms'
            },
            'Manage Platforms'
          );
        push @{ $menu{$manage} },
          $q->a(
            {
                -href  => $url_prefix . '?a=' . MANAGEPROJECTS,
                -title => 'Manage Projects'
            },
            'Manage Projects'
          );
        push @{ $menu{$manage} },
          $q->a(
            {
                -href  => $url_prefix . '?a=' . MANAGESTUDIES,
                -title => 'Manage Studies'
            },
            'Manage Studies'
          );
        push @{ $menu{$manage} },
          $q->a(
            {
                -href  => $url_prefix . '?a=' . MANAGEEXPERIMENTS,
                -title => 'Manage Experiments'
            },
            'Manage Experiments'
          );
    }

    # add admin options
    #if ($s->is_authorized('admin')) {
    #}

    return \%menu;
}


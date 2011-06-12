#!/usr/bin/perl -w

use strict;
use warnings;

#---------------------------------------------------------------------------
# Bundled modules 
#---------------------------------------------------------------------------

# CGI options: -nosticky option prevents CGI.pm from printing hidden 
# .cgifields inside a # form. We do not add qw/:standard/ because we use 
# object-oriented style.
#
use CGI 2.47 qw/-nosticky/;
use Switch;
use URI::Escape;
use Carp;
use Math::BigInt;
#use Time::HiRes qw/clock/;
use Data::Dumper;

#---------------------------------------------------------------------------
# Custom modules in SGX directory
#---------------------------------------------------------------------------
use lib 'SGX';

use SGX::Debug;        # all debugging code goes here
use SGX::Config;    # all configuration for our project goes here
use SGX::User 0.07;    # user authentication, sessions and cookies
use SGX::Session 0.08;    # email verification
use SGX::ManageMicroarrayPlatforms;
use SGX::ManageProjects;
use SGX::ManageStudies;
use SGX::ManageExperiments;
use SGX::OutputData;
use SGX::JavaScriptDeleteConfirm;
use SGX::TFSDisplay;
use SGX::FindProbes;
use SGX::ChooseProject;

#---------------------------------------------------------------------------
#  User Authentication
#---------------------------------------------------------------------------
my $softwareVersion = "0.1.12";
my $dbh = mysql_connect();
my $s = SGX::User->new(-handle        => $dbh,
               -expire_in    => 3600, # expire in 3600 seconds (1 hour)
               -check_ip    => 1,
               -cookie_name    => 'user');

$s->restore();    # restore old session if it exists


#---------------------------------------------------------------------------
#  Main
#---------------------------------------------------------------------------
my $q = CGI->new();
my $error_string;
my $title;
my $css = [
    {-src=>YUI_ROOT . '/build/reset-fonts/reset-fonts.css'},
    {-src=>YUI_ROOT . '/build/container/assets/skins/sam/container.css'},
    {-src=>YUI_ROOT . '/build/paginator/assets/skins/sam/paginator.css'},
    {-src=>YUI_ROOT . '/build/datatable/assets/skins/sam/datatable.css'},
    {-src=>CSS_DIR . '/style.css'}
];

my $js = [{-type=>'text/javascript',-src=>JS_DIR . '/prototype.js'},
      {-type=>'text/javascript',-src=>JS_DIR . '/form.js'}];

my $content;    # this will be a reference to a subroutine that displays the main content

#This is a reference to the manage platform module. Module gets instanstiated when visitng the page.
my $TFSDisplay;
my $findProbes;
my $ChooseProject;

# Action constants can evaluate to anything, but must be different from already defined actions.
# One can also use an enum structure to formally declare the input alphabet of all possible actions,
# but then the URIs would not be human-readable anymore.
# ===== User Management ==================================
use constant FORM            => 'form_';# this is simply a prefix, FORM.WHATEVS does NOT do the function, just show input form.
use constant LOGIN            => 'login';
use constant LOGOUT            => 'logout';
use constant DEFAULT_ACTION        => 'mainPage';
use constant UPDATEPROFILE        => 'updateProfile';
use constant MANAGEPLATFORMS        => 'managePlatforms';
use constant MANAGEPROJECTS        => 'manageProjects';
use constant MANAGESTUDIES        => 'manageStudies';
use constant MANAGEEXPERIMENTS        => 'manageExperiments';
use constant OUTPUTDATA            => 'outputData';
use constant CHANGEPASSWORD        => 'changePassword';
use constant CHANGEEMAIL        => 'changeEmail';
use constant CHOOSEPROJECT      => 'chooseProject';
use constant RESETPASSWORD        => 'resetPassword';
use constant REGISTERUSER        => 'registerUser';
use constant VERIFYEMAIL        => 'verifyEmail';
use constant QUIT            => 'quit';
use constant DUMP            => 'dump';
use constant DOWNLOADTFS        => 'getTFS';
use constant SHOWSCHEMA            => 'showSchema';
use constant HELP            => 'help';
use constant ABOUT            => 'about';
use constant COMPAREEXPERIMENTS        => 'Compare Selected';    # submit button text
use constant FINDPROBES            => 'Search';        # submit button text
use constant UPDATEPROBE        => 'updateCell';
use constant UPLOADANNOT        => 'uploadAnnot';

my $action = (defined($q->url_param('a'))) ? $q->url_param('a') : DEFAULT_ACTION;

while (defined($action)) { switch ($action) {
    # WARNING: always undefine $action at the end of your case block, unless you're passing
    # the execution to another case block that will undefine $action on its own. If you
    # don't undefine $action, this loop will go on forever!
    case FORM.UPLOADANNOT {
        # TODO: only admins should be allowed to perform this action
        if ($s->is_authorized('user')) {
            $title = 'Upload/Update Annotations';
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo-dom-event/yahoo-dom-event.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/animation/animation-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/dragdrop/dragdrop-min.js'};
            push @$js, {-type=>'text/javascript',-src=>JS_DIR . '/annot.js'};
            $content = \&form_uploadAnnot;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
     }
    case UPLOADANNOT {
        # TODO: only admins should be allowed to perform this action
        if ($s->is_authorized('user')) {
            $content = \&uploadAnnot;
            $title = 'Complete';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case FORM.CHOOSEPROJECT {
        if ($s->is_authorized('user')) {
            $title = 'Change Project';
            $content = \&chooseProject;
            $action = undef; # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case CHOOSEPROJECT {
        if ($s->is_authorized('user')) {
            my $project_set_to = $q->param('current_project');

            # store project information in the session: note that
            # this must be done before cookie is committed, which
            # must be done before anything is written
            $s->{object}->{curr_proj} = $project_set_to;
            $action = FORM.CHOOSEPROJECT;
        } else {
            $action = FORM.LOGIN;
        }
    }
    case UPDATEPROBE {
        # AJAX request
        if ($s->is_authorized('user')) {
            if (updateCell()) {
                print $q->header(-status=>200);
                exit(1);
            } else {
                print $q->header(-status=>404);
                exit(0);
            }
        } else {
            print $q->header(-status=>401);
            exit(0);
        }
    }
    case MANAGEPLATFORMS {
        if ($s->is_authorized('user')) {    
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo-dom-event/yahoo-dom-event.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/connection/connection-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/dragdrop/dragdrop-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/container/container-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/element/element-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datasource/datasource-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/paginator/paginator-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datatable/datatable-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/selector/selector-min.js'};
        
            $content = \&managePlatforms;
            $title = 'Platforms';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case MANAGEPROJECTS {
        if ($s->is_authorized('user')) {

            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo-dom-event/yahoo-dom-event.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/connection/connection-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/dragdrop/dragdrop-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/container/container-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/element/element-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datasource/datasource-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/paginator/paginator-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datatable/datatable-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/selector/selector-min.js'};

            $content = \&manageProjects;
            $title = 'Projects';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case MANAGESTUDIES {
        if ($s->is_authorized('user')) {

            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo-dom-event/yahoo-dom-event.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/connection/connection-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/dragdrop/dragdrop-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/container/container-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/element/element-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datasource/datasource-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/paginator/paginator-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datatable/datatable-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/selector/selector-min.js'};


            $content = \&manageStudies;

            $title = 'Studies';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case MANAGEEXPERIMENTS {
        if ($s->is_authorized('user')) {    
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo-dom-event/yahoo-dom-event.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/connection/connection-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/dragdrop/dragdrop-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/container/container-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/element/element-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datasource/datasource-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/paginator/paginator-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datatable/datatable-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/selector/selector-min.js'};

            $content = \&manageExperiments;
            $title = 'Experiments';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case OUTPUTDATA {
        if ($s->is_authorized('user')) {
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo-dom-event/yahoo-dom-event.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/connection/connection-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/dragdrop/dragdrop-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/container/container-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/element/element-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datasource/datasource-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/paginator/paginator-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datatable/datatable-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/selector/selector-min.js'};

            $content = \&outputData;
            $title = 'Output Data';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case FORM.FINDPROBES            {
        if ($s->is_authorized('user')) {
            $title = 'Find Probes';
            push @$js, {-type=>'text/javascript',-code=>'
Event.observe(window, "load", init);
function init() {
    sgx_toggle($("graph").checked, [\'graph_option_names\', \'graph_option_values\']);
}
'};
            $content = \&form_findProbes;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case FINDPROBES                {
        if ($s->is_authorized('user')) {
            $title = 'Find Probes';
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo-dom-event/yahoo-dom-event.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/connection/connection-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/dragdrop/dragdrop-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/container/container-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/element/element-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datasource/datasource-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/paginator/paginator-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datatable/datatable-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/selector/selector-min.js'};
            push @$js, {-type=>'text/javascript',-code=>findProbes_js()};
            $content = \&findProbes;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case DUMP                {
        if ($s->is_authorized('user')) {
            my $table = $q->param('table');
            #show data as a tab-delimited text file
            $s->commit();
            print $q->header(-type=>'text/plain', -cookie=>\@SGX::Cookie::cookies);
            dump_table($table);
            $action = QUIT;
        } else {
            $action = FORM.LOGIN;
        }
    }
    case DOWNLOADTFS            {
        if ($s->is_authorized('user')) {
            $title = 'View Slice';

            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo-dom-event/yahoo-dom-event.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/element/element-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/paginator/paginator-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datasource/datasource-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datatable/datatable.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo/yahoo.js'};
            push @$js, {-type=>'text/javascript',-code=>show_tfs_js()};

            $content = \&show_tfs;
            $action = undef;
        } else {
            $action = FORM.LOGIN;
        }
    }
    case SHOWSCHEMA            {
        if ($s->is_authorized('user')) {
            $title = 'Database Schema';
            $content = \&schema;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case HELP            {
        # will send a redirect header, so commit the session to data store now
        $s->commit();
        print $q->redirect(-uri        => $q->url(-base=>1).'./html/wiki/',
                   -status    => 302,     # 302 Found
                   -cookie    => \@SGX::Cookie::cookies);
        $action = QUIT;
    }
    case ABOUT {
        $title = 'About';
        $content = \&about;
        $action = undef;    # final state
    }
    case FORM.COMPAREEXPERIMENTS        {
        if ($s->is_authorized('user')) {
            $title = 'Compare Experiments';
            push @$js, {-type=>'text/javascript',-code=>form_compareExperiments_js()};
            push @$js, {-type=>'text/javascript',-src=>JS_DIR . '/experiment.js'};
            $content = \&form_compareExperiments;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case COMPAREEXPERIMENTS        {
        if ($s->is_authorized('user')) {
            $title = 'Compare Experiments';

            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/yahoo-dom-event/yahoo-dom-event.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/element/element-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/paginator/paginator-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datasource/datasource-min.js'};
            push @$js, {-type=>'text/javascript', -src=>YUI_ROOT . '/build/datatable/datatable-min.js'};
            push @$js, {-type=>'text/javascript',-code=>compare_experiments_js()};

            $content = \&compare_experiments;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case FORM.LOGIN            {
        if ($s->is_authorized('unauth')) {
            $action = DEFAULT_ACTION;
        } else {
            $title = 'Login';
            $content = \&form_login;
            $action = undef;    # final state
        }
    }
    case LOGIN            {
        $s->authenticate($q->param('username'), $q->param('password'), \$error_string);
        if ($s->is_authorized('unauth')) {
            my $destination = (defined($q->url_param('destination'))) ? uri_unescape($q->url_param('destination')) : undef;
            if (defined($destination) && $destination ne $q->url(-absolute=>1) &&
                $destination !~ m/(?:&|\?|&amp;)a=$action(?:\z|&|#)/ && $destination !~
                m/(?:&|\?|&amp;)a=form_$action(?:\z|&|#)/) {
                # will send a redirect header, so commit the session to data store now
                $s->commit();

                # if the user is heading to a specific placce, pass him/her along,
                # otherwise continue to the main page (script_name)
                # do not add nph=>1 parameter to redirect() because that will cause it to crash
                print $q->redirect(-uri        => $q->url(-base=>1).$destination,
                           -status    => 302,     # 302 Found
                           -cookie    => \@SGX::Cookie::cookies);
                # code will keep executing after redirect, so clean up and force the program to quit
                $action = QUIT;
            } else {
                $action = DEFAULT_ACTION;
            }
        } else {
            $action = FORM.LOGIN;
        }
    }
    case LOGOUT            {
        if ($s->is_authorized('unauth')) {
            $s->destroy;
        }
        $action = DEFAULT_ACTION;
    }
    case FORM.RESETPASSWORD     {
        if ($s->is_authorized('unauth')) {
            $action = FORM.CHANGEPASSWORD;
        } else {
            $title = 'Reset Password';
            $content = \&form_resetPassword;
            $action = undef;    # final state
        }
    }
    case RESETPASSWORD        {
        if ($s->is_authorized('unauth')) {
            $action = FORM.CHANGEPASSWORD;
        } else {
            if ($s->reset_password($q->param('username'), PROJECT_NAME, $q->url(-full=>1).'?a='.FORM.CHANGEPASSWORD, \$error_string)) {
                $title = 'Reset Password';
                $content = \&resetPassword_success;
                $action = undef;    # final state
            } else {
                $action = FORM.RESETPASSWORD;
            }
        }
    }
    case FORM.CHANGEPASSWORD    {
        if ($s->is_authorized('unauth')) {
            $title = 'Change Password';
            $content = \&form_changePassword;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case CHANGEPASSWORD        {
        if ($s->is_authorized('unauth')) {
            if ($s->change_password($q->param('old_password'), $q->param('new_password1'), $q->param('new_password2'), \$error_string)) {
                $title = 'Change Password';
                $content = \&changePassword_success;
                $action = undef;    # final state
            } else {
                $action = FORM.CHANGEPASSWORD;
            }
        } else {
            $action = FORM.LOGIN;
        }
    }
    case CHOOSEPROJECT {
        if ($s->is_authorized('user')) {
            $title = 'Choose Project';
            $content = \&chooseProject;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case FORM.CHANGEEMAIL    {
        if ($s->is_authorized('unauth')) {
            $title = 'Change Email';
            $content = \&form_changeEmail;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case CHANGEEMAIL       {
        if ($s->is_authorized('unauth')) {
            if ($s->change_email($q->param('password'), 
                         $q->param('email1'), $q->param('email2'),
                         PROJECT_NAME,
                         $q->url(-full=>1).'?a='.VERIFYEMAIL, 
                         \$error_string)) {
                $title = 'Change Email';
                $content = \&changeEmail_success;
                $action = undef;    # final state
            } else {
                $action = FORM.CHANGEEMAIL;
            }
        } else {
            $action = FORM.LOGIN;
        }
    }
    case FORM.REGISTERUSER        {
        if ($s->is_authorized('unauth')) {
            $action = DEFAULT_ACTION;
        } else {
            $title = 'Register';
            $content = \&form_registerUser;
            $action = undef;    # final state
        }
    }
    case REGISTERUSER        {
        if ($s->is_authorized('unauth')) {
            $action = DEFAULT_ACTION;
        } else {
            if ($s->register_user(
                          $q->param('username'),
                          $q->param('password1'), $q->param('password2'),
                          $q->param('email1'), $q->param('email2'),
                          $q->param('full_name'),
                          $q->param('address'),
                          $q->param('phone'),
                          PROJECT_NAME,
                          $q->url(-full=>1).'?a='.VERIFYEMAIL,
                          \$error_string)) {
                $title = 'Registration';
                $content = \&registration_success;
                $action = undef;    # final state
            } else {
                $action = FORM.REGISTERUSER;
            }
        }
    }
    case FORM.UPDATEPROFILE         {
        if ($s->is_authorized('unauth')) {
            $title = 'My Profile';
            $content = \&form_updateProfile;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case UPDATEPROFILE        {
        $action = DEFAULT_ACTION;
    }
    case VERIFYEMAIL        {
        if ($s->is_authorized('unauth')) {
            my $t = SGX::Session->new(
                -handle    => $dbh, 
                -expire_in => 3600*48, 
                -id        => $q->param('sid'), 
                -check_ip  => 0
            );
            if ($t->restore()) {
                if ($s->verify_email($t->{data}->{username})) {
                    $title = 'Email Verification';
                    $content = \&verifyEmail_success;
                    $action = undef;    # final state
                } else {
                    $action = DEFAULT_ACTION;
                }
                $t->destroy();
            } else {
                # no session tied
                $action = DEFAULT_ACTION;
            }
        } else {
            $action = FORM.LOGIN;
        }
    }
    case QUIT            {
        # perform cleanup and stop execution
        $dbh->disconnect;
        exit;
    }
    case DEFAULT_ACTION        {
        $title = 'Main';
        $content = \&main;
        $action = undef;    # final state
    }
    else {
        # should not happen during normal operation
        croak "Invalid action name specified: $action";
    }
}}
$s->commit();    # flush the session data and prepare the cookie

# ==== write menu list ==========================================================
my @menu;
    # add top options for everyone
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.DEFAULT_ACTION,
                -title=>'Main page'},'Home');
if ($s->is_authorized('unauth')) {
    # add unauth options
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
                -title=>'My user profile.'},'My Profile');
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.LOGOUT,
                -title=>'You are signed in as '.$s->{data}->{username}.'. Click on this link to log out.'},'Log out');
} else {
    # add top options for anonymous users
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.LOGIN,
                -title=>'Log in'},'Log in');
}
if ($s->is_authorized('user')) {
    # add user options
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.SHOWSCHEMA,
                -title=>'Show database schema'},'Schema');
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.COMPAREEXPERIMENTS,
                -title=>'Select samples to compare'},'Compare Experiments');
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.FINDPROBES,
                -title=>'Search for probes'},'Find Probes');
    # TODO: only admins should be allowed to see the menu part below:
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPLOADANNOT,
                -title=>'Upload or Update Probe Annotations'}, 'Upload/Update Annotations');
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.MANAGEPLATFORMS,
                -title=>'Manage Platforms'}, 'Manage Platforms');
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.MANAGEPROJECTS,
                -title=>'Manage Projects'}, 'Manage Projects');
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.MANAGESTUDIES,
                -title=>'Manage Studies'}, 'Manage Studies');
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.MANAGEEXPERIMENTS,
                -title=>'Manage Experiments'}, 'Manage Experiments');
    push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.OUTPUTDATA,
                -title=>'Output Data'}, 'Output Data');
}
if ($s->is_authorized('admin')) {
    # add admin options
}
# add bottom options for everyone
push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.ABOUT,
            -title=>'About this site'},'About');
push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.HELP,
            -title=>'Help pages',
            -target=>'_new'},'Help');


# ===== HTML =============================================================

# Normally we can set more than one cookie like this:
# print header(-type=>'text/html',-cookie=>[$cookie1,$cookie2]);
# But because the session object takes over the array, have to do it this way:
#   push @SGX::User::cookies, $cookie2;
# ... and then send the \@SGX::User::cookies array reference to CGI::header() for example.

print $q->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);

cgi_start_html();

print $q->img({src=>IMAGES_DIR . '/logo.png', width=>448, height=>108, alt=>PROJECT_NAME, title=>PROJECT_NAME});

print $q->ul({-id=>'menu'},$q->li(\@menu));

#---------------------------------------------------------------------------
#  Don't delete commented-out block below: it is useful for debugging
#  user sessions.
#---------------------------------------------------------------------------
#print $q->pre("
#cookies sent to user:            
#".Dumper(\@SGX::Cookie::cookies)."
#session data stored:        
#".Dumper($s->{data})."
#session expires after:    ".$s->{ttl}." seconds of inactivity
#");

# Main part
&$content();

### Ideally, would want to disconnect from the database before any HTML is printed
### but for the purpose of fast integration, putting this statement here.
$dbh->disconnect;

cgi_end_html();

#######################################################################################
sub cgi_start_html {
# to add plain javascript code to the header, add the following to the -script array:
# {-type=>'text/javasccript', -code=>$JSCRIPT}
    print $q->start_html(
            -title=>PROJECT_NAME." : $title",
            -style=>$css,
            -script=>$js,
            -class=>'yui-skin-sam',
            -head=>[$q->Link({-type=>'image/x-icon',-href=>IMAGES_DIR.'/favicon.ico',-rel=>'icon'})]
        );
    print '<div id="content">';
}
#######################################################################################
sub cgi_end_html {
    print '</div>';
    print footer();
    #print projectInfo();
    print $q->end_html;
}
#######################################################################################
sub main {
    print $q->p('The SEGEX database will provide public access to previously released datasets from the Waxman laboratory, and data mining and visualization modules to query gene expression across several studies and experimental conditions.');
    print $q->p('This database was developed at Boston University as part of the BE768 Biological Databases course, Spring 2009, G. Benson instructor. Student developers: Anna Badiee, Eugene Scherba, Katrina Steiling and Niraj Trivedi. Faculty advisor: David J. Waxman.');
}
#######################################################################################
sub about {
    print $q->h2('About');
    print $q->p('The mammalian liver functions in the stress response, immune response, drug metabolism and protein synthesis. 
    Sex-dependent responses to hepatic stress are mediated by pituitary secretion of growth hormone (GH) and the 
    GH-responsive nuclear factors STAT5a, STAT5b and HNF4-alpha. Whole-genome expression arrays were used to 
    examine sexually dimorphic gene expression in mouse livers.') .

    $q->p('This SEGEX database provides public access to previously released datasets from the Waxman laboratory, and provides data mining tools and data visualization to query gene expression across several studies and experimental conditions.') .

    $q->p('Developed at Boston University as part of the BE768 Biologic Databases course, Spring 2009, G. Benson instructor. Student developers: Anna Badiee, Eugene Scherba, Katrina Steiling and Niraj Trivedi. Faculty advisor: David J. Waxman.');
}
#######################################################################################
sub form_error {
    # wraps an error message into a <div id='errormsg'> and <p> elements
    # for use in forms
    my $error = shift;
    if (defined($error) && $error) {
        return $q->div({-id=>'errormsg'},$q->p($error));
    } else {
        return '';
    }
}
#######################################################################################
sub form_login {
    my $uri = $q->url(-absolute=>1,-query=>1);
    $uri = $q->url(-absolute=>1) if $uri =~ m/(?:&|\?|&amp;)a=${\LOGOUT}(?:\z|&|#)/;    # do not want to logout immediately after login
    my $destination = (defined($q->url_param('destination'))) ? $q->url_param('destination') : uri_escape($uri);
    print $q->start_form(
        -method=>'POST',
        -action=>$q->url(-absolute=>1).'?a='.LOGIN.'&amp;destination='.$destination,
        -onsubmit=>'return validate_fields(this, [\'username\',\'password\']);'
    ) .
    $q->dl( 
        $q->dt('Username:'),
        $q->dd($q->textfield(-name=>'username',-id=>'username')),
        $q->dt('Password:'),
        $q->dd($q->password_field(-name=>'password',-id=>'password',-maxlength=>40)),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string), 
            $q->submit(-name=>'login',-id=>'login',-value=>'Login'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.RESETPASSWORD,
                -title=>'Email me a new password'},'I Forgot My Password'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.REGISTERUSER,
                -title=>'Set up a new account'},'Register')
        )
    )
    .
    $q->end_form;
}
#######################################################################################
sub form_resetPassword {
    print $q->start_form(
        -method=>'POST',
        -action=>$q->url(-absolute=>1).'?a='.RESETPASSWORD,
        -onsubmit=>'return validate_fields(this, [\'username\']);'
    ) .
    $q->dl( 
        $q->dt('Username:'),
        $q->dd($q->textfield(-name=>'username',-id=>'username')),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(-name=>'resetPassword',-id=>'resetPassword',-value=>'Email me a new password'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.LOGIN,
                -title=>'Back to login page'},'Back')
        )
    ) .
    $q->end_form;
}
#######################################################################################
sub resetPassword_success {
    print $q->p('A new password has been emailed to you. Once you receive the email message, 
        you will be able to change the password sent to you by following the link in the email text.') .
    $q->p($q->a({-href=>$q->url(-absolute=>1),
             -title=>'Back to login page'},'Back'));
}
#######################################################################################
sub registration_success {
    print $q->p('An email message has been sent to the email address you have entered. You
    should confirm your email address by clicking on a link included in the email
    message. Another email message has been sent to the administrator(s) of this site. 
    Once your request for access is approved, you can start browsing the content hosted
    on this site.') .
    $q->p($q->a({-href=>$q->url(-absolute=>1),
             -title=>'Back to login page'},'Back'));
}
#######################################################################################
sub form_changePassword {
    # user has to be logged in
    print $q->start_form(
        -method=>'POST',
        -action=>$q->url(-absolute=>1).'?a='.CHANGEPASSWORD,
        -onsubmit=>'return validate_fields(this, [\'old_password\',\'new_password1\',\'new_password2\']);'
    ) .
    $q->dl( 
        $q->dt('Old Password:'),
        $q->dd($q->password_field(-name=>'old_password',-id=>'old_password',-maxlength=>40)),
        $q->dt('New Password:'),
        $q->dd($q->password_field(-name=>'new_password1',-id=>'new_password1',-maxlength=>40)),
        $q->dt('Confirm New Password:'),
        $q->dd($q->password_field(-name=>'new_password2',-id=>'new_password2',-maxlength=>40)),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(-name=>'changePassword',-id=>'changePassword',-value=>'Change password'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
                -title=>'Back to my profile'},'Back')
        )
    ) .
    $q->end_form;
}
#######################################################################################
sub changePassword_success {
    print $q->p('You have successfully changed your password.') .
    $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
             -title=>'Back to my profile'},'Back'));
}
#######################################################################################
sub verifyEmail_success {
    print $q->p('You email address has been verified.') .
    $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
             -title=>'Back to my profile'},'Back'));
}
#######################################################################################
sub form_changeEmail {
    # user has to be logged in
    print $q->start_form(
        -method=>'POST',
        -action=>$q->url(-absolute=>1).'?a='.CHANGEEMAIL,
        -onsubmit=>'return validate_fields(this, [\'password\',\'email1\',\'email2\']);'
    ) .
    $q->dl(
        $q->dt('Password:'),
        $q->dd($q->password_field(-name=>'password',-id=>'password',-maxlength=>40)),
        $q->dt('Email:'),
        $q->dd($q->textfield(-name=>'email1',-id=>'email1')),
        $q->dt('Confirm Email:'),
        $q->dd($q->textfield(-name=>'email2',-id=>'email2')),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(-name=>'changeEmail',-id=>'changeEmail',-value=>'Change email'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
                -title=>'Back to my profile'},'Back')
        )
    ) .
    $q->end_form;
}
#######################################################################################
sub changeEmail_success {
    print $q->p('You have changed your email address. Please confirm your new email
        address by clicking on the link in the message has been sent to the address
        you provided.') .
    $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
         -title=>'Back to my profile'},'Back'));
}
#######################################################################################
sub form_updateProfile {
    # user has to be logged in
    print $q->h2('My Profile');

    if ($s->is_authorized('user')) {
        print $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.CHOOSEPROJECT,
                -title=>'Choose Project'},'Choose Project'));
    }

    print
        $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.CHANGEPASSWORD,
            -title=>'Change Password'},'Change Password')),
        $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.CHANGEEMAIL,
            -title=>'Change Email'},'Change Email'));
}
#######################################################################################
sub form_registerUser {
    # user cannot be logged in
    print $q->start_form(
        -method=>'POST',
        -action=>$q->url(absolute=>1).'?a='.REGISTERUSER,
        -onsubmit=>'return validate_fields(this, [\'username\',\'password1\',\'password2\',\'email1\',\'email2\',\'full_name\']);'
    ) .
    $q->dl(
        $q->dt('Username:'),
        $q->dd($q->textfield(-name=>'username',-id=>'username')),
        $q->dt('Password:'),
        $q->dd($q->password_field(-name=>'password1',-id=>'password1',-maxlength=>40)),
        $q->dt('Confirm Password:'),
        $q->dd($q->password_field(-name=>'password2',-id=>'password2',-maxlength=>40)),
        $q->dt('Email:'),
        $q->dd($q->textfield(-name=>'email1',-id=>'email1')),
        $q->dt('Confirm Email:'),
        $q->dd($q->textfield(-name=>'email2',-id=>'email2')),
        $q->dt('Full Name:'),
        $q->dd($q->textfield(-name=>'full_name',-id=>'full_name')),
        $q->dt('Address:'),
        $q->dd($q->textarea(-name=>'address',-id=>'address',-rows=>10,-columns=>50)),
        $q->dt('Phone:'),
        $q->dd($q->textfield(-name=>'phone',-id=>'phone')),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(-name=>'registerUser',-id=>'registerUser',-value=>'Register'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.LOGIN,
                -title=>'Back to login page'},'Back')
        )
    ) .
    $q->end_form;
}
#######################################################################################
sub footer {
    return 
        $q->div({-id=>'footer'},
        $q->ul(
            $q->li($q->a({-href=>'http://www.bu.edu/',
                -title=>'Boston University'},'Boston University')),
            $q->li(
                $q->ul(
                $q->li($q->a({-href=>'http://validator.w3.org/check?uri=referer',
                    -title=>'Validate XHTML'},'XHTML')),
                $q->li($q->a({-href=>'http://jigsaw.w3.org/css-validator/check/referer',
                    -title=>'Validate CSS'},'CSS')),
                $q->li('SEGEX version : ' . $softwareVersion )
                )
            )
        ));
}
#######################################################################################
#sub projectInfo {
#    $ChooseProject = SGX::ChooseProject->new($dbh,$q);
#    $ChooseProject->drawProjectInfoHeader();
#}
#######################################################################################
sub updateCell {
    my $type = $q->param('type');
    assert(defined($type));

    switch ($type) 
    {
        case 'probe' 
        {
            my $rc = $dbh->do(
                'update probe left join platform on platform.pid=probe.pid set note=? where reporter=? and pname=?', 
                undef,
                $q->param('note'),
                $q->param('reporter'),
                $q->param('pname')
            ) or croak $dbh->errstr;
            return $rc;
        }
        case 'gene' 
        {
            # tries to use gene symbol first as key field; if gene symbol is empty, switches to 
            # transcript accession number.
            my $seqname = $q->param('seqname');
            my $pname = $q->param('pname');
            my $note = $q->param('note');
            if (defined($seqname) && $seqname ne '') {
                my $rc = $dbh->do(
                    'update gene left join platform on platform.pid=gene.pid set gene_note=? where seqname=? and pname=?',
                    undef,
                    $note,
                    $seqname,
                    $pname
                ) or croak $dbh->errstr;
                return $rc;
            } else {
                my $accnum_count = 0;
                my @accnum = split(/ *, */, $q->param('accnum'));
                foreach (@accnum) {
                    if (defined($_) && $_ ne '') {
                        $accnum_count++;
                        $dbh->do(
                            'update gene left join platform on platform.pid=gene.pid set gene_note=? where accnum=? and pname=?',
                            undef,
                            $note,
                            $_,
                            $pname
                        ) or croak $dbh->errstr;
                    }
                }
                if ($accnum_count > 0) {
                    return 1;
                } else {
                    return 0;
                }
            }
        }
        case 'experiment' 
        {
            my $rc = $dbh->do(
                'update experiment set ExperimentDescription=?, AdditionalInformation=? where eid=?',
                undef,
                $q->param('desc'),
                $q->param('add'),
                $q->param('eid')
            ) or croak $dbh->errstr;
            return $rc;
        }
        case 'experimentSamples' 
        {
            my $rc = $dbh->do(
                'update experiment set sample1=?, sample2=? where eid=?',
                undef,
                $q->param('S1'),
                $q->param('S2'),
                $q->param('eid')
            ) or croak $dbh->errstr;
            return $rc;
        }
        case 'study'
        {
            my $rc = $dbh->do(
                'update study set description=?, pubmed=? where stid=?',
                undef,
                $q->param('desc'),
                $q->param('pubmed'),
                $q->param('stid')
            ) or croak $dbh->errstr;
            return $rc;
        }
        case 'platform'
        {
            my $rc = $dbh->do(
                'update platform set pname=?, def_f_cutoff=?, def_p_cutoff=? where pid=?',
                undef,
                $q->param('pname'),
                $q->param('fold'),
                $q->param('pvalue'),
                $q->param('pid')
            ) or croak $dbh->errstr;
            return $rc;
        }
        case 'project'
        {
            my $rc = $dbh->do(
                'update project set prname=?, prdesc=? where prname=?',
                undef,
                $q->param('name'),
                $q->param('desc'),
                $q->param('old_name')
            ) or croak $dbh->errstr;
            return $rc;
        }
        else
        {
            croak "Unknown request type=$type\n";
        }
    }
}
#######################################################################################
sub form_findProbes {
    my %type_dropdown = (
        'gene'=>'Gene Symbols',
        'transcript'=>'Transcripts',
        'probe'=>'Probes'
    );
    my %match_dropdown = (
        'full'=>'Full Word',
        'prefix'=>'Prefix',
        'part'=>'Part of the Word / Regular Expression*'
    );
    my %opts_dropdown = (
        '0'=>'Basic (names,IDs only)',
        '1'=>'Full annotation',
        '2'=>'Full annotation with experiment data (CSV)',
        '3'=>'Full annotation with experiment data (Not implemented yet)'
    );
    my %trans_dropdown = (
        'fold' => 'Fold Change +/- 1', 
        'ln'=>'Log2 Ratio'
    );

    print $q->start_form(-method=>'GET',
        -action=>$q->url(absolute=>1),
        -enctype=>'application/x-www-form-urlencoded') .
    $q->h2('Find Probes') .
    $q->p('Enter search text below to find the data for that probe. The textbox will allow a comma separated list of values, or one value per line, to obtain information on multiple probes.') .
    $q->p('Regular Expression Example: "^cyp.b" would retrieve all genes starting with cyp.b where the period represents any one character. More examples can be found at <a href="http://en.wikipedia.org/wiki/Regular_expression_examples">Wikipedia Examples</a>.') .
    $q->dl(
        $q->dt('Search string(s):'),
        $q->dd($q->textarea(-name=>'address',-id=>'address',-rows=>10,-columns=>50,-tabindex=>1, -name=>'text')),
        $q->dt('Search type :'),
        $q->dd($q->popup_menu(
                -name=>'type',
                -default=>'gene',
                -values=>[keys %type_dropdown],
                -labels=>\%type_dropdown
        )),
        $q->dt('Pattern to match :'),
        $q->dd($q->radio_group(
                -tabindex=>2, 
                -name=>'match', 
                -linebreak=>'true', 
                -default=>'full', 
                -values=>[keys %match_dropdown], 
                -labels=>\%match_dropdown
        )),
        $q->dt('Display options :'),
        $q->dd($q->popup_menu(
                -tabindex=>3, 
                -name=>'opts',
                -values=>[keys %opts_dropdown], 
                -default=>'1',
                -labels=>\%opts_dropdown
        )),
        $q->dt('Graph(s) :'),
        $q->dd($q->checkbox(-tabindex=>4, id=>'graph', -onclick=>'sgx_toggle(this.checked, [\'graph_option_names\', \'graph_option_values\']);', -checked=>0, -name=>'graph',-label=>'Show Differential Expression Graph')),
        $q->dt({id=>'graph_option_names'}, "Response variable:"),
        $q->dd({id=>'graph_option_values'}, $q->radio_group(
                -tabindex=>5, 
                -name=>'trans', 
                -linebreak=>'true', 
                -default=>'fold', 
                -values=>[keys %trans_dropdown], 
                -labels=>\%trans_dropdown
        )),
        $q->dt('&nbsp;'),
        $q->dd($q->submit(-tabindex=>6, -name=>'a', -value=>FINDPROBES, -override=>1)),
    ) 
    .
    $q->endform;
}
#######################################################################################
sub findProbes_js 
{
    my $text         = $q->param('text') or croak "You did not specify what to search for";    # must be always set -- no defaults
    my $type         = $q->param('type') or croak "You did not specify where to search";    # must be always set -- no defaults
    my $trans         = (defined($q->param('trans'))) ? $q->param('trans') : 'fold';
    my $match         = (defined($q->param('match'))) ? $q->param('match') : 'full';
    my $opts         = (defined($q->param('opts'))) ? $q->param('opts') : 1;
    my $speciesColumn    = 5;

    my @extra_fields;

    switch ($opts) {
    case 0 {}
    case 1 { @extra_fields = ('coalesce(probe.note, g0.note) as \'Probe Specificity - Comment\', coalesce(probe.probe_sequence, g0.probe_sequence) AS \'Probe Sequence\'', 'group_concat(distinct g0.description order by g0.seqname asc separator \'; \') AS \'Gene Description\'', 'group_concat(distinct gene_note order by g0.seqname asc separator \'; \') AS \'Gene Ontology - Comment\'') }
    case 2 {}
    }

    my $extra_sql = (@extra_fields) ? ', '.join(', ', @extra_fields) : '';

    my $qtext;
    
    #This will be the array that holds all the splitted items.
    my @textSplit;    
    
    #If we find a comma, split on that, otherwise we split on new lines.
    if($text =~ m/,/)
    {
        #Split the input on commas.    
        @textSplit = split(/\,/,trim($text));
    }
    else
    {
        #Split the input on the new line.    
        @textSplit = split(/\r\n/,$text);
    }
    
    #Get the count of how many search terms were found.
    my $searchesFound = @textSplit;
    
    #This will be the string we output.
    my $out = "";

    if($searchesFound < 2)
    {
        switch ($match) 
        {
            case 'full'        { $qtext = '^'.$textSplit[0].'$' }
            case 'prefix'    { $qtext = '^'.$textSplit[0] }
            case 'part'        { $qtext = $textSplit[0] } 
            else            { assert(0) }
        }
    }
    else
    {
        #Begining of the SQL regex.
        $qtext = '^';
        
        #Add the search items seperated by a bar.
        foreach(@textSplit)
        {
            if($_)
            {
                $qtext .= trim($_) . "|";
            }
        }
        
        #Remove the double backslashes.
        $qtext =~ s/\|$//;
        
        #Add the closing regex character.
        $qtext .= '$';
    }
    
    my $g0_sql;
    switch ($type) 
    {
        case 'probe' 
        {
            $g0_sql = "
            select rid, reporter, note, probe_sequence, g1.pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join 
            (select distinct probe.rid, probe.reporter, probe.note, probe.probe_sequence, probe.pid, accnum from probe left join annotates on annotates.rid=probe.rid left join gene on gene.gid=annotates.gid where reporter REGEXP ?) as g1
            on g2.accnum=g1.accnum where rid is not NULL
            
            union

            select rid, reporter, note, probe_sequence, g3.pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
            (select distinct probe.rid, probe.reporter, probe.note, probe.probe_sequence, probe.pid, seqname from probe left join annotates on annotates.rid=probe.rid left join gene on gene.gid=annotates.gid where reporter REGEXP ?) as g3
            on g4.seqname=g3.seqname where rid is not NULL
            ";

        }
        case 'gene' 
        {
            $g0_sql = "
            select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join
            (select distinct accnum from gene where seqname REGEXP ? and accnum is not NULL) as g1
            on g2.accnum=g1.accnum where g2.gid is not NULL

            union

            select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
            (select distinct seqname from gene where seqname REGEXP ? and seqname is not NULL) as g3
            on g4.seqname=g3.seqname where g4.gid is not NULL
            ";
        }
        case 'transcript' 
        {
            $g0_sql = "
            select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join
            (select distinct accnum from gene where accnum REGEXP ? and accnum is not NULL) as g1
            on g2.accnum=g1.accnum where g2.gid is not NULL

            union

            select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
            (select distinct seqname from gene where accnum REGEXP ? and seqname is not NULL) as g3
            on g4.seqname=g3.seqname where g4.gid is not NULL
            ";
        } 
        else 
        {
            assert(0); # shouldn't happen
        }
    }

    my $probeSQLStatement = qq{
            select distinct 
                coalesce(probe.reporter, g0.reporter) as Probe, 
                pname as Platform,
                group_concat(distinct if(isnull(g0.accnum),'',g0.accnum) order by g0.seqname asc separator ',') as 'Transcript', 
                if(isnull(g0.seqname),'',g0.seqname) as 'Gene'
                $extra_sql,
                platform.species
                from
                ($g0_sql) as g0
            left join (annotates natural join probe) on annotates.gid=g0.gid
            left join platform on platform.pid=coalesce(probe.pid, g0.pid)
            group by coalesce(probe.rid, g0.rid)
            };

            
    if($opts==2)
    {
        $s->commit();
        #print $q->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
        $findProbes = SGX::FindProbes->new($dbh,$q,$type,$qtext);
        $findProbes->setInsideTableQuery($g0_sql);
        $findProbes->loadProbeData($qtext);
        $findProbes->loadExperimentData();
        $findProbes->fillPlatformHash();
        $findProbes->getFullExperimentData();        
        $findProbes->printFindProbeCSV();
        exit;
    }
    elsif($opts==3)
    {
        $s->commit();
        #print $q->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
        $findProbes = SGX::FindProbes->new($dbh,$q,$type,$qtext);
        $findProbes->setInsideTableQuery($g0_sql);
        $findProbes->loadProbeData($qtext);
        $findProbes->loadExperimentData();
        $findProbes->fillPlatformHash();
        $out = $findProbes->printFindProbeToScreen();
        $out;
    }
    else
    {
        my $sth = $dbh->prepare($probeSQLStatement) or croak $dbh->errstr;
        #warn $sth->{Statement};    

        my $rowcount = $sth->execute($qtext, $qtext) or croak $dbh->errstr;

        my $caption = sprintf("Found %d probe", $rowcount) .(($rowcount != 1) ? 's' : '')." annotated with $type groups matching '$qtext' (${type}s grouped by gene symbol or transcript accession number)";

        $out .= "
    var probelist = {
    caption: \"$caption\",
    records: [
    ";

        my @names = @{$sth->{NAME}};    # cache the field name array

        my $data = $sth->fetchall_arrayref;
        $sth->finish;

        # data are sent as a JSON object plus Javascript code (at the moment)
        foreach (sort {$a->[3] cmp $b->[3]} @$data) {
            foreach (@$_) {
                $_ = '' if !defined $_;
                $_ =~ s/"//g;    # strip all double quotes (JSON data are bracketed with double quotes)
                        # TODO: perhaps escape quotation marks instead of removing them
            }

            # TODO: add a species table to the schema. Each Experiment table entry (a single microarray)
            # will then have a foreign key to species (because expression microarrays are species-specific).
            # Will also need species reference from either Probe table or Gene table or both (or something similar).
            # the following NCBI search shows only genes specific to a given species:
            # http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=Cyp2a12+AND+mouse[ORGN]
            $out .= '{0:"'.$_->[0].'",1:"'.$_->[1].'",2:"'.$_->[2].'",3:"'.$_->[3].'"';


            switch ($opts) 
            {
                case 0 
                {
                    $speciesColumn = 5;
                    $out .= ',5:"'.$_->[5].'"';
                }

                case 1 
                { 
                    $speciesColumn = 8;
                    $out .= ',4:"'.$_->[4].'",5:"'.$_->[5].'",6:"'.$_->[6].'",7:"'.$_->[7].'",8:"'.$_->[8].'"';
                }

                case 2 
                {
                    $speciesColumn = 4;
                    $out .= ',4:"'.$_->[4].'",5:"'.$_->[5].'",6:"'.$_->[6].'",7:"'.$_->[7].'",8:"'.$_->[8].'",9:"'.$_->[9].'"';
                }
            }
            $out .= "},\n";
        }
        $out =~ s/,\s*$//;    # strip trailing comma

        my $tableOut = '';
        my $columnList = '';

        #We need different 
        switch ($opts) 
            {
                case 0 
                {
                    $tableOut = '';
                }

                case 1 
                { 
                    $columnList = ',"4","5","6","7","8"';
                    $tableOut = ',
                            {key:"4", sortable:true, resizeable:true, label:"'.$names[4].'",
                    editor:new YAHOO.widget.TextareaCellEditor({
                    disableBtns: false,
                    asyncSubmitter: function(callback, newValue) { 
                        var record = this.getRecord();
                        //var column = this.getColumn();
                        //var datatable = this.getDataTable(); 
                        if (this.value == newValue) { callback(); } 

                        YAHOO.util.Connect.asyncRequest("POST", "'.$q->url(-absolute=>1).'?a=updateCell", { 
                            success:function(o) { 
                                if(o.status === 200) {
                                    // HTTP 200 OK
                                    callback(true, newValue); 
                                } else { 
                                    alert(o.statusText);
                                    //callback();
                                } 
                            }, 
                            failure:function(o) { 
                                alert(o.statusText); 
                                callback(); 
                            },
                            scope:this 
                        }, "type=probe&note=" + escape(newValue) + "&pname=" + encodeURI(record.getData("1")) + "&reporter=" + encodeURI(record.getData("0"))
                        );
                    }})},
                            {key:"5", sortable:true, resizeable:true, label:"'.$names[5].'", formatter:"formatSequence"},
                            {key:"6", sortable:true, resizeable:true, label:"'.$names[6].'"},
                            {key:"7", sortable:true, resizeable:true, label:"'.$names[7].'",

                    editor:new YAHOO.widget.TextareaCellEditor({
                    disableBtns: false,
                    asyncSubmitter: function(callback, newValue) {
                        var record = this.getRecord();
                        //var column = this.getColumn();
                        //var datatable = this.getDataTable();
                        if (this.value == newValue) { callback(); }
                        YAHOO.util.Connect.asyncRequest("POST", "'.$q->url(-absolute=>1).'?a=updateCell", {
                            success:function(o) {
                                if(o.status === 200) {
                                    // HTTP 200 OK
                                    callback(true, newValue);
                                } else {
                                    alert(o.statusText);
                                    //callback();
                                }
                            },
                            failure:function(o) {
                                alert(o.statusText);
                                callback();
                            },
                            scope:this
                        }, "type=gene&note=" + escape(newValue) + "&pname=" + encodeURI(record.getData("1")) + "&seqname=" + encodeURI(record.getData("3")) + "&accnum=" + encodeURI(record.getData("2"))
                        );
                    }})}';
                }

                case 2 
                {
                    $columnList = ',"4","5","6","7","8","9"';
                    $tableOut = ',' . "\n" . '{key:"5", sortable:true, resizeable:true, label:"Experiment",formatter:"formatExperiment"}';
                    $tableOut .= ',' . "\n" . '{key:"7", sortable:true, resizeable:true, label:"Probe Sequence"}';
                }
            }


        $out .= '
    ]}

    function export_table(e) {
        var r = this.records;
        var bl = this.headers.length;
        var w = window.open("");
        var d = w.document.open("text/html");
        d.title = "Tab-Delimited Text";
        d.write("<pre>");
        for (var i=0, al = r.length; i < al; i++) {
            for (var j=0; j < bl; j++) {
                d.write(r[i][j] + "\t");
            }
            d.write("\n");
        }
        d.write("</pre>");
        d.close();
        w.focus();
    }

    YAHOO.util.Event.addListener("probetable_astext", "click", export_table, probelist, true);
    YAHOO.util.Event.addListener(window, "load", function() {
        ';
        if (defined($q->param('graph'))) {
            $out .= 'var graph_content = "";
        var graph_ul = YAHOO.util.Dom.get("graphs");';
        }
        $out .= '
        YAHOO.util.Dom.get("caption").innerHTML = probelist.caption;

        YAHOO.widget.DataTable.Formatter.formatProbe = function(elCell, oRecord, oColumn, oData) {
            var i = oRecord.getCount();
            ';
            if (defined($q->param('graph'))) {
                $out .= 'graph_content += "<li id=\"reporter_" + i + "\"><object type=\"image/svg+xml\" width=\"555\" height=\"880\" data=\"./graph.cgi?reporter=" + oData + "&trans='.$trans.'\"><embed src=\"./graph.cgi?reporter=" + oData + "&trans='.$trans.'\" width=\"555\" height=\"880\" /></object></li>";
            elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" href=\"#reporter_" + i + "\">" + oData + "</a></div>";';
            } else {
                $out .= 'elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" id=\"show" + i + "\">" + oData + "</a></div>";';
            }
        $out .= '
        }
        YAHOO.widget.DataTable.Formatter.formatTranscript = function(elCell, oRecord, oColumn, oData) {
            var a = oData.split(/ *, */);
            var out = "";
            for (var i=0, al=a.length; i < al; i++) {
                var b = a[i];
                if (b.match(/^ENS[A-Z]{4}\d{11}/i)) {
                    out += "<a title=\"Search Ensembl for " + b + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + b + "\">" + b + "</a>, ";
                } else {
                    out += "<a title=\"Search NCBI Nucleotide for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=Nucleotide&term=" + oRecord.getData("' . $speciesColumn . '") + "[ORGN]+AND+" + b + "[NACC]\">" + b + "</a>, ";
                }
            }
            elCell.innerHTML = out.replace(/,\s*$/, "");
        }
        YAHOO.widget.DataTable.Formatter.formatGene = function(elCell, oRecord, oColumn, oData) {
            if (oData.match(/^ENS[A-Z]{4}\d{11}/i)) {
                elCell.innerHTML = "<a title=\"Search Ensembl for " + oData + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + oData + "\">" + oData + "</a>";
            } else {
                elCell.innerHTML = "<a title=\"Search NCBI Gene for " + oData + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=" + oRecord.getData("' . $speciesColumn . '") + "[ORGN]+AND+" + oData + "\">" + oData + "</a>";
            }
        }
        YAHOO.widget.DataTable.Formatter.formatExperiment = function(elCell, oRecord, oColumn, oData) {
            elCell.innerHTML = "<a title=\"View Experiment Data\" target=\"_blank\" href=\"?a=getTFS&eid=" + oRecord.getData("6") + "&rev=0&fc=" + oRecord.getData("9") + "&pval=" + oRecord.getData("8") + "&opts=2\">" + oData + "</a>";
        }
        YAHOO.widget.DataTable.Formatter.formatSequence = function(elCell, oRecord, oColumn, oData) {
            elCell.innerHTML = "<a href=\"http://genome.ucsc.edu/cgi-bin/hgBlat?userSeq=" + oData + "&type=DNA&org=" + oRecord.getData("' . $speciesColumn . '") + "\" title=\"UCSC BLAT on " + oRecord.getData("' . $speciesColumn . '") + " DNA\" target=\"_blank\">" + oData + "</a>";
        }
        var myColumnDefs = [
            {key:"0", sortable:true, resizeable:true, label:"'.$names[0].'", formatter:"formatProbe"},
            {key:"1", sortable:true, resizeable:true, label:"'.$names[1].'"},
            {key:"2", sortable:true, resizeable:true, label:"'.$names[2].'", formatter:"formatTranscript"}, 
            {key:"3", sortable:true, resizeable:true, label:"'.$names[3].'", formatter:"formatGene"}'. $tableOut.'];

        var myDataSource = new YAHOO.util.DataSource(probelist.records);
        myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
        myDataSource.responseSchema = {
            fields: ["0","1","2","3"'. $columnList . ']
        };
        var myData_config = {
            paginator: new YAHOO.widget.Paginator({
                rowsPerPage: 50 
            })
        };

        var myDataTable = new YAHOO.widget.DataTable("probetable", myColumnDefs, myDataSource, myData_config);

        // Set up editing flow 
        var highlightEditableCell = function(oArgs) { 
            var elCell = oArgs.target; 
            if(YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) { 
            this.highlightCell(elCell); 
            } 
        }; 
        myDataTable.subscribe("cellMouseoverEvent", highlightEditableCell); 
        myDataTable.subscribe("cellMouseoutEvent", myDataTable.onEventUnhighlightCell); 
        myDataTable.subscribe("cellClickEvent", myDataTable.onEventShowCellEditor);

        var nodes = YAHOO.util.Selector.query("#probetable tr td.yui-dt-col-0 a");
        var nl = nodes.length;

        // Ideally, would want to use a "pre-formatter" event to clear graph_content
        // TODO: fix the fact that when cells are updated via cell editor, the graphs are rebuilt unnecessarily.
        myDataTable.doBeforeSortColumn = function(oColumn, sSortDir) {
            graph_content = "";
            return true;
        };
        myDataTable.doBeforePaginatorChange = function(oPaginatorState) {
            graph_content = "";
            return true;
        };
        myDataTable.subscribe("renderEvent", function () {
        ';

        if (defined($q->param('graph'))) 
        {
            $out .= '
            graph_ul.innerHTML = graph_content;
            ';

        } else {
            $out .=
        '
            // if the line below is moved to window.load closure,
            // panels will no longer show up after sorting
            var manager = new YAHOO.widget.OverlayManager();
            var myEvent = YAHOO.util.Event;
            var i;
            var imgFile;
            for (i = 0; i < nl; i++) {
                myEvent.addListener("show" + i, "click", function () {
                    var index = this.getAttribute("id").substring(4);
                    var panel_old = manager.find("panel" + index);

                    if (panel_old === null) {
                        imgFile = this.innerHTML;    // replaced ".text" with ".innerHTML" because of IE problem
                        var panel =  new YAHOO.widget.Panel("panel" + index, { close:true, visible:true, draggable:true, constraintoviewport:false, context:["container" + index, "tl", "br"] } );
                        panel.setHeader(imgFile);
                        panel.setBody("<object type=\"image/svg+xml\" width=\"555\" height=\"880\" data=\"./graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\"><embed src=\"./graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\" width=\"555\" height=\"880\" /></object>");
                        manager.register(panel);
                        panel.render("container" + index);
                        // panel.show is unnecessary here because visible:true is set
                    } else {
                        panel_old.show();
                    }
                }, nodes[i], true);
            }
        '};
        $out .= '
        });

        return {
            oDS: myDataSource,
            oDT: myDataTable
        };
    });
    ';
        $out;
    }
}
#######################################################################################
sub findProbes {
    print    '<h2 id="caption"></h2>',
        '<div><a id="probetable_astext">View as plain text</a></div>',
        '<div id="probetable"></div>';
    print '<ul id="graphs"></ul>' if defined($q->param('graph'));
}
#######################################################################################
sub schema {
    my $dump_url = $q->url(-absolute=>1).'?a='.DUMP;
    print '<h2>Schema</h2>';
    print '
<map name="schema_Map">
<area shape="rect" title="Click to download Users table" alt="users" coords="544,497,719,718" href="'.$dump_url.'&amp;table=users" target="_blank">
<area shape="rect" title="Click to download Sessions table" alt="sessions" coords="433,497,526,584" href="'.$dump_url.'&amp;table=sessions" target="_blank">
<area shape="rect" title="Click to download Sample table" alt="sample" coords="0,593,140,720" href="'.$dump_url.'&amp;table=sample" target="_blank">
<area shape="rect" title="Click to download Study table" alt="study" coords="197,376,337,502" href="'.$dump_url.'&amp;table=study" target="_blank">
<area shape="rect" title="Click to download Experiment table" alt="experiment" coords="16,368,125,513" href="'.$dump_url.'&amp;table=experiment" target="_blank">
<area shape="rect" title="Click to download Platform table" alt="platform" coords="209,202,326,327" href="'.$dump_url.'&amp;table=platform" target="_blank">
<area shape="rect" title="Click to download Gene table" alt="gene" coords="587,18,719,162" href="'.$dump_url.'&amp;table=gene" target="_blank">
<area shape="rect" title="Click to download Annotates table" alt="annotates" coords="420,46,520,133" href="'.$dump_url.'&amp;table=annotates" target="_blank">
<area shape="rect" title="Click to download Probe table" alt="probe" coords="186,26,349,151" href="'.$dump_url.'&amp;table=probe" target="_blank">
<area shape="rect" title="Click to download Microarray table" alt="microarray" coords="16,0,127,180" href="'.$dump_url.'&amp;table=microarray" target="_blank">
</map>
',
    $q->img({src=>IMAGES_DIR.'/schema.png', width=>720, height=>720, usemap=>'#schema_Map', id=>'schema'});
}
#######################################################################################
sub form_compareExperiments_js {
    my $out = '';

    # get a list of platforms and cutoff values
    my $sth = $dbh->prepare(qq{select pid, pname, def_p_cutoff, def_f_cutoff from platform})
        or croak $dbh->errstr;
    my $rowcount = $sth->execute
        or croak $dbh->errstr;
    assert($rowcount);

    ### populate a Javascript hash with the content of the platform recordset
    $out .= '
Event.observe(window, "load", init);

var form = "'.FORM.COMPAREEXPERIMENTS.'"
var platform = {};
';
    while (my @row = $sth->fetchrow_array) {
        $out .= 'platform['.$row[0]."] = {};\n";
        $out .= 'platform['.$row[0].'][0] = \''.$row[1]."';\n"; # platform name
        $out .= 'platform['.$row[0].'][1] = \''.$row[2]."';\n";    # P-calue cutoff
        $out .= 'platform['.$row[0].'][2] = \''.$row[3]."';\n";    # Fold change cutoff
    }
    $sth->finish;


    # get a list of studies
    $sth = $dbh->prepare(qq{select stid, description, pid from study})
        or croak $dbh->errstr;
    $rowcount = $sth->execute
        or croak $dbh->errstr;
    assert($rowcount);

    ### populate a Javascript hash with the content of the study recordset
    $out .= '
var study = {};
';
    while (my @row = $sth->fetchrow_array) {
        $out .= 'study['.$row[0]."] = {};\n";
        $out .= 'study['.$row[0].'][0] = \''.$row[1]."';\n"; # study description
        $out .= 'study['.$row[0]."][1] = {};\n";     # sample 1 name
        $out .= 'study['.$row[0]."][2] = {};\n";     # sample 2 name
        $out .= 'study['.$row[0].'][3] = \''.$row[2]."';\n"; # platform id
    }
    $sth->finish;

    # get a list of all experiments
    $sth = $dbh->prepare(qq{select stid, eid, experiment.sample2 as s2_desc, experiment.sample1 as s1_desc from study natural join StudyExperiment natural join experiment order by eid})
        or croak $dbh->errstr;
    $rowcount = $sth->execute
        or croak $dbh->errstr;
    assert($rowcount);

    ### populate the Javascript hash with the content of the experiment recordset
    while (my @row = $sth->fetchrow_array) {
        $out .= 'study['.$row[0].'][1]['.$row[1].'] = \''.$row[2]."';\n";
        $out .= 'study['.$row[0].'][2]['.$row[1].'] = \''.$row[3]."';\n";
    }
    $sth->finish;

    $ out .= '
function init() {
    populatePlatforms("platform");
    addExperiment();
}
';
    $out;
}
#######################################################################################
sub form_compareExperiments {
    my %geneFilter_dropdown = (
        'none'=>'none',
        'file'=>'file',
        'list'=>'list'
    );
    my %gene_dropdown = (
        'gene'=>'Gene Symbols',
        'transcript'=>'Transcripts',
        'probe'=>'Probes'
    );
    my %match_dropdown = (
        'full'=>'Full Word',
        'prefix'=>'Prefix',
        'part'=>'Part of the Word / Regular Expression*'
    );

    print $q->h2('Compare Experiments');
    print 
    $q->dl(
        $q->dt('Choose platform / add experiment:'),
        $q->dd(    $q->popup_menu(-name=>'platform', -id=>'platform', -onChange=>"updatePlatform(this);"),
            $q->span({-class=>'separator'},' / '),
            $q->button(-value=>'Add experiment',-onclick=>'addExperiment();'))
    );
    print
    $q->start_form(
            -method=>'POST',
            -id=>FORM.COMPAREEXPERIMENTS,
            -action=>$q->url(absolute=>1).'?a='.COMPAREEXPERIMENTS
    ),
    $q->dl(
        $q->dt('Include all probes in output (Probes without a TFS will be labeled TFS 0):'),
        $q->dd($q->checkbox(-name=>'chkAllProbes',-id=>'chkAllProbes',-value=>'1',-label=>'')),
        $q->dt('Filter:'),
        $q->dd($q->radio_group(
                -tabindex=>2,
                -onChange=>'toggleFilterOptions(this.value);', 
                -name=>'geneFilter', 
                -values=>[keys %geneFilter_dropdown], 
                -default=>'none', 
                -labels=>\%geneFilter_dropdown
        ))
    ),
    $q->dl(
        $q->div({-id=>'divSearchItemsDiv',-name=>'divSearchItemsDiv',-style=>'display:none;'},
            $q->table({-style=>'width:100%'},
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '&nbsp;'
                            )
                    ),                
                $q->TR(
                        $q->th({-id=>'tableheader1',-colspan=>'2'},
                            '<font style="font-size:150%">Search by file of terms</font>'
                            )
                    ),
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '<hr />'
                            )
                    ),
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '&nbsp;'
                            )
                    ),                        
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '<font color="red"><b>When uploading a file you will be limited to only full text matches. The uploaded file must be a .txt file with one line per search term.</b></font>'
                            )
                    ),
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '&nbsp;'
                            )
                    ),                        
                $q->TR(
                        $q->td({-id=>'tablecell2',-colspan=>'2'},'Gene File :',$q->filefield(-name=>'gene_file')),
                    ),
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '&nbsp;'
                            )
                    )                    
            )
        )
    ),
    $q->dl(
        $q->div({-id=>'divSearchItemsDiv2',-name=>'divSearchItemsDiv2',-style=>'display:none;'},    
            $q->table({-style=>'width:100%'},
                $q->TR(
                        $q->th({-id=>'tableheader2',-colspan=>'2'},
                            '<font style="font-size:150%">Search by strings</font>'
                            )
                    ),
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '<hr />'
                            )
                    ),
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            'Search type :',
                            $q->popup_menu(
                                -name=>'type',
                                -values=>[keys %gene_dropdown],
                                -default=>'gene',
                                -labels=>\%gene_dropdown
                            ))
                    ),                    
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '&nbsp;'
                            )
                    ),                    
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '<font color="red"><b>Searches using this method may run slowly when inputting 25 terms!</b></font>'
                            )
                    ),
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '&nbsp;'
                            )
                    ),                    
                $q->TR(
                        $q->td({-id=>'tablecell1'},'Search string(s):'),
                        $q->td({-id=>'tablecell2'},$q->textarea(-name=>'address',-id=>'address',-rows=>10,-columns=>50,-tabindex=>1, -name=>'text'))                        
                    ),
                $q->TR(
                        $q->td({-id=>'tablecell1'},'Pattern to match :'),
                        $q->td($q->radio_group(
                                -tabindex=>2, 
                                -name=>'match', 
                                -values=>[keys %match_dropdown], 
                                -default=>'full', 
                                -linebreak=>'true', 
                                -labels=>\%match_dropdown
                        ))
                    ),
                $q->TR(
                        $q->td({-id=>'tablecell1',-colspan=>'2'},
                            '&nbsp;'
                            )
                    )                    
            )    
        )
    ),
    $q->table({-style=>'width:100%;border-width: 1px;'},    
        $q->TR(
                $q->td({-id=>'tablecell1'},
                        '<font style="font-size:150%">Compare selected experiments</font> : ',
                        $q->submit(-name=>'submit',-value=>'Submit', -override=>1),
                        $q->hidden(-name=>'a',-value=>COMPAREEXPERIMENTS, -override=>1)
                    )
            )
    ),
    $q->dl(
        $q->dt('<br />')
            ),
    $q->dl(
        $q->dt('<br />')
            ),            
    $q->endform;
}

#######################################################################################
sub compare_experiments_js {
    #print $q->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
    #This flag tells us whether or not to ignore the thresholds.
    my $allProbes         = '';
    $allProbes             = ($q->param('chkAllProbes')) if defined($q->param('chkAllProbes'));
    
    my $searchFilter    = '';
    $searchFilter         = ($q->param('chkUseGeneList')) if defined($q->param('chkUseGeneList'));

    my $filterType        = '';
    $filterType         = ($q->param('geneFilter')) if defined($q->param('geneFilter'));    
    
    my $probeListQuery    = '';
    my $probeList        = '';
    
    if($filterType eq "file")
    {
        $findProbes = SGX::FindProbes->new($dbh,$q);
        $findProbes->createInsideTableQueryFromFile();
        $findProbes->loadProbeReporterData($findProbes->getQueryTerms);
        $probeList     = $findProbes->getProbeList();
        $probeListQuery    = " WHERE rid IN (SELECT rid FROM probe WHERE reporter in ($probeList)) ";
    }
    elsif($filterType eq "list")
    {
        $findProbes = SGX::FindProbes->new($dbh,$q);
        $findProbes->createInsideTableQuery();
        $findProbes->loadProbeData($findProbes->getQueryTerms);
        $findProbes->setProbeList();
        $probeList     = $findProbes->getProbeList();
        $probeListQuery    = " WHERE rid IN (SELECT rid FROM probe WHERE reporter in ($probeList)) ";
    }

    #If we are filtering, generate the SQL statement for the rid's.    
    my $thresholdQuery    = '';
    my $query_titles     = '';
    my $query_fs         = 'SELECT fs, COUNT(*) as c FROM (SELECT BIT_OR(flag) AS fs FROM (';
    my $query_fs_body     = '';
    my (@eids, @reverses, @fcs, @pvals);

    my $i;
    for ($i = 1; defined($q->param("eid_$i")); $i++) 
    {
        my ($eid, $fc, $pval) = ($q->param("eid_$i"), $q->param("fc_$i"), $q->param("pval_$i"));
        my $reverse = (defined($q->param("reverse_$i"))) ? 1 : 0;
        
        #Prepare the four arrays that will be used to display data
        push @eids,     $eid; 
        push @reverses, $reverse; 
        push @fcs,         $fc; 
        push @pvals,     $pval;

        my @IDSplit = split(/\|/,$eid);

        my $currentSTID = $IDSplit[0];
        my $currentEID = $IDSplit[1];        
        
        #Flagsum breakdown query
        my $flag = 1 << $i - 1;

        #This is the normal threshold.
        $thresholdQuery    = " AND pvalue < $pval AND ABS(foldchange)  > $fc ";

        $query_fs_body .= "SELECT rid, $flag AS flag FROM microarray WHERE eid=$currentEID $thresholdQuery UNION ALL ";
        
        #This is part of the query when we are including all probes.
        if($allProbes eq "1")
        {
            $query_fs_body .= "SELECT rid, 0 AS flag FROM microarray WHERE eid=$currentEID AND rid NOT IN (SELECT RID FROM microarray WHERE eid=$currentEID $thresholdQuery) UNION ALL ";
        }

        # account for sample order when building title query
        my $title = ($reverse) ? "experiment.sample1, ' / ', experiment.sample2" : "experiment.sample2, ' / ', experiment.sample1";
        
        $query_titles .= " SELECT eid, CONCAT(study.description, ': ', $title) AS title FROM experiment NATURAL JOIN StudyExperiment NATURAL JOIN study WHERE eid=$currentEID AND StudyExperiment.stid=$currentSTID UNION ALL ";
    }

    my $exp_count = $i - 1;    # number of experiments being compared

    # strip trailing 'UNION ALL' plus any trailing white space
    $query_fs_body =~ s/UNION ALL\s*$//i;
    $query_fs = sprintf($query_fs, $exp_count) . $query_fs_body . ") AS d1 $probeListQuery GROUP BY rid) AS d2 GROUP BY fs";

    #Run the Flag Sum Query.
    my $sth_fs = $dbh->prepare(qq{$query_fs}) or croak $dbh->errstr;
    my $rowcount_fs = $sth_fs->execute or croak $dbh->errstr;
    my $h = $sth_fs->fetchall_hashref('fs');
    $sth_fs->finish;

    # strip trailing 'UNION ALL' plus any trailing white space
    $query_titles =~ s/UNION ALL\s*$//i;
    my $sth_titles = $dbh->prepare(qq{$query_titles}) or croak $dbh->errstr;
    my $rowcount_titles = $sth_titles->execute or croak $dbh->errstr;

    assert($rowcount_titles == $exp_count);
    my $ht = $sth_titles->fetchall_hashref('eid');
    $sth_titles->finish;

    my $rep_count = 0;
    my %hc;
    # initialize a hash using a slice:
    @hc{ 0 .. ($exp_count - 1) } = 0; #for ($i = 0; $i < $exp_count; $i++) { $hc{$i} = 0 }
    foreach my $value (values %$h) {
        for ($i = 0; $i < $exp_count; $i++) {
            # use of bitwise AND operator to test for bit presence
            $hc{$i} += $value->{c} if 1 << $i & $value->{fs};
        }
        $rep_count += $value->{c};
    }



    ### Draw a 450x300 area-proportional Venn diagram using Google API if $exp_count is (2,3)
    # http://code.google.com/apis/chart/types.html#venn
    # http://code.google.com/apis/chart/formats.html#data_scaling
    #
    my $out = '';
    switch ($exp_count) {
    case 2 {
        # draw two circles
        my @c;
        for ($i = 1; $i < 4; $i++) {
            # replace undefined values with zeros
            if (defined($h->{$i})) { push @c, $h->{$i}->{c} }
            else { push @c, 0 }
        }
        my $AB = $c[2];
        my $A = $hc{0}; 
        my $B = $hc{1}; 
        assert($A == $c[0] + $AB);
        assert($B == $c[1] + $AB);

        my @IDSplit1 = split(/\|/,$eids[0]);
        my @IDSplit2 = split(/\|/,$eids[1]);

        my $currentEID1 = $IDSplit1[1];        
        my $currentEID2 = $IDSplit2[1];

        my $scale = max($A, $B); # scale must be equal to the area of the largest circle
        my @nums = ($A, $B, 0, $AB);
        my $qstring = 'cht=v&amp;chd=t:'.join(',', @nums).'&amp;chds=0,'.$scale.
            '&amp;chs=450x300&chtt=Significant+Probes&amp;chco=ff0000,00ff00&amp;chdl='.
            uri_escape('1. '.$ht->{$currentEID1}->{title}).'|'.
            uri_escape('2. '.$ht->{$currentEID2}->{title});

        $out .= "var venn = '<img src=\"http://chart.apis.google.com/chart?$qstring\" />';\n";
    }
    case 3 {
        # draw three circles
        my @c;
        for ($i = 1; $i < 8; $i++) {
            # replace undefined values with zeros
            if (defined($h->{$i})) { push @c, $h->{$i}->{c} }
            else { push @c, 0 }
        }
        my $ABC = $c[6];
        my $AB = $c[2] + $ABC;
        my $AC = $c[4] + $ABC;
        my $BC = $c[5] + $ABC;
        my $A = $hc{0};
        my $B = $hc{1};
        my $C = $hc{2};
        assert($A == $c[0] + $c[2] + $c[4] + $ABC);
        assert($B == $c[1] + $c[2] + $c[5] + $ABC);
        assert($C == $c[3] + $c[4] + $c[5] + $ABC);

        my @IDSplit1 = split(/\|/,$eids[0]);
        my @IDSplit2 = split(/\|/,$eids[1]);
        my @IDSplit3 = split(/\|/,$eids[2]);

        my $currentEID1 = $IDSplit1[1];        
        my $currentEID2 = $IDSplit2[1];
        my $currentEID3 = $IDSplit3[1];

        my $scale = max($A, $B, $C); # scale must be equal to the area of the largest circle
        my @nums = ($A, $B, $C, $AB, $AC, $BC, $ABC);
        my $qstring = 'cht=v&amp;chd=t:'.join(',', @nums).'&amp;chds=0,'.$scale.
            '&amp;chs=450x300&chtt=Significant+Probes+(Approx.)&amp;chco=ff0000,00ff00,0000ff&amp;chdl='.
            uri_escape('1. '.$ht->{$currentEID1}->{title}).'|'.
            uri_escape('2. '.$ht->{$currentEID2}->{title}).'|'.
            uri_escape('3. '.$ht->{$currentEID3}->{title});

        $out .= "var venn = '<img src=\"http://chart.apis.google.com/chart?$qstring\" />';\n";
    }
    else {
        $out .= "var venn = '';\n";
    } }

    # Summary table -------------------------------------
$out .= '
var rep_count="'.$rep_count.'";
var eid="'.join(',',@eids).'";
var rev="'.join(',',@reverses).'";
var fc="'.join(',',@fcs).'";
var pval="'.join(',',@pvals).'";
var allProbes = "' . $allProbes . '";
var searchFilter = "' . $probeList . '";

var summary = {
caption: "Experiments compared",
records: [
';

    for ($i = 0; $i < @eids; $i++) 
    {
        my @IDSplit = split(/\|/,$eids[$i]);

        my $currentSTID = $IDSplit[0];
        my $currentEID = $IDSplit[1];        
        
        my $escapedTitle    = '';
        print '<tr><th>' . ($i + 1) . '</th><td>'.    $ht->{$currentEID}->{title} .'</td><td>'.$fcs[$i].'</td><td>'.$pvals[$i].'</td><td>'.$hc{$i}."</td></tr>\n";

        $escapedTitle        = $ht->{$currentEID}->{title};
        $escapedTitle        =~ s/\\/\\\\/g;
        $escapedTitle        =~ s/"/\\\"/g;

        $out .= '{0:"'. ($i + 1) . '",1:"' . $escapedTitle . '",2:"' . $fcs[$i] . '",3:"' . $pvals[$i] . '",4:"'.$hc{$i} . "\"},\n";
    }
    $out =~ s/,\s*$//;      # strip trailing comma
    $out .= '
]};
';

    # TFS breakdown table ------------------------------

    $out .= '
var tfs = {
caption: "View data for reporters significant in unique experiment combinations",
records: [
';

    # numerical sort on hash value
    # http://www.devdaily.com/perl/edu/qanda/plqa00016/
    #
    foreach my $key (sort {$h->{$b}->{fs} <=> $h->{$a}->{fs}} keys %$h) {
        $out .= '{0:"'.$key.'",';
        for ($i = 0; $i < $exp_count; $i++) {
            # use of bitwise AND operator to test for bit presence
            if (1 << $i & $h->{$key}->{fs})    { 
                $out .= ($i + 1).':"x",';
            } else {
                $out .= ($i + 1).':"",';
            }
        }
        $out .= ($i + 1).':"'.$h->{$key}->{c}."\"},\n";
    }
    $out =~ s/,\s*$//;      # strip trailing comma

    my $tfs_defs = "{key:\"0\", sortable:true, resizeable:false, label:\"FS\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},\n";
    my $tfs_response_fields = "{key:\"0\", parser:\"number\"},\n";
    for ($i = 1; $i <= $exp_count; $i++) {
        $tfs_defs .= "{key:\"$i\", sortable:true, resizeable:false, label:\"$i\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},\n";
        $tfs_response_fields .= "{key:\"$i\"},\n";
    }
    $tfs_defs .= "{key:\"$i\", sortable:true, resizeable:true, label:\"Reporters\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},
{key:\"".($i + 1)."\", sortable:false, resizeable:true, label:\"View probes\", formatter:\"formatDownload\"}\n";
    $tfs_response_fields .= "{key:\"$i\", parser:\"number\"},
{key:\"".($i + 1)."\", parser:\"number\"}\n";

    $out .= '
]};

YAHOO.util.Event.addListener(window, "load", function() {
    var Dom = YAHOO.util.Dom;
    Dom.get("eid").value = eid;
    Dom.get("rev").value = rev;
    Dom.get("fc").value = fc;
    Dom.get("pval").value = pval;
    Dom.get("allProbes").value = allProbes;
    Dom.get("searchFilter").value = searchFilter;
    Dom.get("venn").innerHTML = venn;
    Dom.get("summary_caption").innerHTML = summary.caption;
    var summary_table_defs = [
        {key:"0", sortable:true, resizeable:false, label:"&nbsp;"},
        {key:"1", sortable:true, resizeable:true, label:"Experiment"},
        {key:"2", sortable:true, resizeable:false, label:"&#124;Fold Change&#124; &gt;"}, 
        {key:"3", sortable:true, resizeable:false, label:"P &lt;"},
        {key:"4", sortable:true, resizeable:false, label:"Reporters"}
    ];
    var summary_data = new YAHOO.util.DataSource(summary.records);
    summary_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    summary_data.responseSchema = { fields: [
        {key:"0", parser:"number"},
        {key:"1"},
        {key:"2", parser:"number"},
        {key:"3", parser:"number"},
        {key:"4", parser:"number"}
    ]};
    var summary_table = new YAHOO.widget.DataTable("summary_table", summary_table_defs, summary_data, {});

    YAHOO.widget.DataTable.Formatter.formatDownload = function(elCell, oRecord, oColumn, oData) {
        var fs = oRecord.getData("0");
        elCell.innerHTML = "<input type=\"submit\" name=\"get\" value=\"TFS: " + fs + "\" />&nbsp;&nbsp;&nbsp;<input type=\"submit\" name=\"CSV\" value=\"(TFS: " + fs + " CSV)\" />";
    }
    Dom.get("tfs_caption").innerHTML = tfs.caption;
    Dom.get("tfs_all_dt").innerHTML = "View probes significant in at least one experiment:";
    Dom.get("tfs_all_dd").innerHTML = "<input type=\"submit\" name=\"get\" value=\"'.$rep_count.' significant probes\" /><input type=\"submit\" name=\"CSV\" value=\"(CSV)\" />";
    var tfs_table_defs = [
'.$tfs_defs.'
    ];
    var tfs_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 50 
        })
    };
    var tfs_data = new YAHOO.util.DataSource(tfs.records);
    tfs_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    tfs_data.responseSchema = {
        fields: ['.$tfs_response_fields.']
    };
    var tfs_table = new YAHOO.widget.DataTable("tfs_table", tfs_table_defs, tfs_data, tfs_config);
});
';
    
    $out;
}
#######################################################################################
sub compare_experiments {
    my %opts_dropdown = (
        '0'=>'Basic (ratios and p-value only)',
        '1'=>'Experiment data',
        '2'=>'Experiment data with annotations'
    );

    print    '<div id="venn"></div>',
        '<h2 id="summary_caption"></h2>',
        '<div id="summary_table" class="table_cont"></div>',
        $q->start_form(
            -method=>'POST',
            -action=>$q->url(-absolute=>1) . "?a=" . DOWNLOADTFS,
            -target=>'_blank',
            -class=>'getTFS',
            -enctype=>'application/x-www-form-urlencoded'
        ),
        $q->hidden(-name=>'a',-value=>DOWNLOADTFS, -override=>1),
        $q->hidden(-name=>'eid', -id=>'eid'),
        $q->hidden(-name=>'rev', -id=>'rev'),
        $q->hidden(-name=>'fc', -id=>'fc'),
        $q->hidden(-name=>'pval', -id=>'pval'),
        $q->hidden(-name=>'allProbes', -id=>'allProbes'),
        $q->hidden(-name=>'searchFilter', -id=>'searchFilter'),
        '<h2 id="tfs_caption"></h2>',
        $q->dl(
            $q->dt('Data to display:'),
            $q->dd($q->popup_menu(
                    -name=>'opts',
                    -values=>[keys %opts_dropdown], 
                    -default=>'0',
                    -labels=>\%opts_dropdown
            )),
            $q->dt({-id=>'tfs_all_dt'}, "&nbsp;"),
            $q->dd({-id=>'tfs_all_dd'}, "&nbsp;")
        ),
        '<div id="tfs_table" class="table_cont"></div>',
        $q->endform;
}
#######################################################################################
sub dump_table {
    # prints out the entire table in tab-delimited format
    #
    my $table = shift;
    my $sth = $dbh->prepare(qq{SELECT * FROM $table}) or croak $dbh->errstr;
    my $rowcount = $sth->execute or croak $dbh->errstr;

    # print the table head (fieldnames)
    print join("\t", @{$sth->{NAME}}), "\n";

    # print the data itself
    while (my $row = $sth->fetchrow_arrayref) {
        # NULL elements become undefined -- replace those,
        # otherwise the error_log will overfill with warnings
        foreach (@$row) { $_ = '' if !defined $_ }
        print join("\t", @$row), "\n";
    }
    $sth->finish;
}
#######################################################################################

#######################################################################################
sub show_tfs_js {

    if(defined($q->param('CSV')))
    {
        $s->commit();
        $TFSDisplay = SGX::TFSDisplay->new($dbh,$q);
        $TFSDisplay->loadDataFromSubmission();
        $TFSDisplay->getPlatformData();
        $TFSDisplay->loadAllData();
        $TFSDisplay->displayTFSInfoCSV();
    }
    else
    {
        $TFSDisplay = SGX::TFSDisplay->new($dbh,$q);
        $TFSDisplay->loadDataFromSubmission();
        $TFSDisplay->loadTFSData();
        $TFSDisplay->displayTFSInfo();
    }
}
#######################################################################################

#######################################################################################
sub show_tfs {
    print     '<h2 id="summary_caption"></h2>';
    #print    '<a href="' . $q->url(-query=>1) . '&CSV=1" target = "_blank">Output all data in CSV</a><br /><br />';
    print    '<div><a id="summ_astext">View as plain text</a></div>';
    print    '<div id="summary_table" class="table_cont"></div>';
    print    '<h2 id="tfs_caption"></h2>';
    print    '<div><a id="tfs_astext">View as plain text</a></div>';
    print    '<div id="tfs_table" class="table_cont"></div>';
}
#######################################################################################
sub get_annot_fields {
    # takes two arguments which are references to hashes that will store field names of two tables:
    # probe and gene
    my ($probe_fields, $gene_fields) = @_;

    # get fields from Probe table (except pid, rid)
    #my $sth = $dbh->prepare(qq{show columns from probe where Field not regexp "^[a-z]id\$"})
    #    or croak $dbh->errstr;
    #my $rowcount = $sth->execute or croak $dbh->errstr;
    #while (my @row = $sth->fetchrow_array) {
    #    $probe_fields->{$row[0]} = 1;
    #}
    #$sth->finish;

    $probe_fields->{"Reporter ID"}         = "reporter";
    $probe_fields->{"Probe Sequence"}     = "probe_sequence";
    $probe_fields->{"Note From Probe"}     = "note";

    # get fields from Gene table (except pid, gid)
    #$sth = $dbh->prepare(qq{show columns from gene where Field not regexp "^[a-z]id\$"})
    #    or croak $dbh->errstr;
    #$rowcount = $sth->execute or croak $dbh->errstr;
    #while (my @row = $sth->fetchrow_array) {
    #    $gene_fields->{$row[0]} = 1;
    #}
    #$sth->finish;

    $gene_fields->{"Gene Symbol"}         = "seqname";
    $gene_fields->{"Accession Number"}    = "accnum";
    $gene_fields->{"Gene Name"}         = "description";
    $gene_fields->{"Source"}             = "source";
    $gene_fields->{"Gene Note"}         = "gene_note";

}
#######################################################################################
sub form_uploadAnnot {

    #If we have a newpid in the querystring, default the dropdown list.
    my $newpid = '';
    $newpid = ($q->url_param('newpid')) if defined($q->url_param('newpid'));

    my $fieldlist;
    my %platforms;
    my %core_fields = (
        "Reporter ID"         => 1,
        "Accession Number"     => 1,
        "Gene Symbol"         => 1
    );

    # get a list of platforms and cutoff values
    my $sth = $dbh->prepare(qq{select pid, pname from platform})
        or croak $dbh->errstr;
    my $rowcount = $sth->execute
        or croak $dbh->errstr;
    while (my @row = $sth->fetchrow_array) {
        $platforms{$row[0]} = $row[1];
    }
    $sth->finish;

    my (%probe_fields, %gene_fields);

    get_annot_fields(\%probe_fields, \%gene_fields);

    foreach (keys %probe_fields) 
    {
        $fieldlist .= $q->li({-class=>($core_fields{$_}) ? 'core' : 'list1', -id=>$_}, $_);
    }

    foreach (keys %gene_fields) 
    {
        $fieldlist .= $q->li({-class=>($core_fields{$_}) ? 'core' : 'list1', -id=>$_}, $_);
    }

    print
    $q->h2('Upload Annotation'),
    $q->p('Only the fields specified below will be updated. You can specify fields by dragging field tags into the target area on the right and reordering them to match the column order in the tab-delimited file. When reporter (manufacturer-provided id) is among the fields uploaded, the existing annotation for the uploaded probes will be lost and replaced with the annotation present in the uploaded file. The "Add transcript accession numbers to existing probes" option will prevent the update program from deleting existing accession numbers from probes.'),
    $q->p('The default policy for updating probe-specific fields is to insert new records whenever existing records could not be matched on the probe core field (reporter id). The default policy for updating gene-specific fields is update-only, without insertion of new records. However, new gene records <em>are</em> inserted when both reporter id and either of the gene core fields (accnum, seqname) are specified.');

    print $q->div({-class=>'workarea'}, $q->h3('Available Fields:') .
        $q->ul({-id=>'ul1', -class=>'draglist'}, $fieldlist));
    print $q->div({-class=>'workarea'}, $q->h3('Fields in the Uploaded File:') .
        $q->ul({-id=>'ul2', -class=>'draglist'}));

    print $q->startform(-method=>'POST',
        -action=>$q->url(-absolute=>1).'?a='.UPLOADANNOT,
        -enctype=>'multipart/form-data');

    print $q->dl(
        $q->dt("Platform:"),
        $q->dd($q->popup_menu(
                -name=>'platform', 
                -values=>[keys %platforms], 
                -labels=>\%platforms, 
                -default=>$newpid
        )),
        $q->dt("File to upload (tab-delimited):"),
        $q->dd($q->filefield(-name=>'uploaded_file')),
        $q->dt("&nbsp;"),
        $q->dd($q->submit(-value=>'Upload'),
            $q->hidden(-id=>'fields', -name=>'fields'))
    );
    print $q->end_form;
}


#######################################################################################
sub uploadAnnot {

        ### Always backup first!!!

    my @fields;
    my $regex_split_on_commas = qr/ *, */;
    
    #Fields is an array of the fields from the input box.
    @fields = split($regex_split_on_commas, $q->param('fields')) if defined($q->param('fields'));
    
    #If the user didn't select enough fields on the input screen, warn them.
    if (@fields < 2) 
    {
        print $q->p('Too few fields specified -- nothing to update.');
        return;
    }

    # How the precompiled regular expression below works:
    # - Sometimes fields in the tab-delimited file are bounded by double quotes, like this "124442,34345,5656".
    #   We need to strip these quotes, however it would be nice to preserve the quotes if they are actually used for something,
    #   such as ""some" test", where the word "some" is enclosed in double quotes.
    # - The regex below matches 0 or 1 quotation mark at the beginning ^("?)
    #   and then backreferences the matched character at the end of the string \1$
    #   The actual content of the field is matched in (.*) and referenced outside regex as $2.
    my $regex_strip_quotes = qr/^("?)(.*)\1$/;

    #Create two hashes that hold hash{Long Name} = DBName
    my (%probe_fields, %gene_fields);
    
    get_annot_fields(\%probe_fields, \%gene_fields);

    my $i = 0;
    
    #This hash will hold hash{DBName} = index
    my %col;
    
    #Create a hash mapping record names to columns in the file
    foreach (@fields) 
    {
        # if the assertion below fails, the field specified by the user 
        # either doesn't exist or is protected.
        assert($probe_fields{$_} || $gene_fields{$_});
        
        if($probe_fields{$_})
        {
            $col{$probe_fields{$_}} = $i;
        }
        
        if($gene_fields{$_})
        {
            $col{$gene_fields{$_}} = $i;
        }

        $i++;
    }
    
    # delete core fields from field hash
    delete $probe_fields{"Reporter ID"};
    delete $gene_fields{"Accession Number"};
    delete $gene_fields{"Gene Symbol"};
    
    # create two slices of specified fields, one for each table
    my @slice_probe = @col{%probe_fields};
    my @slice_gene = @col{%gene_fields};
    
    @slice_probe = grep { defined($_) } @slice_probe;    # remove undef elements
    @slice_gene = grep { defined($_) } @slice_gene;        # remove undef elements
    
    my $gene_titles = '';
    foreach (@slice_gene) { $gene_titles .= ','.$gene_fields{$fields[$_]} }
    
    my $probe_titles = '';
    foreach (@slice_probe) { $probe_titles .= ','.$probe_fields{$fields[$_]} }
    
    my $reporter_index             = $col{reporter};    # probe table only is updated when this is defined and value is valid
    my $outside_have_reporter     = defined($reporter_index);
    my $accnum_index             = $col{accnum};
    my $seqname_index             = $col{seqname};
    my $outside_have_gene         = defined($accnum_index) || defined($seqname_index);
    my $pid_value                 = $q->param('platform');
    my $replace_accnum             = $outside_have_reporter && $outside_have_gene && !defined($q->param('add'));
    
    if (!$outside_have_reporter && !$outside_have_gene) 
    {
        print $q->p('No core fields specified -- cannot proceed with update.');
        return;
    }
    
    my $update_gene;

    # Access uploaded file
    my $fh = $q->upload('uploaded_file');
    # Perl 6 will allow setting $/ to a regular expression,
    # which would remove the need to read the whole file at once.
    local $/;    # sets input record separator to undefined, allowing "slurp" mode
    my $whole_file = <$fh>;
    close($fh);
    my @lines = split(/\s*(?:\r|\n)/, $whole_file);    # split on CRs or LFs while also removing preceding white space

    #my $clock0 = clock();
    foreach (@lines) {
        my @row = split(/ *\t */);    # split on a tab surrounded by any number (including zero) of blanks
        my @sql;

        my $have_reporter = 0;

        # probe fields -- updated only when reporter (core field for probe table) is specified
        if ($outside_have_reporter) {
            my $reporter_value;
            my $probe_values = '';
            my $probe_duplicates = '';
            foreach (@slice_probe) {
                my $value = $row[$_];
                # alternative one-liner:
                # $value = ($value && $value =~ $regex_strip_quotes && $2 && $2 ne '#N/A') ? $dbh->quote($2) : 'NULL';
                if ($value) {
                    $value =~ $regex_strip_quotes;
                    $value = ($2 && $2 ne '#N/A') ? $dbh->quote($2) : 'NULL';
                } else {
                    $value = 'NULL';
                }
                #$row[$_] = $value;
                $probe_values .= ','.$value;
                $probe_duplicates .= ','.$probe_fields{$fields[$_]}.'='.$value;
            }
            if (defined($reporter_index)) {
                $reporter_value = $row[$reporter_index];
                if ($reporter_value) {
                    $reporter_value =~ $regex_strip_quotes;
                    $reporter_value = ($2 && $2 ne '#N/A') ? $dbh->quote($2) : 'NULL';
                } else {
                    $reporter_value = 'NULL';
                }
                $have_reporter++ if $reporter_value ne 'NULL';
            }
            if ($have_reporter) {
                # TODO: ensure new rows are not inserted into the Probe table
                # unless we are explicitly setting up a new platform.
                #
                # if reporter was not specified, will not be able to obtain rid and update the "annotates" table
                push @sql, qq{insert into probe (pid, reporter $probe_titles) values ($pid_value, $reporter_value $probe_values) on duplicate key update rid=LAST_INSERT_ID(rid) $probe_duplicates};
                push @sql, qq{set \@rid:=LAST_INSERT_ID()};
                # only delete "annotates" content, not the "gene" content.
                # Then, when everything is done, can go over the entire "gene" table and try to delete records.
                # Successful delete means the records were orphaned (not pointed to from the "annotates" table).
                push (@sql, qq{delete quick ignore from annotates where rid=\@rid}) if $replace_accnum;
            }
        }

        my @accnum_array;
        my $have_seqname = 0;
        my $seqname_value;

        # gene fields -- updated when any of the core fields are specified
        foreach (@slice_gene) {
            my $value = $row[$_];
            if ($value) {
                $value =~ $regex_strip_quotes;
                $value = ($2 && $2 ne '#N/A') ? $dbh->quote($2) : 'NULL';
            } else {
                $value = 'NULL';
            }
            $row[$_] = $value;
        }
        if ($outside_have_gene) {
            my $gene_values = '';
            $update_gene = '';
            foreach (@slice_gene) {
                $gene_values .= ','.$row[$_];
                $update_gene .= ','.$gene_fields{$fields[$_]}.'='.$row[$_];
            }

            if (defined($seqname_index)) {
                $seqname_value = $row[$seqname_index];
                if ($seqname_value) {
                    $seqname_value =~ $regex_strip_quotes;
                    $seqname_value = ($2 && $2 ne '#N/A' && $2 ne 'Data not found') ? $dbh->quote($2) : 'NULL';
                } else {
                    $seqname_value = 'NULL';
                }
                $have_seqname++ if $seqname_value ne 'NULL';
            }
            if (defined($accnum_index)) {
                # The two lines below split the value matched by the regular expression (stored in $2)
                # on a comma surrounded by any number (including zero) of blanks, delete invalid members 
                # from the resulting array, quote each member with DBI::quote, and assign the array to @accnum_array.
                $row[$accnum_index] =~ $regex_strip_quotes;
                @accnum_array = map { $dbh->quote($_) } grep { $_ && $_ ne '#N/A' } split($regex_split_on_commas, $2);

                # Iterate over the resulting array
                if ($have_reporter && @accnum_array) {
                    push @sql, qq{update gene natural join annotates set seqname=$seqname_value where rid=\@rid};
                    foreach (@accnum_array) {
                        push @sql, qq{insert into gene (accnum, seqname $gene_titles) values ($_, $seqname_value $gene_values) on duplicate key update gid=LAST_INSERT_ID(gid) $update_gene};
                        push @sql, qq{insert ignore into annotates (rid, gid) values (\@rid, LAST_INSERT_ID())};
                    }
                }
            }
            if ($have_reporter && !@accnum_array && $have_seqname) {
                # have gene symbol but not transcript accession number
                push @sql, qq{update gene natural join annotates set seqname=$seqname_value where rid=\@rid};
                push @sql, qq{insert into gene (seqname $gene_titles) values ($seqname_value $gene_values) on duplicate key update gid=LAST_INSERT_ID(gid) $update_gene};
                push @sql, qq{insert ignore into annotates (rid, gid) values (\@rid, LAST_INSERT_ID())};
            }
        }
        if (@slice_gene) {
            if (!$outside_have_gene) {
                # if $outside_have_gene is true, $update_gene string has been formed already
                $update_gene = '';
                foreach (@slice_gene) {
                    # title1 = value1, title2 = value2, ...
                    $update_gene .= ','.$gene_fields{$fields[$_]} .'='.$row[$_];
                }
            }
            $update_gene =~ s/^,//;      # strip leading comma
            if ($have_reporter) {
                if (!@accnum_array && !$have_seqname && !$replace_accnum) {
                    # if $replace_accnum was specified, all rows from annotates table where rid=@rid
                    # have already been deleted, so no genes would be updated anyway
                    push @sql, qq{update gene natural join annotates set $update_gene where rid=\@rid};
                }
            } else {
                if (!@accnum_array && $have_seqname) {
                    my $eq_seqname = ($seqname_value eq 'NULL') ? 'is NULL' : "=$seqname_value";
                    push @sql, qq{update gene set $update_gene where seqname $eq_seqname and pid=$pid_value};
                } elsif (@accnum_array && !$have_seqname) {
                    foreach (@accnum_array) {
                        my $eq_accnum = ($_ eq 'NULL') ? 'is NULL' : "=$_";
                        push @sql, qq{update gene set $update_gene where accnum $eq_accnum and pid=$pid_value};
                    }
                } elsif (@accnum_array && $have_seqname) {
                    my $eq_seqname = ($seqname_value eq 'NULL') ? 'is NULL' : "=$seqname_value";
                    foreach (@accnum_array) {
                        my $eq_accnum = ($_ eq 'NULL') ? 'is NULL' : "=$_";
                        push @sql, qq{update gene set $update_gene where accnum $eq_accnum and seqname $eq_seqname and pid=$pid_value};
                    }
                }
            }
        }

        # execute the SQL statements
        foreach(@sql) {
            #warn $_;
            #print $_;
            $dbh->do($_) or croak $dbh->errstr;
        }
    }
    #my $clock1 = clock();

    if ($outside_have_reporter && $replace_accnum) {
        #warn "begin optimizing\n";
        # have to "optimize" because some of the deletes above were performed with "ignore" option
        $dbh->do('optimize table annotates') 
            or croak $dbh->errstr;
        # in case any gene records have been orphaned, delete them
        $dbh->do(
            'delete gene from gene left join annotates on gene.gid=annotates.gid where annotates.gid is NULL'
        ) or croak $dbh->errstr;
        #warn "end optimizing\n";
    }
    my $count_lines = @lines;
    #print $q->p(sprintf("%d lines processed in %g seconds", $count_lines, $clock1 - $clock0));
    print $q->p(sprintf("%d lines processed.", $count_lines));
    
    #Flag the platform as being annotated.
    $dbh->do(
        'UPDATE platform SET isAnnotated=1 WHERE pid=?',
        undef,
        $pid_value
    ) or croak $dbh->errstr;

}

sub cleanSQLString
{
    my $value = shift;
    my $regex_strip_quotes = qr/^("?)(.*)\1$/;

    if ($value) 
    {
        $value =~ $regex_strip_quotes;
        $value = ($2 && $2 ne '#N/A') ? $dbh->quote($2) : 'NULL';
    } 
    else 
    {
        $value = 'NULL';
    }

    return $value;

}

#===  FUNCTION  ================================================================
#         NAME:  managePlatforms
#      PURPOSE:  dispatch requests related to Manage Platforms functionality
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub managePlatforms
{
    my $managePlatform = SGX::ManageMicroarrayPlatforms->new($dbh,$q);
    $managePlatform->dispatch($q->url_param('ManageAction'));
}

#===  FUNCTION  ================================================================
#         NAME:  manageProjects
#      PURPOSE:  dispatch requests related to Manage Projects functionality
#   PARAMETERS:  
#      RETURNS:  
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub manageProjects
{
    my $mp = SGX::ManageProjects->new($dbh,$q, JS_DIR);
    $mp->dispatch($q->url_param('ManageAction'));
}

#===  FUNCTION  ================================================================
#         NAME:  manageStudies
#      PURPOSE:  dispatch requests related to Manage Studies funcitonality
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub manageStudies
{
    my $ms = SGX::ManageStudies->new($dbh,$q, JS_DIR);
    $ms->dispatch($q->url_param('ManageAction'));
}

#===  FUNCTION  ================================================================
#         NAME:  manageExperiments
#      PURPOSE:  dispatch requests related to Manage Experiments functionality
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub manageExperiments
{
    my $me = SGX::ManageExperiments->new($dbh,$q, JS_DIR);
    $me->dispatch($q->url_param('ManageAction'));
}


#===  FUNCTION  ================================================================
#         NAME:  outputData
#      PURPOSE:  dispatch requests related to Output Data functionality
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub outputData
{
    my $od = SGX::OutputData->new($dbh,$q, JS_DIR);
    $od->dispatch($q->url_param('outputAction'));
}

#===  FUNCTION  ================================================================
#         NAME:  chooseProject
#      PURPOSE:  dispatch requests related to Choose Project functionality
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub chooseProject
{
    my $cp = SGX::ChooseProject->new($dbh,$q,$s->{data}->{curr_proj});
    $cp->dispatch($q->url_param('projectAction'));
}


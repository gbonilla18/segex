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
use JSON::XS;
use Tie::IxHash;

#---------------------------------------------------------------------------
# Custom modules in SGX directory
#---------------------------------------------------------------------------
use lib 'SGX';

use SGX::Debug;        # all debugging code goes here
use SGX::Config;    # all configuration for our project goes here
use SGX::Util qw/trim max/;
use SGX::User 0.07;    # user authentication, sessions and cookies
use SGX::Session 0.08;    # email verification
use SGX::ManageMicroarrayPlatforms;
use SGX::ManageProjects;
use SGX::ManageStudies;
use SGX::ManageExperiments;
use SGX::OutputData;
use SGX::JavaScriptDeleteConfirm;
use SGX::TFSDisplay;
use SGX::FindProbes qw/getform_findProbes/;
use SGX::ChooseProject;

#---------------------------------------------------------------------------
#  User Authentication
#---------------------------------------------------------------------------
# :NOTE:06/17/2011 12:57:58:es: bump up version from 0.1.12 to 0.2.0
# :NOTE:06/17/2011 16:59:33:es: bump up version to 0.2.1
my $softwareVersion = '0.2.1';

my $dbh = sgx_db_connect();
my $s = SGX::User->new(-handle        => $dbh,
               -expire_in    => 3600, # expire in 3600 seconds (1 hour)
               -check_ip    => 1);

$s->restore();    # restore old session if it exists


#---------------------------------------------------------------------------
#  Main
#---------------------------------------------------------------------------
my $q = CGI->new();
my $error_string;
my $title;
my $css = [
    {-src=>YUI_BUILD_ROOT . '/reset-fonts/reset-fonts.css'},
    {-src=>YUI_BUILD_ROOT . '/container/assets/skins/sam/container.css'},
    {-src=>YUI_BUILD_ROOT . '/paginator/assets/skins/sam/paginator.css'},
    {-src=>YUI_BUILD_ROOT . '/datatable/assets/skins/sam/datatable.css'},
    {-src=>CSS_DIR . '/style.css'}
];

my @js_src_yui;
my @js_src_code = ({-src=>'prototype.js'}, {-src=>'form.js'});

my $content;    # this will be a reference to a subroutine that displays the main content

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
            push @js_src_yui, (
                'yahoo-dom-event/yahoo-dom-event.js',
                'animation/animation-min.js', 
                'dragdrop/dragdrop-min.js'
            );
            push @js_src_code, {-src=>'annot.js'};
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
            my $chooseProj = SGX::ChooseProject->new($dbh, $q, $project_set_to);

            # store id in a permanent cookie (also gets copied to the session cookie
            # automatically)
            $s->perm_cookie_store(curr_proj => $project_set_to);

            # store name in the session cookie only
            $s->session_cookie_store(
                proj_name => $chooseProj->lookupProjectName()
            );

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
            push @js_src_yui, (
                'yahoo-dom-event/yahoo-dom-event.js',
                'connection/connection-min.js',
                'dragdrop/dragdrop-min.js',
                'container/container-min.js',
                'element/element-min.js',
                'datasource/datasource-min.js',
                'paginator/paginator-min.js',
                'datatable/datatable-min.js',
                'selector/selector-min.js'
            );
        
            $content = \&managePlatforms;
            $title = 'Platforms';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case MANAGEPROJECTS {
        if ($s->is_authorized('user')) {

            push @js_src_yui, (
                'yahoo-dom-event/yahoo-dom-event.js',
                'connection/connection-min.js',
                'dragdrop/dragdrop-min.js',
                'container/container-min.js',
                'element/element-min.js',
                'datasource/datasource-min.js',
                'paginator/paginator-min.js',
                'datatable/datatable-min.js',
                'selector/selector-min.js'
            );

            $content = \&manageProjects;
            $title = 'Projects';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case MANAGESTUDIES {
        if ($s->is_authorized('user')) {
            push @js_src_yui, (
                'yahoo-dom-event/yahoo-dom-event.js',
                'connection/connection-min.js',
                'dragdrop/dragdrop-min.js',
                'container/container-min.js',
                'element/element-min.js',
                'datasource/datasource-min.js',
                'paginator/paginator-min.js',
                'datatable/datatable-min.js',
                'selector/selector-min.js'
            );

            $content = \&manageStudies;

            $title = 'Studies';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case MANAGEEXPERIMENTS {
        if ($s->is_authorized('user')) {
            push @js_src_yui, (
                'yahoo-dom-event/yahoo-dom-event.js',
                'connection/connection-min.js',
                'dragdrop/dragdrop-min.js',
                'container/container-min.js',
                'element/element-min.js',
                'datasource/datasource-min.js',
                'paginator/paginator-min.js',
                'datatable/datatable-min.js',
                'selector/selector-min.js'
            );

            $content = \&manageExperiments;
            $title = 'Experiments';
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case OUTPUTDATA {
        if ($s->is_authorized('user')) {
            push @js_src_yui, (
                'yahoo-dom-event/yahoo-dom-event.js',
                'connection/connection-min.js',
                'dragdrop/dragdrop-min.js',
                'container/container-min.js',
                'element/element-min.js',
                'datasource/datasource-min.js',
                'paginator/paginator-min.js',
                'datatable/datatable-min.js',
                'selector/selector-min.js'
            );

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
            push @js_src_code, {-code =>'
Event.observe(window, "load", init);
function init() {
    sgx_toggle($("graph").checked, ["graph_option_names", "graph_option_values"]);
}'
};
            $content = \&form_findProbes;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case FINDPROBES                {
        if ($s->is_authorized('user')) {
            $title = 'Find Probes';
            my $findProbes = SGX::FindProbes->new($dbh, cgi => $q, user_session => $s);
            # push YUI dependencies to @js_src_yui array
            $findProbes->list_yui_deps(\@js_src_yui);
            # push data + JS code to @js_src_code array
            push @js_src_code, {-code=>$findProbes->findProbes_js($s)};
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
            print $q->header(-type=>'text/plain', -cookie=>$s->cookie_array());
            dump_table($table);
            $action = QUIT;
        } else {
            $action = FORM.LOGIN;
        }
    }
    case DOWNLOADTFS            {
        if ($s->is_authorized('user')) {
            $title = 'View Slice';

            push @js_src_yui, (
                'yahoo-dom-event/yahoo-dom-event.js',
                'element/element-min.js',
                'paginator/paginator-min.js',
                'datasource/datasource-min.js',
                'datatable/datatable-min.js',
                'yahoo/yahoo.js'
            );
            push @js_src_code, {-code =>show_tfs_js()};

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
                   -cookie    => $s->cookie_array());
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
            push @js_src_code, {-code=>form_compareExperiments_js()};
            push @js_src_code, {-src=>'experiment.js'};
            $content = \&form_compareExperiments;
            $action = undef;    # final state
        } else {
            $action = FORM.LOGIN;
        }
    }
    case COMPAREEXPERIMENTS        {
        if ($s->is_authorized('user')) {
            $title = 'Compare Experiments';

            push @js_src_yui, (
                'yahoo-dom-event/yahoo-dom-event.js',
                'element/element-min.js',
                'paginator/paginator-min.js',
                'datasource/datasource-min.js',
                'datatable/datatable-min.js'
            );
            push @js_src_code, {-code=>compare_experiments_js()};

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
            #$s->read_perm_cookie(); # already read by authenticate()
            my $chooseProj = SGX::ChooseProject->new($dbh, $q, $s->{session_cookie}->{curr_proj});

            # no need to store the working project name in permanent storage (only store
            # the working project id there) -- store it only in the session cookie
            # (which is read every time session is initialized).
            
            $s->session_cookie_store(
                proj_name => $chooseProj->lookupProjectName()
            );

            my $destination = (defined($q->url_param('destination'))) 
                ? uri_unescape($q->url_param('destination')) 
                : undef;
            if (defined($destination) && 
                $destination ne $q->url(-absolute=>1) && 
                $destination !~ m/(?:&|\?|&amp;)a=$action(?:\z|&|#)/ && 
                $destination !~ m/(?:&|\?|&amp;)a=form_$action(?:\z|&|#)/) 
            {
                # will send a redirect header, so commit the session to data store now
                $s->commit();

                # if the user is heading to a specific placce, pass him/her along,
                # otherwise continue to the main page (script_name)
                # do not add nph=>1 parameter to redirect() because that will cause it to crash
                print $q->redirect(-uri        => $q->url(-base=>1).$destination,
                           -status    => 302,     # 302 Found
                           -cookie    => $s->cookie_array());
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
            if ($s->change_email(
                    password => $q->param('password'), 
                    email1 => $q->param('email1'),
                    email2 => $q->param('email2'),
                    project_name => PROJECT_NAME,
                    login_uri => $q->url(-full=>1).'?a='.VERIFYEMAIL, 
                    error => \$error_string)) 
            {
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
            $title = 'Sign up';
            $content = \&form_registerUser;
            $action = undef;    # final state
        }
    }
    case REGISTERUSER        {
        if ($s->is_authorized('unauth')) {
            $action = DEFAULT_ACTION;
        } else {
            if ($s->register_user(
                username => $q->param('username'),
                password1 => $q->param('password1'),
                password2 => $q->param('password2'),
                email1 => $q->param('email1'), 
                email2 => $q->param('email2'),
                full_name => $q->param('full_name'),
                address => $q->param('address'),
                phone => $q->param('phone'),
                project_name => PROJECT_NAME,
                login_uri => $q->url(-full=>1).'?a='.VERIFYEMAIL,
                error => \$error_string)) 
            {
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
                if ($s->verify_email($t->{session_stash}->{username})) {
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
                -title=>'You are signed in as '.$s->{session_stash}->{username}.'. Click on this link to log out.'},'Log out');
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

print $q->header(-type=>'text/html', -cookie=>$s->cookie_array());

cgi_start_html();

print $q->img({src=>IMAGES_DIR . '/logo.png', width=>448, height=>108, alt=>PROJECT_NAME, title=>PROJECT_NAME});

print $q->ul({-id=>'menu'},$q->li(\@menu));

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

cgi_end_html();

#######################################################################################
sub cgi_start_html {
# to add plain javascript code to the header, add the following to the -script array:
# {-type=>'text/javasccript', -code=>$JSCRIPT}
    my @js;
    foreach (@js_src_yui) {
        push @js, {-type=>'text/javascript', -src=>YUI_BUILD_ROOT . '/' . $_}
    }
    foreach (@js_src_code) {
        $_->{-type} = 'text/javascript';
        if (defined($_->{-src})) {
            $_->{-src} = JS_DIR . '/' . $_->{-src};
        }
        push @js, $_;
    }

    print $q->start_html(
            -title=>PROJECT_NAME." : $title",
            -style=>$css,
            -script=>\@js,
            -class=>'yui-skin-sam',
            -head=>[$q->Link({-type=>'image/x-icon',-href=>IMAGES_DIR.'/favicon.ico',-rel=>'icon'})]
        );
    print '<div id="content">';
    return;
}
#######################################################################################
sub cgi_end_html {
    print '</div>';
    print footer();
    #print projectInfo();
    print $q->end_html;
    return;
}
#######################################################################################
sub main {
    print main_text();
    return;
}
#######################################################################################
sub about {
    print $q->h2('About');
    print about_text();
    return;
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
            $q->submit(-name=>'login',-id=>'login',-class=>'css3button',-value=>'Login'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.RESETPASSWORD,
                -title=>'Email me a new password'},'I Forgot My Password'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.REGISTERUSER,
                -title=>'Set up a new account'}, 'Sign up')
        )
    )
    .
    $q->end_form;
    return;
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
            $q->submit(-name=>'resetPassword',-id=>'resetPassword',-class=>'css3button',-value=>'Email new password'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.LOGIN,
                -title=>'Back to login page'},'Back')
        )
    ) .
    $q->end_form;
    return;
}
#######################################################################################
sub resetPassword_success {
    print $q->p($s->reset_password_text()) .
    $q->p($q->a({-href=>$q->url(-absolute=>1),
             -title=>'Back to login page'},'Back'));
    return;
}
#######################################################################################
sub registration_success {
    print $q->p($s->register_user_text()) .
    $q->p($q->a({-href=>$q->url(-absolute=>1),
             -title=>'Back to login page'},'Back'));
    return;
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
            $q->submit(-name=>'changePassword',-id=>'changePassword',-class=>'css3button',-value=>'Change password'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
                -title=>'Back to my profile'},'Back')
        )
    ) .
    $q->end_form;
    return;
}
#######################################################################################
sub changePassword_success {
    print $q->p('You have successfully changed your password.') .
    $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
             -title=>'Back to my profile'},'Back'));
    return;
}
#######################################################################################
sub verifyEmail_success {
    print $q->p('You email address has been verified.') .
    $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
             -title=>'Back to my profile'},'Back'));
    return;
}
#######################################################################################
sub form_changeEmail {
    # user has to be logged in
    print $q->h2('Change Email Address'),
    $q->start_form(
        -method=>'POST',
        -action=>$q->url(-absolute=>1).'?a='.CHANGEEMAIL,
        -onsubmit=>'return validate_fields(this, [\'password\',\'email1\',\'email2\']);'
    ) .
    $q->dl(
        $q->dt('Password:'),
        $q->dd($q->password_field(-name=>'password',-id=>'password',-maxlength=>40)),
        $q->dt('New Email Address:'),
        $q->dd($q->textfield(-name=>'email1',-id=>'email1')),
        $q->dt('Confirm New Address:'),
        $q->dd($q->textfield(-name=>'email2',-id=>'email2')),
        $q->dt('&nbsp;'),
        $q->dd(
            form_error($error_string),
            $q->submit(-name=>'changeEmail',-id=>'changeEmail',-class=>'css3button',-value=>'Change email'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
                -title=>'Back to my profile'},'Back')
        )
    ) .
    $q->end_form;
    return;
}
#######################################################################################
sub changeEmail_success {
    print $q->p($s->change_email_text()) .
    $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
         -title=>'Back to my profile'},'Back'));
    return;
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
    return;
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
            $q->submit(-name=>'registerUser',-id=>'registerUser',-class=>'css3button',-value=>'Register'),
            $q->span({-class=>'separator'},' / '),
            $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.LOGIN,
                -title=>'Back to login page'},'Back')
        )
    ) .
    $q->end_form;
    return;
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
sub form_findProbes
{
    print getform_findProbes($q, FINDPROBES);
    return;
}
#######################################################################################

#######################################################################################
sub findProbes {
    print    '<h2 id="caption"></h2>',
        '<div><a id="probetable_astext">View as plain text</a></div>',
        '<div id="probetable"></div>';
    print '<ul id="graphs"></ul>' if defined($q->param('graph'));
    return;
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
    return;
}
#######################################################################################
sub form_compareExperiments_js {
 # :TODO:06/14/2011 17:19:36:es: Only one query should be enough to select a list of
 # platforms and studies
    my $out = '';

    # find out what the current project is set to
    #$s->read_perm_cookie();
    my $curr_proj = $s->{session_cookie}->{curr_proj};

    # get a list of platforms and cutoff values
    my $query_text;
    my @query_params;
    if (!defined($curr_proj) || $curr_proj eq '') {
        # current project not set or set to 'All Projets'
        $query_text = qq{SELECT pid, pname, def_p_cutoff, def_f_cutoff FROM platform};
    } else {
        # current project is set
        push @query_params, $curr_proj;
        $query_text = <<"END_PLATFORM_QUERY"
SELECT pid, pname, def_p_cutoff, def_f_cutoff 
FROM platform 
RIGHT JOIN study USING(pid) 
RIGHT JOIN ProjectStudy USING(stid)
WHERE prid=? 
GROUP BY pid

END_PLATFORM_QUERY
    }
    my $sth = $dbh->prepare($query_text)
        or croak $dbh->errstr;
    my $rowcount = $sth->execute(@query_params)
        or croak $dbh->errstr;
    assert($rowcount);

    ### populate a Javascript hash with the content of the platform recordset
    $out .= "Event.observe(window, 'load', init);\n";
    $out .= 'var form = "' . FORM.COMPAREEXPERIMENTS . "\";\n";

    my %json_platform;
    while (my @row = $sth->fetchrow_array) {
        # format:
        # 0 - platform id => [
        #   1 - platform name
        #   2 - P-value cutoff
        #   3 - fold-change cutoff 
        # ];
        $json_platform{$row[0]} = [ $row[1], $row[2], $row[3] ];
    }
    $sth->finish;

    $out .= 'var platform = ' . encode_json(\%json_platform) . ";\n";

    # get a list of studies
    if (!defined($curr_proj) || $curr_proj eq '') {
        # current project not set or set to 'All Projects'
        $sth = $dbh->prepare(qq{select stid, description, pid from study})
            or croak $dbh->errstr;
        $rowcount = $sth->execute
            or croak $dbh->errstr;
    } else {
        # current project is set
        $sth = $dbh->prepare(qq{select stid, description, pid from study RIGHT JOIN ProjectStudy USING(stid) WHERE prid=? group by stid})
            or croak $dbh->errstr;
        $rowcount = $sth->execute($curr_proj)
            or croak $dbh->errstr;
    }
    assert($rowcount);

    ### populate a Javascript hash with the content of the study recordset
    my %json_study;
    while (my @row = $sth->fetchrow_array) {
        # format:
        # study_id => [
        #   0 - study description
        #   1 - sample 1 name
        #   2 - sample 2 name
        #   3 - platform id
        # ];
        $json_study{$row[0]} = [$row[1], {}, {}, $row[2] ];
    }
    $sth->finish;

    # get a list of all experiments
    if (!defined($curr_proj) || $curr_proj eq '') {
        $sth = $dbh->prepare(<<"END_EXP_QUERY")
select stid, eid, experiment.sample2 as s2_desc, experiment.sample1 as s1_desc 
from study 
inner join StudyExperiment USING(stid)
inner join experiment using(eid)

END_EXP_QUERY
            or croak $dbh->errstr;
        $rowcount = $sth->execute
            or croak $dbh->errstr;
    } else {
        $sth = $dbh->prepare(<<"END_EXP_QUERY")
select stid, eid, experiment.sample2 as s2_desc, experiment.sample1 as s1_desc 
from experiment
inner join StudyExperiment USING(eid)
inner join study using(stid)
inner join ProjectStudy USING(stid)
WHERE prid = ?
GROUP BY eid

END_EXP_QUERY
            or croak $dbh->errstr;
        $rowcount = $sth->execute($curr_proj)
            or croak $dbh->errstr;
    }
        assert($rowcount);

    ### populate the Javascript hash with the content of the experiment recordset
    while (my @row = $sth->fetchrow_array) {
        $json_study{$row[0]}->[1]->{$row[1]} = $row[2];
        $json_study{$row[0]}->[2]->{$row[1]} = $row[3];
    }
    $sth->finish;

    $out .= 'var study = ' . encode_json(\%json_study) . ";\n";

    $out .= '
function init() {
    populatePlatforms("platform");
    addExperiment();
}
';
    $out;
}
#######################################################################################
sub form_compareExperiments {

    my %geneFilter_dropdown;
    my $geneFilter_dropdown_t = tie(%geneFilter_dropdown, 'Tie::IxHash',
        'none'=>'No Filtering',
        'list'=>'List of Terms',
        'file'=>'Uploaded File'
    );
    my %gene_dropdown;
    my $gene_dropdown_t = tie(%gene_dropdown, 'Tie::IxHash',
        'gene'=>'Gene Symbols',
        'transcript'=>'Transcripts',
        'probe'=>'Probes'
    );
    my %match_dropdown;
    my $match_dropdown_t = tie(%match_dropdown, 'Tie::IxHash',
        'full'=>'Full Word',
        'prefix'=>'Prefix',
        'part'=>'Part of the Word / Regular Expression*'
    );

    print $q->h2('Compare Experiments');
    print 
    $q->dl(
        $q->dt('Add experiment from platform:'),
        $q->dd(    $q->popup_menu(-name=>'platform', -id=>'platform', -onChange=>"updatePlatform(this);"),
            $q->span({-class=>'separator'},' : '),
            $q->button(
                -value=>'Add experiment',
                -class=>'plaintext',
                -onclick=>'addExperiment();'
            )
        )
    );
    print
    $q->start_form(
            -method=>'POST',
            -id=>FORM.COMPAREEXPERIMENTS,
            -action=>$q->url(absolute=>1).'?a='.COMPAREEXPERIMENTS
    ),
    $q->dl(
        $q->dt('Include all probes in output:'),
        $q->dd($q->checkbox(-name=>'chkAllProbes',-id=>'chkAllProbes',-value=>'1',-label=>''),
            $q->p({-style=>'color:#777;'}, 'Probes without a TFS will be labeled \'TFS 0\'')
        ),
        $q->dt('Filter on:'),
        $q->dd($q->radio_group(
                -tabindex=>2,
                -onChange=>'toggleFilterOptions(this.value);', 
                -name=>'geneFilter', 
                -values=>[keys %geneFilter_dropdown], 
                -default=>'none', 
                -labels=>\%geneFilter_dropdown
        ))
    ),
    $q->div({-id=>'divSearchItemsDiv',-name=>'divSearchItemsDiv',-style=>'display:none;'},
        $q->h3('Filter on input file'),
        $q->dl(
            $q->dt('Upload File:'),
            $q->dd(
                $q->filefield(-name=>'gene_file'),
                $q->p({-style=>'color:#777;'}, 'The file must be in plain-text format
                    with one search term per line')
            ),
            $q->dt('Terms are:'),
            $q->dd($q->popup_menu(
                       -name=>'type',
                       -values=>[keys %gene_dropdown],
                       -default=>'gene',
                       -labels=>\%gene_dropdown
                   )
            ),
            $q->dt('Patterns to match:'),
            $q->dd({-style=>'color:#777;'},'Full Word')
        )
    ),
    $q->div({-id=>'divSearchItemsDiv2',-name=>'divSearchItemsDiv2',-style=>'display:none;'},
        $q->h3('Filter on input list'),
        $q->dl(
            $q->dt('Search term(s):'),
            $q->dd($q->textarea(-name=>'address',-id=>'address',-rows=>10,-columns=>50,-tabindex=>1,
                -name=>'text')),

            $q->dt('Terms are:'),
            $q->dd($q->popup_menu(
                       -name=>'type',
                       -values=>[keys %gene_dropdown],
                       -default=>'gene',
                       -labels=>\%gene_dropdown
                   )
            ),
            $q->dt('Patterns to match:'),
            $q->dd($q->radio_group(
                          -tabindex=>2, 
                          -name=>'match', 
                          -values=>[keys %match_dropdown], 
                          -default=>'full', 
                          -linebreak=>'true', 
                          -labels=>\%match_dropdown
                  )
            )
        )
    ),
    $q->dl(
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(-name=>'submit',-class=>'css3button',-value=>'Compare', -override=>1),
            $q->hidden(-name=>'a',-value=>COMPAREEXPERIMENTS, -override=>1)
        )
    ),
    $q->endform;
    return;
}

#######################################################################################
sub compare_experiments_js {
    #print $q->header(-type=>'text/html', -cookie=>$s->cookie_array());
    #This flag tells us whether or not to ignore the thresholds.
    my $allProbes         = '';
    $allProbes             = ($q->param('chkAllProbes')) if defined($q->param('chkAllProbes'));
    
    my $searchFilter    = '';
    $searchFilter         = ($q->param('chkUseGeneList')) if defined($q->param('chkUseGeneList'));

    my $filterType        = '';
    $filterType         = ($q->param('geneFilter')) if defined($q->param('geneFilter'));    
    
    my $probeListQuery    = '';
    my $probeList        = '';
    
    #$s->read_perm_cookie();
    my $curr_proj = $s->{session_cookie}->{curr_proj};

    if($filterType eq "file")
    {
        my $findProbes = SGX::FindProbes->new($dbh, cgi => $q);
        $findProbes->{_WorkingProject} = $curr_proj;
        $findProbes->createInsideTableQueryFromFile();
        $findProbes->loadProbeReporterData($findProbes->getQueryTerms);
        $probeList     = $findProbes->getProbeList();
        #$probeListQuery    = " WHERE rid IN (SELECT rid FROM probe WHERE reporter in ($probeList)) ";
        $probeListQuery    = " WHERE rid IN ($probeList) ";
    }
    elsif($filterType eq "list")
    {
        my $findProbes = SGX::FindProbes->new($dbh, cgi => $q);
        $findProbes->{_WorkingProject} = $curr_proj;
        $findProbes->createInsideTableQuery();

        # find out what the current project is set to 
        $findProbes->build_ProbeQuery(extra_fields => 0);

        $findProbes->loadProbeData($findProbes->getQueryTerms);
        $findProbes->setProbeList();
        $probeList     = $findProbes->getProbeList();
        $probeListQuery    = " WHERE rid IN ($probeList) ";
        #warn $probeListQuery;
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



    ### Draw a 750x300 area-proportional Venn diagram using Google API if $exp_count is (2,3)
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
        #assert(defined($A));
        #assert(defined($B));
        assert($A == $c[0] + $AB);
        assert($B == $c[1] + $AB);

        my @IDSplit1 = split(/\|/,$eids[0]);
        my @IDSplit2 = split(/\|/,$eids[1]);

        my $currentEID1 = $IDSplit1[1];        
        my $currentEID2 = $IDSplit2[1];

        my $scale = max($A, $B); # scale must be equal to the area of the largest circle
        my @nums = ($A, $B, 0, $AB);
        my $qstring = 'cht=v&amp;chd=t:'.join(',', @nums).'&amp;chds=0,'.$scale.
            '&amp;chs=750x300&chtt=Significant+Probes&amp;chco=ff0000,00ff00&amp;chdl='.
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
            '&amp;chs=750x300&chtt=Significant+Probes+(Approx.)&amp;chco=ff0000,00ff00,0000ff&amp;chdl='.
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
        elCell.innerHTML = "<input class=\"plaintext\" type=\"submit\" name=\"get\" value=\"TFS: " + fs + "\" />&nbsp;&nbsp;&nbsp;<input class=\"plaintext\" type=\"submit\" name=\"CSV\" value=\"(TFS: " + fs + " CSV)\" />";
    }
    Dom.get("tfs_caption").innerHTML = tfs.caption;
    Dom.get("tfs_all_dt").innerHTML = "View probes significant in at least one experiment:";
    Dom.get("tfs_all_dd").innerHTML = "<input type=\"submit\" name=\"get\" class=\"plaintext\" value=\"'.$rep_count.' significant probes\" /> <span class=\"separator\">/</span><input type=\"submit\" class=\"plaintext\" name=\"CSV\" value=\"CSV-formatted\" />";
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
    return;
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
    return;
}
#######################################################################################

#######################################################################################
sub show_tfs_js {

    my $TFSDisplay;
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
    return;
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
    return;
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
    return;
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
        $q->dd($q->submit(-class=>'css3button',-value=>'Upload'),
            $q->hidden(-id=>'fields', -name=>'fields'))
    );
    print $q->end_form;
    return;
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
    return;
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
    return;
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
    return;
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
    return;
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
    return;
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
    #$s->read_perm_cookie();
    my $curr_proj = $s->{session_cookie}->{curr_proj};

    my $cp = SGX::ChooseProject->new($dbh, $q, $curr_proj);
    $cp->dispatch($q->url_param('projectAction'));
    return;
}


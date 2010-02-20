#!/usr/bin/perl -w

# TODO: 1) rename table "Microarray" to "Response"; 2) rename table "Experiment" to "Array",
# 3) move "public" field from "Experiment/Array" to "Study". Consequence: if a particular experiment/array
# needs to be released but other experiments/arrays from the same study need to stay private, the given experiment/array
# will have to be referenced to from a separate, "public" study (can be a virtual link). 4) add "species" field to experiment/array table,
# and to "Sample" table as well as a foreign key to a separate "Species" table.

# always use strict option
use strict;
use warnings;

# bundled modules
# -nosticky option prevents CGI.pm from printing hidden .cgifields inside a form
use CGI 2.47 qw/-nosticky/;	# do not add qw/:standard/ because we use object-oriented style
use Switch;
use URI::Escape;
use Carp;
use Math::BigInt;
#use Time::HiRes qw/clock/;
#use Data::Dumper;

use lib 'SGX';

# custom modules in SGX directory
use SGX::Debug;		# all debugging code goes here
use SGX::Config;	# all configuration for our project goes here
use SGX::User 0.07;	# user authentication, sessions and cookies
use SGX::Session 0.08;	# email verification
use SGX::ManageMicroarrayPlatforms;
use SGX::ManageStudies;
use SGX::ManageExperiments;

# ===== USER AUTHENTICATION =============================================
my $softwareVersion = "0.10";
my $dbh = mysql_connect();
my $s = SGX::User->new(-handle		=> $dbh,
		       -expire_in	=> 3600, # expire in 3600 seconds (1 hour)
		       -check_ip	=> 1,
		       -cookie_name	=> 'user');

$s->restore;	# restore old session if it exists

# ====== MAIN FLOW CONTROLLER =================================================
# http://en.wikipedia.org/wiki/Finite_state_machine

my $q = CGI->new();
my $error_string;
my $title;
my $css = [
	{-src=>'./yui/build/reset-fonts/reset-fonts.css'},
	{-src=>'./yui/build/container/assets/skins/sam/container.css'},
	{-src=>'./yui/build/paginator/assets/skins/sam/paginator.css'},
	{-src=>'./yui/build/datatable/assets/skins/sam/datatable.css'},
	{-src=>'./html/style.css'}
];

my $js = [{-type=>'text/javascript',-src=>'./html/prototype.js'},
	  {-type=>'text/javascript',-src=>'./html/form.js'}];

my $content;	# this will be a reference to a subroutine that displays the main content

#This is a reference to the manage platform module. Module gets instanstiated when visitng the page.
my $managePlatform;
my $manageStudy;
my $manageExperiment;

# Action constants can evaluate to anything, but must be different from already defined actions.
# One can also use an enum structure to formally declare the input alphabet of all possible actions,
# but then the URIs would not be human-readable anymore.
# ===== User Management ==================================
use constant FORM			=> 'form_';# this is simply a prefix, FORM.WHATEVS does NOT do the function, just show input form.
use constant LOGIN			=> 'login';
use constant LOGOUT			=> 'logout';
use constant DEFAULT_ACTION		=> 'mainPage';
use constant UPDATEPROFILE		=> 'updateProfile';
use constant MANAGEPLATFORMS		=> 'managePlatforms';
use constant MANAGESTUDIES		=> 'manageStudy';
use constant MANAGEEXPERIMENTS		=> 'manageExperiments';
use constant CHANGEPASSWORD		=> 'changePassword';
use constant CHANGEEMAIL		=> 'changeEmail';
use constant RESETPASSWORD		=> 'resetPassword';
use constant REGISTERUSER		=> 'registerUser';
use constant VERIFYEMAIL		=> 'verifyEmail';
use constant QUIT			=> 'quit';
use constant DUMP			=> 'dump';
use constant DOWNLOADTFS		=> 'getTFS';
use constant SHOWSCHEMA			=> 'showSchema';
use constant HELP			=> 'help';
use constant ABOUT			=> 'about';
use constant COMPAREEXPERIMENTS		=> 'Compare Selected';	# submit button text
use constant FINDPROBES			=> 'Search';		# submit button text
use constant UPDATEPROBE		=> 'updateCell';
use constant UPLOADANNOT		=> 'uploadAnnot';

my $action = (defined($q->url_param('a'))) ? $q->url_param('a') : DEFAULT_ACTION;

while (defined($action)) { switch ($action) {
	# WARNING: always undefine $action at the end of your case block, unless you're passing
	# the execution to another case block that will undefine $action on its own. If you
	# don't undefine $action, this loop will go on forever!
	case FORM.UPLOADANNOT {
		# TODO: only admins should be allowed to perform this action
		if ($s->is_authorized('user')) {
			$title = 'Upload/Update Annotations';
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/yahoo-dom-event/yahoo-dom-event.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/animation/animation-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/dragdrop/dragdrop-min.js'};
			push @$js, {-type=>'text/javascript',-src=>'./html/annot.js'};
			$content = \&form_uploadAnnot;
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
 	}
	case UPLOADANNOT {
		# TODO: only admins should be allowed to perform this action
		if ($s->is_authorized('user')) {
			$content = \&uploadAnnot;
			$title = 'Complete';
			$action = undef;	# final state
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
	case FORM.MANAGEPLATFORMS {
		if ($s->is_authorized('user')) {	
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/yahoo-dom-event/yahoo-dom-event.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/connection/connection-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/dragdrop/dragdrop-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/container/container-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/element/element-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datasource/datasource-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/paginator/paginator-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datatable/datatable-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/selector/selector-min.js'};
		
			$content = \&form_managePlatforms;
			$title = 'Platforms';
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case MANAGEPLATFORMS {
		if ($s->is_authorized('user')) {

			$content = \&managePlatforms;

			$title = 'Platforms';
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case FORM.MANAGESTUDIES {
		if ($s->is_authorized('user')) {	
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/yahoo-dom-event/yahoo-dom-event.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/connection/connection-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/dragdrop/dragdrop-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/container/container-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/element/element-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datasource/datasource-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/paginator/paginator-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datatable/datatable-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/selector/selector-min.js'};

			$content = \&form_manageStudies;
			$title = 'Studies';
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case MANAGESTUDIES {
		if ($s->is_authorized('user')) {

			$content = \&manageStudies;

			$title = 'Studies';
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}	
	case FORM.MANAGEEXPERIMENTS {
		if ($s->is_authorized('user')) {	
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/yahoo-dom-event/yahoo-dom-event.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/connection/connection-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/dragdrop/dragdrop-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/container/container-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/element/element-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datasource/datasource-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/paginator/paginator-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datatable/datatable-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/selector/selector-min.js'};

			$content = \&form_manageExperiments;
			$title = 'Experiments';
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case MANAGEEXPERIMENTS {
		if ($s->is_authorized('user')) {

			$content = \&manageExperiments;

			$title = 'Experiments';
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case FORM.FINDPROBES			{
		if ($s->is_authorized('user')) {
			$title = 'Find Probes';
			push @$js, {-type=>'text/javascript',-code=>'
Event.observe(window, "load", init);
function init() {
	sgx_toggle($("graph").checked, [\'graph_option_names\', \'graph_option_values\']);
}
'};
			$content = \&form_findProbes;
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case FINDPROBES				{
		if ($s->is_authorized('user')) {
			$title = 'Find Probes';
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/yahoo-dom-event/yahoo-dom-event.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/connection/connection-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/dragdrop/dragdrop-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/container/container-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/element/element-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datasource/datasource-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/paginator/paginator-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datatable/datatable-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/selector/selector-min.js'};
			push @$js, {-type=>'text/javascript',-code=>findProbes_js()};
			$content = \&findProbes;
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case DUMP				{
		if ($s->is_authorized('user')) {
			my $table = $q->param('table');
			#show data as a tab-delimited text file
			$s->commit;
			print $q->header(-type=>'text/plain', -cookie=>\@SGX::Cookie::cookies);
			dump_table($table);
			$action = QUIT;
		} else {
			$action = FORM.LOGIN;
		}
	}
	case DOWNLOADTFS			{
		if ($s->is_authorized('user')) {
			$title = 'View Slice';

			push @$js, {-type=>'text/javascript', -src=>'./yui/build/yahoo-dom-event/yahoo-dom-event.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/element/element-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/paginator/paginator-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datasource/datasource-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datatable/datatable.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/yahoo/yahoo.js'};
			push @$js, {-type=>'text/javascript',-code=>show_tfs_js()};

			$content = \&show_tfs;
			$action = undef;
		} else {
			$action = FORM.LOGIN;
		}
	}
	case SHOWSCHEMA			{
		if ($s->is_authorized('user')) {
			$title = 'Database Schema';
			$content = \&schema;
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case HELP			{
		# will send a redirect header, so commit the session to data store now
		$s->commit;
		print $q->redirect(-uri		=> $q->url(-base=>1).'./html/wiki/',
				   -status	=> 302,	 # 302 Found
				   -cookie	=> \@SGX::Cookie::cookies);
		$action = QUIT;
	}
	case ABOUT {
		$title = 'About';
		$content = \&about;
		$action = undef;	# final state
	}
	case FORM.COMPAREEXPERIMENTS		{
		if ($s->is_authorized('user')) {
			$title = 'Compare Experiments';
			push @$js, {-type=>'text/javascript',-code=>form_compareExperiments_js()};
			push @$js, {-type=>'text/javascript',-src=>'./html/experiment.js'};
			$content = \&form_compareExperiments;
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case COMPAREEXPERIMENTS		{
		if ($s->is_authorized('user')) {
			$title = 'Compare Experiments';

			push @$js, {-type=>'text/javascript', -src=>'./yui/build/yahoo-dom-event/yahoo-dom-event.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/element/element-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/paginator/paginator-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datasource/datasource-min.js'};
			push @$js, {-type=>'text/javascript', -src=>'./yui/build/datatable/datatable-min.js'};
			push @$js, {-type=>'text/javascript',-code=>compare_experiments_js()};

			$content = \&compare_experiments;
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case FORM.LOGIN			{
		if ($s->is_authorized('unauth')) {
			$action = DEFAULT_ACTION;
		} else {
			$title = 'Login';
			$content = \&form_login;
			$action = undef;	# final state
		}
	}
	case LOGIN			{
		$s->authenticate($q->param('username'), $q->param('password'), \$error_string);
		if ($s->is_authorized('unauth')) {
			my $destination = (defined($q->url_param('destination'))) ? uri_unescape($q->url_param('destination')) : undef;
			if (defined($destination) && $destination ne $q->url(-absolute=>1) && $destination !~ m/(?:&|\?|&amp;)a=$action(?:\z|&|#)/ && $destination !~ m/(?:&|\?|&amp;)a=form_$action(?:\z|&|#)/) {
				# will send a redirect header, so commit the session to data store now
				$s->commit;

				# if the user is heading to a specific placce, pass him/her along,
				# otherwise continue to the main page (script_name)
				# do not add nph=>1 parameter to redirect() because that will cause it to crash
				print $q->redirect(-uri		=> $q->url(-base=>1).$destination,
						   -status	=> 302,	 # 302 Found
						   -cookie	=> \@SGX::Cookie::cookies);
				# code will keep executing after redirect, so clean up and force the program to quit
				$action = QUIT;
			} else {
				$action = DEFAULT_ACTION;
			}
		} else {
			$action = FORM.LOGIN;
		}
	}
	case LOGOUT			{
		if ($s->is_authorized('unauth')) {
			$s->destroy;
		}
		$action = DEFAULT_ACTION;
	}
	case FORM.RESETPASSWORD 	{
		if ($s->is_authorized('unauth')) {
			$action = FORM.CHANGEPASSWORD;
		} else {
			$title = 'Reset Password';
			$content = \&form_resetPassword;
			$action = undef;	# final state
		}
	}
	case RESETPASSWORD		{
		if ($s->is_authorized('unauth')) {
			$action = FORM.CHANGEPASSWORD;
		} else {
			if ($s->reset_password($q->param('username'), PROJECT_NAME, $q->url(-full=>1).'?a='.FORM.CHANGEPASSWORD, \$error_string)) {
				$title = 'Reset Password';
				$content = \&resetPassword_success;
				$action = undef;	# final state
			} else {
				$action = FORM.RESETPASSWORD;
			}
		}
	}
	case FORM.CHANGEPASSWORD	{
		if ($s->is_authorized('unauth')) {
			$title = 'Change Password';
			$content = \&form_changePassword;
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case CHANGEPASSWORD		{
		if ($s->is_authorized('unauth')) {
			if ($s->change_password($q->param('old_password'), $q->param('new_password1'), $q->param('new_password2'), \$error_string)) {
				$title = 'Change Password';
				$content = \&changePassword_success;
				$action = undef;	# final state
			} else {
				$action = FORM.CHANGEPASSWORD;
			}
		} else {
			$action = FORM.LOGIN;
		}
	}
	case FORM.CHANGEEMAIL	{
		if ($s->is_authorized('unauth')) {
			$title = 'Change Email';
			$content = \&form_changeEmail;
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case CHANGEEMAIL	   {
		if ($s->is_authorized('unauth')) {
			if ($s->change_email($q->param('password'), 
					     $q->param('email1'), $q->param('email2'),
					     PROJECT_NAME,
					     $q->url(-full=>1).'?a='.VERIFYEMAIL, 
					     \$error_string)) {
				$title = 'Change Email';
				$content = \&changeEmail_success;
				$action = undef;	# final state
			} else {
				$action = FORM.CHANGEEMAIL;
			}
		} else {
			$action = FORM.LOGIN;
		}
	}
	case FORM.REGISTERUSER		{
		if ($s->is_authorized('unauth')) {
			$action = DEFAULT_ACTION;
		} else {
			$title = 'Register';
			$content = \&form_registerUser;
			$action = undef;	# final state
		}
	}
	case REGISTERUSER		{
		if ($s->is_authorized('unauth')) {
			$action = DEFAULT_ACTION;
		} else {
			if ($s->register_user($q->param('username'),
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
				$action = undef;	# final state
			} else {
				$action = FORM.REGISTERUSER;
			}
		}
	}
	case FORM.UPDATEPROFILE 		{
		if ($s->is_authorized('unauth')) {
			$title = 'My Profile';
			$content = \&form_updateProfile;
			$action = undef;	# final state
		} else {
			$action = FORM.LOGIN;
		}
	}
	case UPDATEPROFILE		{
		$action = DEFAULT_ACTION;
	}
	case VERIFYEMAIL		{
		if ($s->is_authorized('unauth')) {
			my $t = SGX::Session->new(-handle=>$dbh, -expire_in=>3600*48, -id=>$q->param('sid'), -check_ip=>0);
			if ($t->restore) {
				if ($s->verify_email($t->{data}->{username})) {
					$title = 'Email Verification';
					$content = \&verifyEmail_success;
					$action = undef;	# final state
				} else {
					$action = DEFAULT_ACTION;
				}
				$t->destroy;
			} else {
				# no session tied
				$action = DEFAULT_ACTION;
			}
		} else {
			$action = FORM.LOGIN;
		}
	}
	case QUIT			{
		# perform cleanup and stop execution
		$dbh->disconnect;
		exit;
	}
	case DEFAULT_ACTION		{
		$title = 'Main';
		$content = \&main;
		$action = undef;	# final state
	}
	else {
		# should not happen during normal operation
		warn "Invalid action name specified: $action";
		$action = DEFAULT_ACTION;
	}
}}
$s->commit;	# flush the session data and prepare the cookie

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
	push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.MANAGEPLATFORMS,
				-title=>'Manage Platforms'}, 'Manage Platforms');
	push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.MANAGESTUDIES,
				-title=>'Manage Studies'}, 'Manage Studies');
	push @menu, $q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.MANAGEEXPERIMENTS,
				-title=>'Manage Experiments'}, 'Manage Experiments');
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

#print $q->h1('Welcome to '.PROJECT_NAME),
#	$q->h2('The database for sex-specific gene expression');
print $q->img({src=>IMAGES_PATH."/logo.png", width=>448, height=>108, alt=>PROJECT_NAME, title=>PROJECT_NAME});

print $q->ul({-id=>'menu'},$q->li(\@menu));

# testing stuff...
#print $q->pre("
#cookies sent to user:			
#".Dumper(\@SGX::Cookie::cookies)."
#session data stored:		
#".Dumper($s->{data})."
#session expires after:	".$s->{ttl}." seconds of inactivity
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
			-head=>[$q->Link({-type=>'image/x-icon',-href=>IMAGES_PATH.'/favicon.ico',-rel=>'icon'})]
		);
	print '<div id="content">';
}
#######################################################################################
sub cgi_end_html {
	print '</div>';
	print footer();
	print $q->end_html;
}
#######################################################################################
sub main {
	print $q->p('The SEGEX database will provide public access to previously released datasets from the Waxman laboratory, and data mining and visualization modules to query gene expression across several studies and experimental conditions.');
	print $q->p('This database was developed at Boston University as part of the BE768 Biological Databases course, Spring 2009, G. Benson instructor. Student developers: Anna Badiee, Eugene Scherba, Katrina Steiling and Niraj Trivedi. Faculty advisor: David J. Waxman.');
}
#######################################################################################
sub about {
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
	$uri = $q->url(-absolute=>1) if $uri =~ m/(?:&|\?|&amp;)a=${\LOGOUT}(?:\z|&|#)/;	# do not want to logout immediately after login
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
			$q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.RESETPASSWORD,-title=>'Email me a new password'},'I Forgot My Password'),
			$q->span({-class=>'separator'},' / '),
			$q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.REGISTERUSER,-title=>'Set up a new account'},'Register')
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
	print $q->p('A new password has been emailed to you. Once you receive this email, you will be able to change the password sent to you by following the link in the email text.') .
	$q->p($q->a({-href=>$q->url(-absolute=>1),
		     -title=>'Back to login page'},'Back'));
}
#######################################################################################
sub registration_success {
	print $q->p('An email has been sent to the email address you have entered. It contains a link, by following which you can confirm your email address. Another email message has been sent to the administrator(s) of this site. Once your request for access is approved, you will be able to start using the data provided.') .
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
	print $q->p('You have changed your email address. Please verify your new email address with the system by clicking on the link in the email that has been sent to you.') .
	$q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.UPDATEPROFILE,
		     -title=>'Back to my profile'},'Back'));
}
#######################################################################################
sub form_updateProfile {
	# user has to be logged in
	print $q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.CHANGEPASSWORD,-title=>'Change Password'},'Change Password')) .
	$q->p($q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.CHANGEEMAIL,-title=>'Change Email'},'Change Email'));
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
			$q->submit(-name=>'registerUser',-id=>'registerUser',-value=>'Submit for approval'),
			$q->span({-class=>'separator'},' / '),
			$q->a({-href=>$q->url(-absolute=>1).'?a='.FORM.LOGIN,
				-title=>'Back to login page'},'Back')
		)
	) .
	$q->end_form;
}
#######################################################################################
sub footer {
	$q->div({-id=>'footer'},
		$q->ul(
		#$q->li($q->a({-href=>'http://www.bu.edu/',-title=>'Boston University'},$q->img({src=>'http://www.bu.edu/common/hp/graphics/bu-logo.gif', alt=>'Boston University'}))),
		$q->li($q->a({-href=>'http://www.bu.edu/',-title=>'Boston University'},'Boston University')),
		$q->li(
			$q->ul(
			$q->li($q->a({-href=>'http://validator.w3.org/check?uri=referer',
				-title=>'Validate XHTML'},'XHTML')),
			$q->li($q->a({-href=>'http://jigsaw.w3.org/css-validator/check/referer',
				-title=>'Validate CSS'},'CSS')),
			$q->li('SEGEX version : ' . $softwareVersion )
			)
		))
	);
}
#######################################################################################
sub updateCell {
	my $type = $q->param('type');
	assert(defined($type));

	switch ($type) {
	case 'probe' {
		my ($reporter, $pname, $note) = (
			$dbh->quote($q->param('reporter')),
			$dbh->quote($q->param('pname')),
			$dbh->quote($q->param('note'))
		);
		return $dbh->do(qq{update probe left join platform on platform.pid=probe.pid set note=$note where reporter=$reporter and pname=$pname});
	}
	case 'gene' {
		# tries to use gene symbol first as key field; if gene symbol is empty, switches to 
		# transcript accession number.
		my ($seqname, $pname, $note) = (
			$q->param('seqname'),
			$dbh->quote($q->param('pname')),
			$dbh->quote($q->param('note'))
		);
		if (defined($seqname) && $seqname ne '') {
			$seqname = $dbh->quote($seqname);
			return $dbh->do(qq{update gene left join platform on platform.pid=gene.pid set gene_note=$note where seqname=$seqname and pname=$pname});
		} else {
			my $accnum_count = 0;
			my @accnum = split(/ *, */, $q->param('accnum'));
			foreach (@accnum) {
				if (defined($_) && $_ ne '') {
					$accnum_count++;
					$_ = $dbh->quote($_);
					$dbh->do(qq{update gene left join platform on platform.pid=gene.pid set gene_note=$note where accnum=$_ and pname=$pname});
				}
			}
			if ($accnum_count > 0) {
				return 1;
			} else {
				return 0;
			}
		}
	}
	else {
		assert(0);
	}}
}
#######################################################################################
sub form_findProbes {
	print $q->start_form(-method=>'GET',
		-action=>$q->url(absolute=>1),
		-enctype=>'application/x-www-form-urlencoded') .

	#$q->p('This function will find all probes that reference the same gene symbol as the reporter ID entered below and plot fold change or log ratio.') .
	$q->dl(
		$q->dt('Search string:'),
		$q->dd($q->textfield(-tabindex=>1, -name=>'text'), ' in ', $q->popup_menu(-name=>'type',-values=>['gene','transcript','probe'],-default=>'gene',-labels=>{'gene'=>'Gene Symbols','transcript'=>'Transcripts','probe'=>'Probes'})),
		$q->dt('Pattern to match:'),
		$q->dd($q->radio_group(-tabindex=>2, -name=>'match', -values=>['full','prefix', 'part'], -default=>'full', -linebreak=>'true', -labels=>{full=>'Full Word', prefix=>'Prefix', part=>'Part of the Word / Regular Expression'})),
		$q->dt('Display options:'),
		$q->dd($q->popup_menu(-tabindex=>3, -name=>'opts',-values=>['0','1','2'], -default=>'1',-labels=>{'0'=>'Basic (names and IDs only)', '1'=>'Full annotation', '2'=>'Full annotation with experiment data (TO BE IMPLEMENTED)'})),
		$q->dt('Graph(s):'),
		$q->dd($q->checkbox(-tabindex=>4, id=>'graph', -onclick=>'sgx_toggle(this.checked, [\'graph_option_names\', \'graph_option_values\']);', -checked=>0, -name=>'graph',-label=>'Show Differential Expression Graph')),
		$q->dt({id=>'graph_option_names'}, "Response variable:"),
		$q->dd({id=>'graph_option_values'}, $q->radio_group(-tabindex=>5, -name=>'trans', -values=>['fold','ln'], -default=>'fold', -linebreak=>'true', -labels=>{fold=>'Fold Change +/- 1', ln=>'Log2 Ratio'})),
		$q->dt('&nbsp;'),
		$q->dd($q->submit(-tabindex=>6, -name=>'a', -value=>FINDPROBES, -override=>1))
	) .
	$q->endform;
}
#######################################################################################
sub findProbes_js {

	my $text = $q->param('text') or die "You did not specify what to search for";	# must be always set -- no defaults
	my $type = $q->param('type') or die "You did not specify where to search";	# must be always set -- no defaults
	my $trans = (defined($q->param('trans'))) ? $q->param('trans') : 'fold';
	my $match = (defined($q->param('match'))) ? $q->param('match') : 'full';
	my $opts = (defined($q->param('opts'))) ? $q->param('opts') : 1;

	my @extra_fields;

	switch ($opts) {
	case 0 {}
	case 1 { @extra_fields = ('coalesce(probe.note, g0.note) as \'Probe Specificity - Comment\', coalesce(probe.probe_sequence, g0.probe_sequence) AS \'Probe Sequence\'', 'group_concat(distinct g0.description order by g0.seqname asc separator \'; \') AS \'Gene Description\'', 'group_concat(distinct gene_note order by g0.seqname asc separator \'; \') AS \'Gene Specificity - Comment\'') }
	case 2 {} # TODO
	}

	my $extra_sql = (@extra_fields) ? ', '.join(', ', @extra_fields) : '';

	my $qtext;
	switch ($match) {
	case 'full'	{ $qtext = '^'.$text.'$' }
	case 'prefix'	{ $qtext = '^'.$text }
	case 'part'	{ $qtext = $text } 
	else		{ assert(0) }
	}

	my $g0_sql;
	switch ($type) {
	case 'probe' {
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
	case 'gene' {
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
	case 'transcript' {
		$g0_sql = "
select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join
(select distinct accnum from gene where accnum REGEXP ? and accnum is not NULL) as g1
on g2.accnum=g1.accnum where g2.gid is not NULL

union

select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
(select distinct seqname from gene where accnum REGEXP ? and seqname is not NULL) as g3
on g4.seqname=g3.seqname where g4.gid is not NULL
";
	} else {
		assert(0); # shouldn't happen
	}}

	my $sth = $dbh->prepare(qq{
select distinct coalesce(probe.reporter, g0.reporter) as Probe, pname as Platform, group_concat(distinct if(isnull(g0.accnum),'',g0.accnum) order by g0.seqname asc separator ',') as 'Transcript', if(isnull(g0.seqname),'',g0.seqname) as 'Gene'$extra_sql from
($g0_sql) as g0
left join (annotates natural join probe) on annotates.gid=g0.gid
left join platform on platform.pid=coalesce(probe.pid, g0.pid)
group by coalesce(probe.rid, g0.rid)
})
		or die $dbh->errstr;
	#warn $sth->{Statement};
	my $rowcount = $sth->execute($qtext, $qtext)
		or die $dbh->errstr;

	my $caption = sprintf("Found %d probe", $rowcount) .(($rowcount != 1) ? 's' : '')." annotated with $type groups matching '$qtext' (${type}s grouped by gene symbol or transcript accession number)";

	my $out = "
var probelist = {
caption: \"$caption\",
records: [
";

	my @names = @{$sth->{NAME}};	# cache the field name array

	my $data = $sth->fetchall_arrayref;
	$sth->finish;

	# data are sent as a JSON object plus Javascript code (at the moment)
	foreach (sort {$a->[3] cmp $b->[3]} @$data) {
		foreach (@$_) {
			$_ = '' if !defined $_;
			$_ =~ s/"//g;	# strip all double quotes (JSON data are bracketed with double quotes)
					# TODO: perhaps escape quotation marks instead of removing them
		}

		# TODO: add a species table to the schema. Each Experiment table entry (a single microarray)
		# will then have a foreign key to species (because expression microarrays are species-specific).
		# Will also need species reference from either Probe table or Gene table or both (or something similar).
		# the following NCBI search shows only genes specific to a given species:
		# http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=Cyp2a12+AND+mouse[ORGN]
		$out .= '{0:"'.$_->[0].'",1:"'.$_->[1].'",2:"'.$_->[2].'",3:"'.$_->[3].'"';

		if (@extra_fields) 
		{
			$out .= ',4:"'.$_->[4].'",5:"'.$_->[5].'",6:"'.$_->[6].'",7:"'.$_->[7].'"';
		}
		$out .= "},\n";
	}
	$out =~ s/,\s*$//;	# strip trailing comma

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
			$out .= 'graph_content += "<li id=\"reporter_" + i + "\"><object type=\"image/svg+xml\" width=\"555\" height=\"580\" data=\"/graph.cgi?reporter=" + oData + "&trans='.$trans.'\"><embed src=\"/graph.cgi?reporter=" + oData + "&trans='.$trans.'\" width=\"555\" height=\"580\" /></object></li>";
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
				out += "<a title=\"Search NCBI Nucleotide for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=Nucleotide&term='.SPECIES.'[ORGN]+AND+" + b + "[NACC]\">" + b + "</a>, ";
			}
		}
		elCell.innerHTML = out.replace(/,\s*$/, "");
	}
	YAHOO.widget.DataTable.Formatter.formatGene = function(elCell, oRecord, oColumn, oData) {
		if (oData.match(/^ENS[A-Z]{4}\d{11}/i)) {
			elCell.innerHTML = "<a title=\"Search Ensembl for " + oData + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + oData + "\">" + oData + "</a>";
		} else {
			elCell.innerHTML = "<a title=\"Search NCBI Gene for " + oData + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term='.SPECIES.'[ORGN]+AND+" + oData + "\">" + oData + "</a>";
		}
	}
	YAHOO.widget.DataTable.Formatter.formatSequence = function(elCell, oRecord, oColumn, oData) {
		elCell.innerHTML = "<a href=\"http://genome.ucsc.edu/cgi-bin/hgBlat?userSeq=" + oData + "&type=DNA&org='.SPECIES.'\" title=\"UCSC BLAT on '.SPECIES.' DNA\" target=\"_blank\">" + oData + "</a>";
	}
	var myColumnDefs = [
		{key:"0", sortable:true, resizeable:true, label:"'.$names[0].'", formatter:"formatProbe"},
		{key:"1", sortable:true, resizeable:true, label:"'.$names[1].'"},
		{key:"2", sortable:true, resizeable:true, label:"'.$names[2].'", formatter:"formatTranscript"}, 
		{key:"3", sortable:true, resizeable:true, label:"'.$names[3].'", formatter:"formatGene"}'. ((@extra_fields) ? ',
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
}})}' : '') .'
];

	var myDataSource = new YAHOO.util.DataSource(probelist.records);
	myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
	myDataSource.responseSchema = {
		fields: ["0","1","2","3"'. ((@extra_fields) ? ',"4","5","6","7"' : '') . ']
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
	if (defined($q->param('graph'))) {
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
					imgFile = this.innerHTML;	// replaced ".text" with ".innerHTML" because of IE problem
					var panel =  new YAHOO.widget.Panel("panel" + index, { close:true, visible:true, draggable:true, constraintoviewport:false, context:["container" + index, "tl", "br"] } );
					panel.setHeader(imgFile);
					panel.setBody("<object type=\"image/svg+xml\" width=\"555\" height=\"580\" data=\"/graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\"><embed src=\"/graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\" width=\"555\" height=\"580\" /></object>");
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
#######################################################################################
sub findProbes {
	print	'<h2 id="caption"></h2>',
		'<div><a id="probetable_astext">View as plain text</a></div>',
		'<div id="probetable"></div>';
	print '<ul id="graphs"></ul>' if defined($q->param('graph'));
}
#######################################################################################
sub schema {
	my $dump_url = $q->url(-absolute=>1).'?a='.DUMP;
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
	$q->img({src=>IMAGES_PATH.'/schema.png', width=>720, height=>720, usemap=>'#schema_Map', id=>'schema'});
}
#######################################################################################
sub form_compareExperiments_js {
	my $out = '';

	# get a list of platforms and cutoff values
	my $sth = $dbh->prepare(qq{select pid, pname, def_p_cutoff, def_f_cutoff from platform})
		or die $dbh->errstr;
	my $rowcount = $sth->execute
		or die $dbh->errstr;
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
		$out .= 'platform['.$row[0].'][1] = \''.$row[2]."';\n";	# P-calue cutoff
		$out .= 'platform['.$row[0].'][2] = \''.$row[3]."';\n";	# Fold change cutoff
	}
	$sth->finish;


	# get a list of studies
	$sth = $dbh->prepare(qq{select stid, description, pid from study})
		or die $dbh->errstr;
	$rowcount = $sth->execute
		or die $dbh->errstr;
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
	$sth = $dbh->prepare(qq{select stid, eid, s2.description as s2_desc, s1.description as s1_desc from study natural join experiment left join sample as s1 on sid1=s1.sid left join sample as s2 on sid2=s2.sid})
		or die $dbh->errstr;
	$rowcount = $sth->execute
		or die $dbh->errstr;
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

	print 
	$q->dl(
		$q->dt('Choose platform / add experiment:'),
		$q->dd(	$q->popup_menu(-name=>'platform', -id=>'platform', -onChange=>"updatePlatform(this);"),
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
		$q->dt('Compare selected experiments:'),
		$q->dd(
			$q->submit(-name=>'submit',-value=>'Submit', -override=>1),
			$q->hidden(-name=>'a',-value=>COMPAREEXPERIMENTS, -override=>1)
		)
	),
	$q->endform;
}

#######################################################################################
sub compare_experiments_js {
	my $query_titles = '';
	my $query_fs = 'SELECT fs, COUNT(*) as c FROM (SELECT BIT_OR(flag) AS fs FROM (';
	my $query_fs_body = '';
	my (@eids, @reverses, @fcs, @pvals);
	my $i;
	for ($i = 1; defined($q->param("eid_$i")); $i++) 
	{
		my ($eid, $fc, $pval) = ($q->param("eid_$i"), $q->param("fc_$i"), $q->param("pval_$i"));
		my $reverse = (defined($q->param("reverse_$i"))) ? 1 : 0;
		# prepare the four arrays that will be used to display data
		push @eids, $eid; push @reverses, $reverse; push @fcs, $fc; push @pvals, $pval;

		# flagsum breakdown query
		my $flag = 1 << $i - 1;
		$query_fs_body .= "SELECT rid, $flag AS flag FROM microarray WHERE eid=$eid AND pvalue < $pval AND ABS(foldchange) > $fc UNION ALL ";
		# account for sample order when building title query
		my $title = ($reverse) ? 
			"s1.genotype, '-', s1.sex, ' / ', s2.genotype, '-', s2.sex" :
			"s2.genotype, '-', s2.sex, ' / ', s1.genotype, '-', s1.sex";
		$query_titles .= " SELECT eid, CONCAT(study.description, ': ', $title) AS title FROM experiment NATURAL JOIN study LEFT JOIN sample AS s1 ON sid1=s1.sid LEFT JOIN sample AS s2 ON sid2=s2.sid WHERE eid=$eid UNION ALL ";
	}

	my $exp_count = $i - 1;	# number of experiments being compared

	# strip trailing 'UNION ALL' plus any trailing white space
	$query_fs_body =~ s/UNION ALL\s*$//i;
	$query_fs = sprintf($query_fs, $exp_count) . $query_fs_body . ') AS d1 GROUP BY rid) AS d2 GROUP BY fs';

	my $sth_fs = $dbh->prepare(qq{$query_fs}) or die $dbh->errstr;
	my $rowcount_fs = $sth_fs->execute or die $dbh->errstr;
	my $h = $sth_fs->fetchall_hashref('fs');
	$sth_fs->finish;

	# strip trailing 'UNION ALL' plus any trailing white space
	$query_titles =~ s/UNION ALL\s*$//i;
	my $sth_titles = $dbh->prepare(qq{$query_titles}) or die $dbh->errstr;
	my $rowcount_titles = $sth_titles->execute or die $dbh->errstr;
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

		my $scale = max($A, $B); # scale must be equal to the area of the largest circle
		my @nums = ($A, $B, 0, $AB);
		my $qstring = 'cht=v&amp;chd=t:'.join(',', @nums).'&amp;chds=0,'.$scale.
			'&amp;chs=450x300&chtt=Significant+Probes&amp;chco=ff0000,00ff00&amp;chdl='.
			uri_escape('1. '.$ht->{$eids[0]}->{title}).'|'.
			uri_escape('2. '.$ht->{$eids[1]}->{title});

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

		my $scale = max($A, $B, $C); # scale must be equal to the area of the largest circle
		my @nums = ($A, $B, $C, $AB, $AC, $BC, $ABC);
		my $qstring = 'cht=v&amp;chd=t:'.join(',', @nums).'&amp;chds=0,'.$scale.
			'&amp;chs=450x300&chtt=Significant+Probes+(Approx.)&amp;chco=ff0000,00ff00,0000ff&amp;chdl='.
			uri_escape('1. '.$ht->{$eids[0]}->{title}).'|'.
			uri_escape('2. '.$ht->{$eids[1]}->{title}).'|'.
			uri_escape('3. '.$ht->{$eids[2]}->{title});

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

var summary = {
caption: "Experiments compared",
records: [
';

	for ($i = 0; $i < @eids; $i++) {
		print '<tr><th>' . ($i + 1) . '</th><td>'.$ht->{$eids[$i]}->{title}.'</td><td>'.$fcs[$i].'</td><td>'.$pvals[$i].'</td><td>'.$hc{$i}."</td></tr>\n";
		$out .= '{0:"'. ($i + 1) . '",1:"' . $ht->{$eids[$i]}->{title} . '",2:"' . $fcs[$i] . '",3:"' . $pvals[$i] . '",4:"'.$hc{$i} . "\"},\n";
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
			if (1 << $i & $h->{$key}->{fs})	{ 
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
		elCell.innerHTML = "<input type=\"submit\" name=\"get\" value=\"FS: " + fs + "\" />";
	}
	Dom.get("tfs_caption").innerHTML = tfs.caption;
	Dom.get("tfs_all_dt").innerHTML = "View probes significant in at least one experiment:";
	Dom.get("tfs_all_dd").innerHTML = "<input type=\"submit\" name=\"get\" value=\"'.$rep_count.' significant probes\" />";
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

	print	'<div id="venn"></div>',
		'<h2 id="summary_caption"></h2>',
		'<div id="summary_table" class="table_cont"></div>',
		$q->start_form(
			-method=>'GET',
			-action=>$q->url(-absolute=>1),
			-target=>'_blank',
			-class=>'getTFS',
			-enctype=>'application/x-www-form-urlencoded'
		),
		$q->hidden(-name=>'a',-value=>DOWNLOADTFS, -override=>1),
		$q->hidden(-name=>'eid', -id=>'eid'),
		$q->hidden(-name=>'rev', -id=>'rev'),
		$q->hidden(-name=>'fc', -id=>'fc'),
		$q->hidden(-name=>'pval', -id=>'pval'),
		'<h2 id="tfs_caption"></h2>',
		$q->dl(
			$q->dt('Data to display:'),
			$q->dd($q->popup_menu(-name=>'opts',-values=>['0','1','2'], -default=>'0',-labels=>{'0'=>'Basic (ratios only)', '1'=>'Experiment data', '2'=>'Experiment data with annotations'})),
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
	my $sth = $dbh->prepare(qq{SELECT * FROM $table}) or die $dbh->errstr;
	my $rowcount = $sth->execute or die $dbh->errstr;

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
sub show_tfs_js {
	# The $output_format parameter is either 'html' or 'text';
	# The $fs parameter is the flagsum for which the data will be filtered
	# If the $fs is zero or undefined, all data will be output
	#
	my $regex_split_on_commas = qr/ *, */;
	my @eids = split($regex_split_on_commas, $q->param('eid'));
	my @reverses = split($regex_split_on_commas, $q->param('rev'));
	my @fcs = split($regex_split_on_commas, $q->param('fc'));
	my @pvals = split($regex_split_on_commas, $q->param('pval'));
	my $fs = $q->param('get');
	if ($fs =~ m/^\d+ significant probes$/i) {
		undef $fs;
	} else {
		$fs =~ s/^FS: //i;
	}
	my $opts = $q->param('opts');

	# Build the SQL query that does the TFS calculation
	my $having = (defined($fs) && $fs) ? "HAVING abs_fs=$fs" : '';
	my $num_start = 5;	# index of the column that is the beginning of the "numeric" half of the table (required for table sorting)
	my $query = '   
SELECT abs_fs, dir_fs, probe.reporter AS Probe, GROUP_CONCAT(DISTINCT accnum SEPARATOR \'+\') AS Transcript, GROUP_CONCAT(DISTINCT seqname SEPARATOR \'+\') AS Gene, %s FROM (
SELECT rid, BIT_OR(abs_flag) AS abs_fs, BIT_OR(dir_flag) AS dir_fs FROM (
';
	my $query_body = '';
	my $query_proj = '';
	my $query_join = '';
	my $query_titles = '';
	my $i = 1; 
	foreach my $eid (@eids) {
		my ($fc, $pval) = ($fcs[$i-1], $pvals[$i-1]);
		assert($fc);    # cannot be undef and cannot be zero
		assert($pval);  # cannot be undef and cannot be zero
		my $abs_flag = 1 << $i - 1;
		my $dir_flag = ($reverses[$i-1]) ? "$abs_flag,0" : "0,$abs_flag";
		$query_proj .= ($reverses[$i-1]) ? "1/m$i.ratio AS \'$i: Ratio\', " : "m$i.ratio AS \'$i: Ratio\', ";
		if ($opts > 0) {
			$query_proj .= ($reverses[$i-1]) ? "-m$i.foldchange AS \'$i: Fold Change\', " : "m$i.foldchange AS \'$i: Fold Change\', ";
			$query_proj .= ($reverses[$i-1]) ? "m$i.intensity2 AS \'$i: Intensity-1\', m$i.intensity1 AS \'$i: Intensity-2\', " : "m$i.intensity1 AS \'$i: Intensity-1\', m$i.intensity2 AS \'$i: Intensity-2\', ";
			$query_proj .= "m$i.pvalue AS \'$i: P\', "; 
		}
		$query_body .= " 
SELECT rid, $abs_flag AS abs_flag, if(foldchange>0,$dir_flag) AS dir_flag FROM microarray WHERE eid=$eid AND pvalue < $pval AND ABS(foldchange) > $fc UNION ALL
";
		$query_join .= "
LEFT JOIN microarray m$i ON m$i.rid=d2.rid AND m$i.eid=$eid
";
		# account for sample order when building title query
		my $title = ($reverses[$i-1]) ?
			"s1.genotype, '-', s1.sex, ' / ', s2.genotype, '-', s2.sex" :
			"s2.genotype, '-', s2.sex, ' / ', s1.genotype, '-', s1.sex";
		$query_titles .= "
SELECT eid, CONCAT(study.description, ': ', $title) AS title FROM experiment NATURAL JOIN study LEFT JOIN sample AS s1 ON sid1=s1.sid LEFT JOIN sample AS s2 ON sid2=s2.sid WHERE eid=$eid UNION ALL
";
		$i++;
	}

	# strip trailing 'UNION ALL' plus any trailing white space
	$query_titles =~ s/UNION ALL\s*$//i;
	my $sth_titles = $dbh->prepare(qq{$query_titles}) or die $dbh->errstr;
	my $rowcount_titles = $sth_titles->execute or die $dbh->errstr;
	assert($rowcount_titles == @eids);
	my $ht = $sth_titles->fetchall_hashref('eid');
	$sth_titles->finish;

	# strip trailing 'UNION ALL' plus any trailing white space
	$query_body =~ s/UNION ALL\s*$//i;
	# strip trailing comma plus any trailing white space from ratio projection
	$query_proj =~ s/,\s*$//;

	if ($opts > 1) {
		$num_start += 2;
		$query_proj = 'probe.probe_sequence AS \'Probe Sequence\', GROUP_CONCAT(DISTINCT IF(gene.description=\'\',NULL,gene.description) SEPARATOR \'; \') AS \'Gene Description\', '.$query_proj;
	}
	# pad TFS decimal portion with the correct number of zeroes
	$query = sprintf($query, $query_proj) . $query_body . "
) AS d1 GROUP BY rid $having) AS d2
$query_join
LEFT JOIN probe ON d2.rid=probe.rid
LEFT JOIN annotates ON d2.rid=annotates.rid
LEFT JOIN gene ON annotates.gid=gene.gid
GROUP BY probe.rid
ORDER BY abs_fs DESC
";
	my $sth = $dbh->prepare(qq{$query}) or die $dbh->errstr;
	my $rowcount_all = $sth->execute or die $dbh->errstr;

my $out = '
var summary = {
caption: "Experiments compared",
headers: ["&nbsp;", "Experiment", "&#124;Fold Change&#124; &gt;", "P &lt;", "&nbsp;"],
parsers: ["number", "string", "number", "number", "string"],
records: [
';
	for ($i = 0; $i < @eids; $i++) {
		$out .= '{0:"' . ($i + 1) . '",1:"'.$ht->{$eids[$i]}->{title}.'",2:"'.$fcs[$i].'",3:"'.$pvals[$i].'",4:"';
		# test for bit presence and print out 1 if present, 0 if absent
		if (defined($fs)) { $out .= (1 << $i & $fs) ? "x\"},\n" : "\"},\n" }
		else { $out .= "\"},\n" }
	}
	$out =~ s/,\s*$//;	# strip trailing comma
	$out .= '
]};
';

# Fields with indexes less num_start are formatted as strings,
# fields with indexes equal to or greater than num_start are formatted as numbers.
my @table_header;
my @table_parser;
my @table_format;
for (my $j = 2; $j < $num_start; $j++) {
	push @table_header, $sth->{NAME}->[$j];
	push @table_parser, 'string';
	push @table_format, 'formatText';
}

for (my $j = $num_start; $j < @{$sth->{NAME}}; $j++) {
	push @table_header, $sth->{NAME}->[$j];
	push @table_parser, 'number';
	push @table_format, 'formatNumber';
}

my $find_probes = $q->a({-target=>'_blank', -href=>$q->url(-absolute=>1).'?a='.FINDPROBES.'&graph=on&type=%1$s&text={0}', -title=>'Find all %1$ss related to %1$s {0}'}, '{0}');
$find_probes =~ s/"/\\"/g;	# prepend all double quotes with backslashes
my @format_template;
push @format_template, sprintf($find_probes, 'probe');
push @format_template, sprintf($find_probes, 'transcript');
push @format_template, sprintf($find_probes, 'gene');

$table_format[0] = 'formatProbe';
$table_format[1] = 'formatTranscript';
$table_format[2] = 'formatGene';
if ($opts > 1) {
	my $blat = $q->a({-target=>'_blank',-title=>'UCSC BLAT on DNA',-href=>'http://genome.ucsc.edu/cgi-bin/hgBlat?org='.SPECIES.'&type=DNA&userSeq={0}'}, '{0}');
	$blat =~ s/"/\\"/g;      # prepend all double quotes with backslashes
	$table_format[3] = 'formatProbeSequence';
	$format_template[3] = $blat;
}

$out .= '
var tfs = {
caption: "Your selection includes '.$rowcount_all.' probes",
headers: ["TFS", "'.join('","', @table_header).'" ],
parsers: ["string", "'.join('","', @table_parser).'" ],
formats: ["formatText", "'.join('","', @table_format).'" ],
frm_tpl: ["", "'.join('","', @format_template).'" ],
records: [
';
	# print table body
	while (my @row = $sth->fetchrow_array) {
		my $abs_fs = shift(@row);
		my $dir_fs = shift(@row);

		# Math::BigInt->badd(x,y) is used to add two very large numbers x and y
		# actually Math::BigInt library is supposed to overload Perl addition operator,
		# but if fails to do so for some reason in this CGI program.
		my $TFS = sprintf("$abs_fs.%0".@eids.'s', Math::BigInt->badd(substr(unpack('b32', pack('V', $abs_fs)),0,@eids), substr(unpack('b32', pack('V', $dir_fs)),0,@eids)));

		$out .= "{0:\"$TFS\"";
		foreach (@row) { $_ = '' if !defined $_ }
		$row[2] =~ s/\"//g;	# strip off quotes from gene symbols
		my $real_num_start = $num_start - 2; # TODO: verify why '2' is used here
		for (my $j = 0; $j < $real_num_start; $j++) {
			$out .= ','.($j + 1).':"'.$row[$j].'"';	# string value
		}
		for (my $j = $real_num_start; $j < @row; $j++) {
			$out .=	','.($j + 1).':'.$row[$j];	# numeric value
		}
		$out .= "},\n";
	}
	$sth->finish;
	$out =~ s/,\s*$//;	# strip trailing comma
	$out .= '
]};

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
YAHOO.util.Event.addListener("summ_astext", "click", export_table, summary, true);
YAHOO.util.Event.addListener("tfs_astext", "click", export_table, tfs, true);
YAHOO.util.Event.addListener(window, "load", function() {
	var Dom = YAHOO.util.Dom;
	var Formatter = YAHOO.widget.DataTable.Formatter;
	var lang = YAHOO.lang;

	Dom.get("summary_caption").innerHTML = summary.caption;
	var summary_table_defs = [];
	var summary_schema_fields = [];
	for (var i=0, sh = summary.headers, sp = summary.parsers, al=sh.length; i<al; i++) {
		summary_table_defs.push({key:String(i), sortable:true, label:sh[i]});
		summary_schema_fields.push({key:String(i), parser:sp[i]});
	}
	var summary_data = new YAHOO.util.DataSource(summary.records);
	summary_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
	summary_data.responseSchema = { fields: summary_schema_fields };
	var summary_table = new YAHOO.widget.DataTable("summary_table", summary_table_defs, summary_data, {});

	var template_probe = tfs.frm_tpl[1];
	var template_transcript = tfs.frm_tpl[2];
	var template_gene = tfs.frm_tpl[3];
	var template_probeseq = tfs.frm_tpl[4];
	Formatter.formatProbe = function (elCell, oRecord, oColumn, oData) {
		elCell.innerHTML = lang.substitute(template_probe, {"0":oData});
	}
	Formatter.formatTranscript = function (elCell, oRecord, oColumn, oData) {
		elCell.innerHTML = lang.substitute(template_transcript, {"0":oData});
	}
	Formatter.formatGene = function (elCell, oRecord, oColumn, oData) {
		elCell.innerHTML = lang.substitute(template_gene, {"0":oData});
	}
	Formatter.formatProbeSequence = function (elCell, oRecord, oColumn, oData) {
		elCell.innerHTML = lang.substitute(template_probeseq, {"0":oData});
	}
	Formatter.formatNumber = function(elCell, oRecord, oColumn, oData) {
		// Overrides the built-in formatter
		elCell.innerHTML = oData.toPrecision(3);
	}
	Dom.get("tfs_caption").innerHTML = tfs.caption;
	var tfs_table_defs = [];
	var tfs_schema_fields = [];
	for (var i=0, th = tfs.headers, tp = tfs.parsers, tf=tfs.formats, al=th.length; i<al; i++) {
		tfs_table_defs.push({key:String(i), sortable:true, label:th[i], formatter:tf[i]});
		tfs_schema_fields.push({key:String(i), parser:tp[i]});
	}
	var tfs_config = {
		paginator: new YAHOO.widget.Paginator({
			rowsPerPage: 50 
		})
	};
	var tfs_data = new YAHOO.util.DataSource(tfs.records);
	tfs_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
	tfs_data.responseSchema = { fields: tfs_schema_fields };
	var tfs_table = new YAHOO.widget.DataTable("tfs_table", tfs_table_defs, tfs_data, tfs_config);
});
';
	$out;
}

#######################################################################################
sub show_tfs {
	print qq{
<h2 id="summary_caption"></h2>
<div><a id="summ_astext">View as plain text</a></div>
<div id="summary_table" class="table_cont"></div>
<h2 id="tfs_caption"></h2>
<div><a id="tfs_astext">View as plain text</a></div>
<div id="tfs_table" class="table_cont"></div>
};
}
#######################################################################################
sub get_annot_fields {
	# takes two arguments which are references to hashes that will store field names of two tables:
	# probe and gene
	my ($probe_fields, $gene_fields) = @_;
	# get fields from Probe table (except pid, rid)
	my $sth = $dbh->prepare(qq{show columns from probe where Field not regexp "^[a-z]id\$"})
		or die $dbh->errstr;
	my $rowcount = $sth->execute or die $dbh->errstr;
	while (my @row = $sth->fetchrow_array) {
		$probe_fields->{$row[0]} = 1;
	}
	$sth->finish;
	# get fields from Gene table (except pid, gid)
	$sth = $dbh->prepare(qq{show columns from gene where Field not regexp "^[a-z]id\$"})
		or die $dbh->errstr;
	$rowcount = $sth->execute or die $dbh->errstr;
	while (my @row = $sth->fetchrow_array) {
		$gene_fields->{$row[0]} = 1;
	}
	$sth->finish;
}
#######################################################################################
sub form_uploadAnnot {
	my $fieldlist;
	my %platforms;
	my %core_fields = (
		'reporter' => 1,
		'accnum' => 1,
		'seqname' => 1
	);
	# get a list of platforms and cutoff values
	my $sth = $dbh->prepare(qq{select pid, pname from platform})
		or die $dbh->errstr;
	my $rowcount = $sth->execute
		or die $dbh->errstr;
	while (my @row = $sth->fetchrow_array) {
		$platforms{$row[0]} = $row[1];
	}
	$sth->finish;

	my (%probe_fields, %gene_fields);
	get_annot_fields(\%probe_fields, \%gene_fields);
	foreach (keys %probe_fields) {
		$fieldlist .= $q->li({-class=>($core_fields{$_}) ? 'core' : 'list1', -id=>$_}, $_);
	}
	foreach (keys %gene_fields) {
		$fieldlist .= $q->li({-class=>($core_fields{$_}) ? 'core' : 'list1', -id=>$_}, $_);
	}

	print
	$q->h2('Upload Annotation'),
	$q->p('Only the fields specified below will be updated. You can specify fields by dragging field tags into the target area on the right and reordering them to match the column order in the tab-delimited file. When reporter (manufacturer-provided id) is among the fields uploaded, the existing annotation for the uploaded probes will be lost and replaced with the annotation present in the uploaded file. The "Add transcript accession numbers to existing probes" option will prevent the update program from deleting existing accession numbers from probes.'),
	$q->p('The default policy for updating probe-specific fields is to insert new records whenever existing records could not be matched on the probe core field (reporter id). The default policy for updating gene-specific fields is update-only, without insertion of new records. However, new gene records <em>are</em> inserted when both reporter id and either of the gene core fields (accnum, seqname) are specified.');
	print $q->div({-class=>'workarea'}, $q->h2('Available Fields:') .
		$q->ul({-id=>'ul1', -class=>'draglist'}, $fieldlist));
	print $q->div({-class=>'workarea'}, $q->h2('Fields in the Uploaded File:') .
		$q->ul({-id=>'ul2', -class=>'draglist'}));

	print $q->startform(-method=>'POST',
		-action=>$q->url(-absolute=>1).'?a='.UPLOADANNOT,
		-enctype=>'multipart/form-data');

	print $q->dl(
		$q->dt("Platform:"),
		$q->dd($q->popup_menu(-name=>'platform', -values=>[keys %platforms], -labels=>{%platforms})),
		$q->dt("Update policy for annotations:"),
		$q->dd($q->checkbox(-name=>'add', -checked=>0, -label=>'Add transcript accession numbers to existing probes')),
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
	@fields = split($regex_split_on_commas, $q->param('fields')) if defined($q->param('fields'));
	if (@fields < 2) {
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

	my (%probe_fields, %gene_fields);
	get_annot_fields(\%probe_fields, \%gene_fields);

	my $i = 0;
	my %col;
	# create a hash mapping record names to columns in the file
	foreach (@fields) {
		# if the assertion below fails, the field specified by the user 
		# either doesn't exist or is protected.
		assert($probe_fields{$_} || $gene_fields{$_});
		$col{$_} = $i;
		$i++;
	}

	# delete core fields from field hash
	delete $probe_fields{reporter};
	delete $gene_fields{accnum};
	delete $gene_fields{seqname};

	# create two slices of specified fields, one for each table
	my @slice_probe = @col{keys %probe_fields};
	my @slice_gene = @col{keys %gene_fields};

	@slice_probe = grep { defined($_) } @slice_probe;	# remove undef elements
	@slice_gene = grep { defined($_) } @slice_gene;		# remove undef elements

	my $gene_titles = '';
	foreach (@slice_gene) { $gene_titles .= ','.$fields[$_] }
	my $probe_titles = '';
	foreach (@slice_probe) { $probe_titles .= ','.$fields[$_] }

	my $reporter_index = $col{reporter};	# probe table only is updated when this is defined and value is valid
	my $outside_have_reporter = defined($reporter_index);
	my $accnum_index = $col{accnum};
	my $seqname_index = $col{seqname};
	my $outside_have_gene = defined($accnum_index) || defined($seqname_index);
	my $pid_value = $q->param('platform');
	my $replace_accnum = $outside_have_reporter && $outside_have_gene && !defined($q->param('add'));
	if (!$outside_have_reporter && !$outside_have_gene) {
		print $q->p('No core fields specified -- cannot proceed with update.');
		return;
	}
	my $update_gene;

	# Access uploaded file
	my $fh = $q->upload('uploaded_file');
	# Perl 6 will allow setting $/ to a regular expression,
	# which would remove the need to read the whole file at once.
	local $/;	# sets input record separator to undefined, allowing "slurp" mode
	my $whole_file = <$fh>;
	close($fh);
	my @lines = split(/\s*(?:\r|\n)/, $whole_file);	# split on CRs or LFs while also removing preceding white space

	#my $clock0 = clock();
	foreach (@lines) {
		my @row = split(/ *\t */);	# split on a tab surrounded by any number (including zero) of blanks
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
				$probe_duplicates .= ','.$fields[$_].'='.$value;
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
				$update_gene .= ','.$fields[$_].'='.$row[$_];
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
						push @sql, qq{insert into gene (pid, accnum, seqname $gene_titles) values ($pid_value, $_, $seqname_value $gene_values) on duplicate key update gid=LAST_INSERT_ID(gid) $update_gene};
						push @sql, qq{insert ignore into annotates (rid, gid) values (\@rid, LAST_INSERT_ID())};
					}
				}
			}
			if ($have_reporter && !@accnum_array && $have_seqname) {
				# have gene symbol but not transcript accession number
				push @sql, qq{update gene natural join annotates set seqname=$seqname_value where rid=\@rid};
				push @sql, qq{insert into gene (pid, seqname $gene_titles) values ($pid_value, $seqname_value $gene_values) on duplicate key update gid=LAST_INSERT_ID(gid) $update_gene};
				push @sql, qq{insert ignore into annotates (rid, gid) values (\@rid, LAST_INSERT_ID())};
			}
		}
		if (@slice_gene) {
			if (!$outside_have_gene) {
				# if $outside_have_gene is true, $update_gene string has been formed already
				$update_gene = '';
				foreach (@slice_gene) {
					# title1 = value1, title2 = value2, ...
					$update_gene .= ','.$fields[$_] .'='.$row[$_];
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
			$dbh->do($_) or die $dbh->errstr;
		}
	}
	#my $clock1 = clock();

	if ($outside_have_reporter && $replace_accnum) {
		#warn "begin optimizing\n";
		# have to "optimize" because some of the deletes above were performed with "ignore" option
		$dbh->do(qq{optimize table annotates}) or die $dbh->errstr;
		# in case any gene records have been orphaned, delete them
		$dbh->do(qq{delete gene from gene left join annotates on gene.gid=annotates.gid where annotates.gid is NULL}) or die $dbh->errstr;
		#warn "end optimizing\n";
	}
	my $count_lines = @lines;
	#print $q->p(sprintf("%d lines processed in %g seconds", $count_lines, $clock1 - $clock0));
	print $q->p(sprintf("%d lines processed.", $count_lines));
}
#######################################################################################


#######################################################################################
#This just displays the Manage platforms form.
sub form_managePlatforms
{
	$managePlatform = new SGX::ManageMicroarrayPlatforms($dbh,$q);
	$managePlatform->loadAllPlatforms();
	$managePlatform->showPlatforms();
}

#This performs the action that was asked for by the manage platforms form.
sub managePlatforms
{
	my $ManageAction = ($q->url_param('ManageAction')) if defined($q->url_param('ManageAction'));
	$managePlatform = new SGX::ManageMicroarrayPlatforms($dbh,$q);

	switch ($ManageAction) 
	{
		case 'add' 
		{
			$managePlatform->loadFromForm();
			$managePlatform->insertNewPlatform();
			print "<br />Record added.<br />";
		}
		case 'delete'
		{
			$managePlatform->loadFromForm();
			$managePlatform->deletePlatform();
			print "<br />Record deleted.<br />";
		}
		case 'edit'
		{
			$managePlatform->loadSinglePlatform();
			$managePlatform->editPlatform();
		}
		case 'editSubmit'
		{
			$managePlatform->loadFromForm();
			$managePlatform->editSubmitPlatform();
			print "<br />Record updated.<br />";
		}

	}
	
	print "<a href ='" . $q->url(-absolute=>1).'?a=form_managePlatforms' . "'>Return to platforms.</a>";
}
#######################################################################################


#######################################################################################
#This just displays the Manage studies form.
sub form_manageStudies
{
	$manageStudy = new SGX::ManageStudies($dbh,$q);
	$manageStudy->loadAllStudies();
	$manageStudy->loadPlatformData();
	$manageStudy->showStudies();
}

#This performs the action that was asked for by the manage platforms form.
sub manageStudies
{
	my $ManageAction = ($q->url_param('ManageAction')) if defined($q->url_param('ManageAction'));
	$manageStudy = new SGX::ManageStudies($dbh,$q);

	switch ($ManageAction) 
	{
		case 'add' 
		{
			$manageStudy->loadFromForm();
			$manageStudy->insertNewStudy();
			print "<br />Record added.<br />";
		}
		case 'delete'
		{
			$manageStudy->loadFromForm();
			$manageStudy->deleteStudy();
			print "<br />Record deleted.<br />";
		}
		case 'edit'
		{
			$manageStudy->loadSingleStudy();
			$manageStudy->loadPlatformData();
			$manageStudy->editStudy();
		}
		case 'editSubmit'
		{
			$manageStudy->loadFromForm();
			$manageStudy->editSubmitStudy();
			print "<br />Record updated.<br />";
		}

	}
	
	print "<a href ='" . $q->url(-absolute=>1).'?a=form_manageStudy' . "'>Return to Studies.</a>";
}
#######################################################################################

#######################################################################################
#This just displays the Manage experiments form.
sub form_manageExperiments
{
	$manageExperiment = new SGX::ManageExperiments($dbh,$q);
	my $ManageAction = ($q->url_param('ManageAction')) if defined($q->url_param('ManageAction'));

	switch ($ManageAction) 
	{
		case 'load' 
		{
			$manageExperiment->loadFromForm();
			$manageExperiment->loadAllExperimentsFromStudy();
			$manageExperiment->loadStudyData();
			$manageExperiment->loadSampleData();
			$manageExperiment->showExperiments();
		}
		
		else
		{
			$manageExperiment->loadStudyData();
			$manageExperiment->showExperiments();
		}

	}

}

#This performs the action that was asked for by the manage platforms form.
sub manageExperiments
{
	$manageExperiment = new SGX::ManageExperiments($dbh,$q);
	my $ManageAction = ($q->url_param('ManageAction')) if defined($q->url_param('ManageAction'));

	switch ($ManageAction) 
	{
		case 'add' 
		{
			$manageExperiment->loadFromForm();
			$manageExperiment->insertNewExperiment();
			print "<br />Record added.<br />";
		}
		case 'edit' 
		{
			$manageExperiment->loadSingleExperiment();
			$manageExperiment->loadSampleData();
			$manageExperiment->editExperiment();
		}
		case 'editSubmit'
		{
			$manageExperiment->loadFromForm();
			$manageExperiment->editSubmitExperiment();
		}
	}

	print "<a href ='" . $q->url(-absolute=>1).'?a=form_manageExperiments' . "'>Return to Experiments.</a>";
}
#######################################################################################

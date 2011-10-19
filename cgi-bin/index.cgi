#!/usr/bin/perl -wT

use strict;
use warnings;

#---------------------------------------------------------------------------
#  Perl library includes
#---------------------------------------------------------------------------
# CGI options: -nosticky option prevents CGI.pm from printing hidden .cgifields
# inside a form. We do not add qw/:standard/ because we use object-oriented
# style.
use CGI 2.47 qw/-nosticky -private_tempfiles/;

#use CGI::Pretty 2.47 qw/-nosticky/;
use Carp;    # croak exported automatically

#---------------------------------------------------------------------------
# Custom modules in SGX directory
#---------------------------------------------------------------------------
use lib qw/./;

#use SGX::Debug;                 # all debugging code goes here
use SGX::Config;                # all configuration for our project goes here
use SGX::Session::User 0.07;    # user authentication, sessions and cookies

#---------------------------------------------------------------------------
#  init
#---------------------------------------------------------------------------
my $q = CGI->new();
my $dbh = eval { sgx_db_connect() };    #or do { $action = ERROR_PAGE };

# :TRICKY:08/09/2011 13:30:40:es:

# When key/value pairs are copied from a permanent cookie to a session cookie,
# we may want to execute some code, depending on which symbols we encounter in
# the permanent cookie. The code executed would, in its turn, produce key/value
# tuples that would be then stored in the session cookie. At the same time, the
# code directly copying the key/value pairs may not know which symbols it will
# encounter.

# This is similar to the Visitor pattern except that Visitor operates on
# objects (and executes methods depending on the classes of objects it
# encounters), and our class operates on key-value pairs (which of course can
# be represented as objects but we choose not to, since key symbols are already
# unique and clearly defined). While in the Visitor pattern, the double
# dispatch that occurs depends on the type of Visitor passed and on the type of
# object being operated on, in our case the double dispatch depends on the type
# of Visitor passed and on the key symbols encountered.

# The motivation of doing things this way (instead of simply including the code
# into SGX::Session::User) is that our event handling code may query different
# tables and/or databases that we do not want SGX::Session::User to know about.
# This way we implement separation of concerns.

my $perm2session = {
    curr_proj => sub {

        # note that we are not using dbh from within User class -- in theory
        # user and session tables could be stored in a separate database.
        my $curr_proj = shift;
        return ( proj_name => '' ) unless defined($curr_proj);
        my $sth = $dbh->prepare('SELECT prname FROM project WHERE prid=?');
        my $rc  = $sth->execute($curr_proj);
        if ( $rc != 1 ) {
            $sth->finish;
            return ( proj_name => '' );
        }
        my ($full_name) = $sth->fetchrow_array;
        $sth->finish;
        return ( proj_name => $full_name );
      }
};

my $s = SGX::Session::User->new(
    dbh          => $dbh,
    expire_in    => 3600,           # expire in 3600 seconds (1 hour)
    check_ip     => 1,
    perm2session => $perm2session
);

$s->restore( $q->param('sid') );    # restore old session if it exists

#---------------------------------------------------------------------------
#  Main
#---------------------------------------------------------------------------
my %controller_context = (
    dbh          => $dbh,
    cgi          => $q,
    user_session => $s,
);

# Action constants can evaluate to anything, but must be different from already
# defined actions.  One can also use an enum structure to formally declare the
# input alphabet of all possible actions, but then the URIs would not be
# human-readable anymore.

#---------------------------------------------------------------------------
#  Dispatch table that associates action symbols ('?a=' URL parameter) with
#  names of packages to which corresponding functionality is delegated. In
#  combination with the dispatcher block below the table, we implement a
#  Strategy pattern where modules listed below are ConcreteStrategies (exposing
#  interface common to abstract class Strategy -- to be implemented) and the
#  dispatch plus dispatcher are Context. CONSEQUENCES: (a) have all
#  participating modules inherit from the same abstract class; (b) if possible,
#  move the dispatcher code into a separate Context class.
#---------------------------------------------------------------------------
my %dispatch_table = (

    # :TODO:08/07/2011 20:39:03:es: come up with nouns to replace verbs for
    # better RESTfulness
    #
    # verbs
    uploadAnnot        => 'SGX::UploadAnnot',
    uploadData         => 'SGX::UploadData',
    outputData         => 'SGX::OutputData',
    compareExperiments => 'SGX::CompareExperiments',
    findProbes         => 'SGX::FindProbes',
    getTFS             => 'SGX::TFSDisplay',
    graph              => 'SGX::Graph',
    ''                 => 'SGX::Static',

    # nouns
    platforms   => 'SGX::ManagePlatforms',
    projects    => 'SGX::ManageProjects',
    studies     => 'SGX::ManageStudies',
    experiments => 'SGX::ManageExperiments',
    users       => 'SGX::ManageUsers',

    profile => 'SGX::Profile',
);

my $loadModule;

#---------------------------------------------------------------------------
#  This is our own super-cool custom dispatcher and dynamic loader
#---------------------------------------------------------------------------
my $action = ( defined( $q->url_param('a') ) ) ? $q->url_param('a') : '';

# :TODO:10/15/2011 23:07:12:es: throw 404 error here if cannot find a module
# that corresponds to the given action.
my $module = $dispatch_table{$action}
  or croak "Invalid action name $action";

#---------------------------------------------------------------------------
#  first get the Perl module needed
#---------------------------------------------------------------------------
$loadModule = eval {

    # convert Perl path to system path and load the file
    ( my $file = $module ) =~ s/::/\//g;
    require "$file.pm";    ## no critic
    $module->new( selector => $action, %controller_context );
} or do {
    my $error = $@;
    croak "Error loading module $module. The message returned was:\n\n$error";
};

#---------------------------------------------------------------------------
#  next, prepare header and body
#---------------------------------------------------------------------------
if ( $loadModule->dispatch_js() ) {

    #---------------------------------------------------------------------------
    #  show body
    #---------------------------------------------------------------------------

    $s->commit();    # flushes the session data and prepares cookies
    eval { $dbh->disconnect() }; # do not disconnect before session data are committed

    # :TODO:08/07/2011 18:56:16:es: Currently the single point of output
    # rule only applies to HTTP response body (the formed HTML). It would be
    # desirable to make changes to existing code to have the same behavior
    # apply to response headers.

    my %header_command_body = (
        -status => 200,                  # 200 OK
        -type   => 'text/html',          # do not send Content-Type
        -cookie => $s->cookie_array(),
        $loadModule->get_header()
    );

    # This is the only statement in the entire application that prints HTML
    # body.
    print

      # HTTP response header
      $q->header(%header_command_body),

      # HTTP response body
      $loadModule->view_show_content();
}
else {

    #---------------------------------------------------------------------------
    #  print a header with no body and exit
    #---------------------------------------------------------------------------

    $s->commit();

    # by default, we add cookies, unless -cookie=>undef
    my %header_command = (

        #-status => 204,                  # 204 No Content -- default status
        -type   => '',                   # do not send Content-Type
        -cookie => $s->cookie_array(),
        $loadModule->get_header()
    );

    $s->commit();    # flushes the session data and prepares cookies
    eval { $dbh->disconnect() }; # do not disconnect before session data are committed

    print $q->header(%header_command), $loadModule->get_body();
}

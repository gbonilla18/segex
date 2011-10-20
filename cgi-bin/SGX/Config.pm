package SGX::Config;

use strict;
use warnings;
use base qw/Exporter/;

use Readonly ();
use File::Basename qw/dirname/;
use SGX::Util qw/replace/;

# :TODO:07/31/2011 17:53:33:es: replace current exporting behavior (symbols are
# exported by default with @EXPORT) with one where symbols need to be
# explicitely specified (@EXPORT_OK).
our @EXPORT =
  qw/PROJECT_NAME CGI_ROOT YUI_BUILD_ROOT DOCUMENTS_ROOT IMAGES_DIR JS_DIR CSS_DIR/;

our @EXPORT_OK = qw/init_context get_module_from_action require_path/;

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
sub get_module_from_action {
    Readonly::Hash my %dispatch_table => (

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
    my $action = shift;
    return $dispatch_table{$action};
}

#---------------------------------------------------------------------------
#  Path to default mailer executable (sendmail, postfix, etc). On both Mac OS X
#  and CentOS, this is /usr/sbin.
#---------------------------------------------------------------------------
use constant MAILER_PATH => '/usr/sbin';

#---------------------------------------------------------------------------
#  General
#---------------------------------------------------------------------------
use constant PROJECT_NAME => 'Segex';

#---------------------------------------------------------------------------
#  Directories
#---------------------------------------------------------------------------
# convert cgi root to documents root by dropping /cgi-bin prefix
use constant CGI_ROOT       => dirname( $ENV{SCRIPT_NAME} );
use constant DOCUMENTS_ROOT => replace( CGI_ROOT, '^\/cgi-bin', '' );
use constant YUI_BUILD_ROOT => '/yui/build';

use constant IMAGES_DIR => DOCUMENTS_ROOT . '/images';
use constant JS_DIR     => DOCUMENTS_ROOT . '/js';
use constant CSS_DIR    => DOCUMENTS_ROOT . '/css';

#---------------------------------------------------------------------------
#  Set $ENV{PATH} by transforming an input list of symbols in qw//. This also
#  strips all trailing slashes from individual paths.
#---------------------------------------------------------------------------
$ENV{PATH} = join(
    ':',
    keys %{
        {
            map {
                ( my $key = ( \&$_ )->() ) =~ s/\/*$//;
                $key => undef
              } qw/MAILER_PATH/
        }
      }
);

#===  FUNCTION  ================================================================
#         NAME:  require_path
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Converts strings such as SGX::Abstract::JSEmitter into
#                something like SGX/Abstract/JSEmitter.pm
#
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub require_path {
    my $module_string = shift;
    $module_string =~ s/::/\//g;
    require "$module_string.pm";    ## no critic
    return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  init_context
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init_context {
    my $q = shift;

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

    my @init_messages;
    my $dbh = eval {
        require DBI;
        require Exception::Class::DBI;
        DBI->connect(

 # :TODO:07/13/2011 15:20:26:es: Consider allowing "mysql_local_infile" only for
 # special kinds of users (ones who have permission to upload data/annotation)
            'dbi:mysql:segex_dev;mysql_local_infile=1',
            'segex_dev_user',
            'b00g3yk1d',
            {
                PrintError  => 0,
                RaiseError  => 0,
                HandleError => Exception::Class::DBI->handler
            }
        );
    } or do {
        my $exception = $@;
        push @init_messages, [ { -class => 'error' }, "$exception" ];
    };

    # now setup session
    my $s;
    if ( defined $dbh ) {
        require SGX::Session::User;
        $s = SGX::Session::User->new(
            dbh          => $dbh,
            expire_in    => 3600,    # expire in 3600 seconds (1 hour)
            check_ip     => 1,
            perm2session => {
                curr_proj => sub {

            # note that we are not using dbh from within User class -- in theory
            # user and session tables could be stored in a separate database.
                    my $value = shift;
                    return ( proj_name => '' ) unless defined($value);
                    my $sth =
                      $dbh->prepare('SELECT prname FROM project WHERE prid=?');
                    my $rc = $sth->execute($value);
                    if ( $rc != 1 ) {
                        $sth->finish;
                        return ( proj_name => '' );
                    }
                    my ($full_name) = $sth->fetchrow_array;
                    $sth->finish;
                    return ( proj_name => $full_name );
                  }
            }
        );
        $s->restore( $q->param('sid') );    # restore old session if it exists
    }

    return (
        _cgi         => $q,
        _dbh         => $dbh,
        _UserSession => $s,
        _messages    => \@init_messages
    );
}

1;

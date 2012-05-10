package SGX::Config;

use strict;
use warnings;
use base qw/Exporter/;

# :TRICKY:05/04/2012 16:55:21:es:
# -nosticky: Prevent CGI.pm from printing hidden .cgifields inside a form
# without us specifically asking it so.
# -no_xhtml: By default, CGI.pm versions 2.69 and higher emit XHTML. This pragma
# disables this feature.
# use CGI::Pretty 2.47 qw/-nosticky -private_tempfiles -no_xhtml/;
use CGI 2.47 qw/-nosticky -private_tempfiles/;
use Readonly ();
use File::Basename qw/dirname/;

use SGX::Util qw/replace car/;
use SGX::Abstract::Exception ();

our @EXPORT_OK =
  qw/%SEGEX_CONFIG $YUI_BUILD_ROOT $IMAGES_DIR $JS_DIR $CSS_DIR carp croak/;

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
Readonly::Hash our %DISPATCH_TABLE => (

    # :TODO:08/07/2011 20:39:03:es: come up with nouns to replace verbs for
    # better RESTfulness ('a='-level actions indicate resources...)

    # verbs
    uploadData => 'SGX::UploadData',
    uploadGO   => 'SGX::UploadGO',

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
    species     => 'SGX::ManageSpecies',

    profile => 'SGX::Profile',
);

our %SEGEX_CONFIG;

BEGIN {

    # have to import from CGI::Carp in an extra BEGIN{} block
    BEGIN {

    #---------------------------------------------------------------------------
    #  load config options from file
    #---------------------------------------------------------------------------
        require Config::General;
        my $conf = Config::General->new(
            -ConfigFile => dirname($0) . '/segex.conf',
            -AutoTrue   => 1
        );
        %SEGEX_CONFIG = $conf->getall();

    #---------------------------------------------------------------------------
    #  figure out which symbols to import from CGI::Carp
    #---------------------------------------------------------------------------
        require CGI::Carp;
        my @carp_imports = qw/croak carp carpout/;
        if ( $SEGEX_CONFIG{debug_errors_to_browser} ) {
            push @carp_imports, qw/fatalsToBrowser warningsToBrowser/;
        }
        CGI::Carp->import(@carp_imports);
    }

    #---------------------------------------------------------------------------
    #  Whether to print to custom error log
    #---------------------------------------------------------------------------
    if ( defined $SEGEX_CONFIG{debug_log_path} ) {

        # untaint path (NUL character is the only character forbidden in paths
        # on UNIX).
        my ($debug_log_path) = $SEGEX_CONFIG{debug_log_path} =~ m/^([^\0]+)$/i;

        open( my $LOG, '>>', $debug_log_path )
          or croak "Unable to append to log file at $debug_log_path $!";

        carpout($LOG);
    }

    #---------------------------------------------------------------------------
    # Whether to display caller info for warnings
    #---------------------------------------------------------------------------
    if ( $SEGEX_CONFIG{debug_caller_info} ) {
        $SIG{__WARN__} = sub {
            my @loc       = caller(1);
            my $timestamp = scalar localtime();
            my $header    = "[$timestamp]";
            my ( $module, $file, $line, $block ) = @loc;
            $header .= " $file line $line:"    if defined $file;
            $header .= ' Warning';
            $header .= " when called $block()" if defined $block;
            $header .= ':';
            warn $header, "\n", @_;
            return 1;
        };
    }
}

#---------------------------------------------------------------------------
#  Directories
#---------------------------------------------------------------------------
# converting CGI_ROOT to documents root by dropping /cgi-bin prefix
Readonly::Scalar my $DOCUMENTS_ROOT =>
  replace( dirname( $ENV{SCRIPT_NAME} ), '^\/cgi-bin', '' );
Readonly::Scalar our $IMAGES_DIR     => "$DOCUMENTS_ROOT/images";
Readonly::Scalar our $JS_DIR         => "$DOCUMENTS_ROOT/js";
Readonly::Scalar our $CSS_DIR        => "$DOCUMENTS_ROOT/css";
Readonly::Scalar our $YUI_BUILD_ROOT => $SEGEX_CONFIG{yui_build_root};

#---------------------------------------------------------------------------
#  Error messages
#---------------------------------------------------------------------------
Readonly::Hash my %DBI_errors => (
    2002 => 'The database server doesn\'t appear to be running',
    1045 => 'The database is not configured correctly'
);

# :TRICKY:05/04/2012 16:46:23:es: Untaint $ENV{PATH} by transforming an input
# list of symbols in qw//. This also strips all trailing slashes from individual
# paths. WARNING: if you remove the block below, everything will seem to work
# OK, but Segex will be unable to send out user registration emails!
$ENV{PATH} = join(
    ':',
    keys %{
        {
            map {
                ( my $key = $_ ) =~ s/\/*$//;
                $key => undef
              } ( $SEGEX_CONFIG{mailer_path} )
        }
      }
);

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Config
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my $class    = shift;
    my $q        = CGI->new();
    my ($action) = $q->url_param('a');
    $action = '' if !defined($action);
    my $self = {
        _cgi          => $q,
        _ResourceName => $action,
    };
    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Config
#       METHOD:  get_module_name
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_module_name {
    my $self          = shift;
    my $resource      = $self->{_ResourceName};
    my $module_string = $DISPATCH_TABLE{$resource};
    if ( !defined($module_string) ) {
        SGX::Exception::HTTP->throw(
            error  => "Resource not found: $resource",
            status => 404
        );
    }
    return $module_string;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Config
#       METHOD:  get_context
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Using this to keep configuration options in one place
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_context {
    my $self = shift;
    my $q    = $self->{_cgi};

 # :TRICKY:08/09/2011 13:30:40:es:
 #
 # Regarding perm2session attribute being set a few blocks below:
 #
 # When key/value pairs are copied from a permanent cookie to a session cookie,
 # we may want to execute some code, depending on which symbols we encounter in
 # the permanent cookie. The code executed would, in its turn, produce key/value
 # tuples that would be then stored in the session cookie. At the same time, the
 # code directly copying the key/value pairs may not know which symbols it will
 # encounter.
 #
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

        # :TODO:07/13/2011 15:20:26:es: Consider allowing "mysql_local_infile"
        # only for special category of users (ones who have permission to upload
        # data/annotation). This would require two different databases, one for
        # user authentication data, another for actual data.
        DBI->connect(
            "dbi:mysql:$SEGEX_CONFIG{dbname};mysql_local_infile=1",
            $SEGEX_CONFIG{dbuser},
            $SEGEX_CONFIG{dbpassword},
            {
                PrintError  => 0,
                RaiseError  => 0,
                HandleError => Exception::Class::DBI->handler
            }
        );
    } or do {
        my $exception;
        if ( $exception = Exception::Class->caught('Exception::Class::DBI') ) {

# Since we know this is a DBI exception, we can use Exception::Class::DBI
# methods err() and errstr() to return error code and error message,
# respectively. The error() method inherited from Exception::Class gives out too
# much information (such as code snipped containing MySQL user name), so we are
# not using it. More on err() and errstr() methods:
# http://search.cpan.org/~dwheeler/Exception-Class-DBI-1.01/lib/Exception/Class/DBI.pm#Exception::Class::DBI
            my $errornum = $exception->err;
            if ( $exception->isa('Exception::Class::DBI::DRH')
                && exists( $DBI_errors{$errornum} ) )
            {
                push @init_messages, [ {}, $DBI_errors{$errornum} ];
            }
            push @init_messages,
              [
                { -class => 'error' },
                sprintf( 'DBI Error %d: %s', $errornum, $exception->errstr )
              ];
        }
        elsif ( $exception = Exception::Class->caught() ) {

            # any other exception
            my $msg =
              eval { $exception->error } || "$exception" || 'Unknown error';
            push @init_messages,
              [ {}, "Can't connect to the database" ],
              [ { -class => 'error' }, $msg ];
        }
        else {

            # unknown error
            push @init_messages, [ {}, "Can't connect to the database" ];
        }

        # set database handle to undefined value on error
        undef;
    };

    # setup session if have database handle
    my $s = defined($dbh)
      ? do {
        require SGX::Session::User;
        SGX::Session::User->new(
            dbh          => $dbh,
            expire_in    => $SEGEX_CONFIG{timeout},
            check_ip     => 1,
            perm2session => {
                curr_proj => sub {

                    # Not using database handle from within User class; ideally
                    # user and session tables should be stored in a separate
                    # database from the rest of the data.
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
      }
      : undef;

    return (
        _ResourceName => $self->{_ResourceName},
        _cgi          => $q,
        _dbh          => $dbh,
        _UserSession  => $s,
        _messages     => \@init_messages
    );
}

1;

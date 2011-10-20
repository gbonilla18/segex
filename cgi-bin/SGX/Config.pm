package SGX::Config;

use strict;
use warnings;
use base qw/Exporter/;

require Exception::Class::DBI;
use File::Basename qw/dirname/;
use SGX::Util qw/replace/;

# :TODO:07/31/2011 17:53:33:es: replace current exporting behavior (symbols are
# exported by default with @EXPORT) with one where symbols need to be
# explicitely specified (@EXPORT_OK).
our @EXPORT =
  qw/PROJECT_NAME CGI_ROOT YUI_BUILD_ROOT DOCUMENTS_ROOT IMAGES_DIR JS_DIR CSS_DIR sgx_db_connect/;

#---------------------------------------------------------------------------
#  Database-specific
#---------------------------------------------------------------------------
# :TODO:07/13/2011 15:20:26:es: Consider allowing "mysql_local_infile" only for
# special kinds of users (ones who have permission to upload data/annotation)
use constant DATABASE_STRING => 'dbi:mysql:segex_dev;mysql_local_infile=1';
use constant DATABASE_USER   => 'segex_dev_user';
use constant DATABASE_PWD    => 'b00g3yk1d';

#---------------------------------------------------------------------------
#  Path to default mailer executable (sendmail, postfix, etc). On both Mac OS X
#  and CentOS, this is /usr/sbin.
#---------------------------------------------------------------------------
use constant MAILER_PATH => '/usr/sbin';

#---------------------------------------------------------------------------
#  General
#---------------------------------------------------------------------------
use constant PROJECT_NAME => 'SEGEX';

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
#         NAME:  sgx_db_connect
#      PURPOSE:  simplify getting database handle
#   PARAMETERS:  n/a
#      RETURNS:  database handle object
#  DESCRIPTION:  ????
#       THROWS:  $DBI::errstr
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub sgx_db_connect {

    my $dbh = DBI->connect(
        DATABASE_STRING,
        DATABASE_USER,
        DATABASE_PWD,
        {
            PrintError  => 0,
            RaiseError  => 0,
            HandleError => Exception::Class::DBI->handler
        }
    );
    return $dbh;
}

1;

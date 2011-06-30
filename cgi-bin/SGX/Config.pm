package SGX::Config;

use strict;
use warnings;
use base qw/Exporter/;

use Carp;
use File::Basename;
use Exception::Class::DBI;

use SGX::Util qw/replace/;

our @EXPORT =
  qw/PROJECT_NAME CGI_ROOT YUI_BUILD_ROOT DOCUMENTS_ROOT IMAGES_DIR JS_DIR CSS_DIR
  sgx_db_connect/;

#---------------------------------------------------------------------------
#  Database-specific
#---------------------------------------------------------------------------
use constant DATABASE_STRING => 'dbi:mysql:segex_dev';
use constant DATABASE_USER   => 'segex_dev_user';
use constant DATABASE_PWD    => 'b00g3yk1d';

#---------------------------------------------------------------------------
#  General
#---------------------------------------------------------------------------
use constant PROJECT_NAME    => 'SEGEX';

#use constant SPECIES      => 'mouse';    # hardcoding species for now

#---------------------------------------------------------------------------
#  Directories
#---------------------------------------------------------------------------
# convert cgi root to documents root by dropping /cgi-bin prefix
use constant CGI_ROOT       => dirname( $ENV{SCRIPT_NAME} );
use constant DOCUMENTS_ROOT => replace( CGI_ROOT, '^\/cgi-bin', '' );
use constant YUI_BUILD_ROOT       => '/yui/build';

use constant IMAGES_DIR => DOCUMENTS_ROOT . '/images';
use constant JS_DIR     => DOCUMENTS_ROOT . '/js';
use constant CSS_DIR    => DOCUMENTS_ROOT . '/css';

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

    my $dbh = DBI->connect( DATABASE_STRING, DATABASE_USER, DATABASE_PWD, {
        PrintError  => 0,
        RaiseError  => 0,
        HandleError => Exception::Class::DBI->handler
    });
    return $dbh;
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
sub about_text
{
    my ($q, %param) = @_;
    return $q->h2('About'),
        $q->p('The mammalian liver functions in the stress response, immune response, drug metabolism and protein synthesis. Sex-dependent responses to hepatic stress are mediated by pituitary secretion of growth hormone (GH) and the GH-responsive nuclear factors STAT5a, STAT5b and HNF4-alpha. Whole-genome expression arrays were used to examine sexually dimorphic gene expression in mouse livers.'),
        $q->p('This SEGEX database provides public access to previously released datasets from the Waxman laboratory, and provides data mining tools and data visualization to query gene expression across several studies and experimental conditions.'),
        $q->p('Developed at Boston University as part of the BE768 Biologic Databases course, Spring 2009, G. Benson instructor. Student developers: Anna Badiee, Eugene Scherba, Katrina Steiling and Niraj Trivedi. Faculty advisor: David J. Waxman.'),
        $q->p($q->a({-href=>$q->url(-absolute=>1) . '?a=' . $param{showSchema}}, 'View database schema'));
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
sub main_text
{
    my ($q, %param) = @_;
    return 
        $q->p('The SEGEX database will provide public access to previously released datasets from the Waxman laboratory, and data mining and visualization modules to query gene expression across several studies and experimental conditions.'),
        $q->p('This database was developed at Boston University as part of the BE768 Biological Databases course, Spring 2009, G. Benson instructor. Student developers: Anna Badiee, Eugene Scherba, Katrina Steiling and Niraj Trivedi. Faculty advisor: David J. Waxman.');
}

1;

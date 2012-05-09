#
#===============================================================================
#
#         FILE:  DBHelper.pm
#
#  DESCRIPTION:
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  03/13/2012 11:18:02
#     REVISION:  ---
#===============================================================================

package SGX::DBHelper;

use strict;
use warnings;

require Data::UUID;
use SGX::Abstract::Exception ();
use SGX::Util qw/car/;

#===  CLASS METHOD  ============================================================
#        CLASS:  DBHelper
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================

sub new {
    my $class = shift;
    my %args  = @_;
    my $self  = { _delegate => $args{delegate} };
    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  DBHelper
#       METHOD:  createTempTable
#   PARAMETERS:  n/a
#      RETURNS:  name of the temporary table
#  DESCRIPTION:  Set up temporary table
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub createTempTable {
    my $self      = shift;
    my $name_type = shift;

    my ( $name, $type ) = @$name_type;
    my $delegate = $self->{_delegate};
    my $dbh      = $delegate->{_dbh};

    my $ug         = Data::UUID->new();
    my $temp_table = $ug->to_string( $ug->create() );
    $temp_table =~ s/-/_/g;
    $temp_table = "tmp$temp_table";

    my $sql = <<"END_createTable";
CREATE TEMPORARY TABLE $temp_table (
    $name $type, 
    UNIQUE KEY $name ($name)
) ENGINE=MEMORY
END_createTable

    my $rc = $dbh->do($sql);
    return $temp_table;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  DBHelper
#       METHOD:  createTempList
#   PARAMETERS:  items => [1,2,3...],
#                type  => 'int(10) unsigned'
#      RETURNS:  Name of the temporary table created
#  DESCRIPTION:  Create a list in the database represented as a table with a
#                single column.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub createTempList {
    my $self      = shift;
    my %args      = @_;
    my $items     = $args{items};
    my $name_type = $args{name_type};

    my $delegate = $self->{_delegate};
    my $dbh      = $delegate->{_dbh};

    #---------------------------------------------------------------------------
    #  batch-insert using DBI execute_array() for high speed
    #---------------------------------------------------------------------------
    my $temp_table = $self->createTempTable($name_type);
    my $sth        = $dbh->prepare("INSERT IGNORE INTO $temp_table VALUES (?)");
    my @tuple_status;
    my $rc = eval {
        $sth->execute_array( { ArrayTupleStatus => \@tuple_status }, $items ) +
          0;
    } or do {
        my $exception = Exception::Class->caught();
        my $msg = eval { $exception->error } || "$exception" || 'Empty list';
        $delegate->add_message( { -class => 'error' }, $msg );
        0;
    };
    $sth->finish();
    if ( !$rc ) {
        for my $tuple ( 0 .. $#$items ) {
            my $status = $tuple_status[$tuple];
            $status = [ 0, "Skipped" ] unless defined $status;
            next unless ref $status;
            $delegate->add_message(
                { -class => 'error' },
                sprintf(
                    "There were errors. Failed to insert (%s): %s\n",
                    $items->[$tuple], $status->[1]
                )
            );
            return $temp_table;
        }
    }
    return $temp_table;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  DBHelper
#       METHOD:  uploadFileToTemp
#   PARAMETERS:  filename => 'string'
#                delete_file => [1|0]
#                name_type  => ['rid', 'int(10) unsigned']
#      RETURNS:  Name of the temporary table created
#  DESCRIPTION:  Create a list in the database represented as a table with a
#                single column.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub uploadFileToTemp {
    my $self        = shift;
    my %args        = @_;
    my $filename    = $args{filename};
    my $name_type   = $args{name_type};
    my $delete_file = ( exists $args{delete_file} ) ? $args{delete_file} : 1;
    my ( $name, $type ) = @$name_type;

    my $delegate = $self->{_delegate};
    my $dbh      = $delegate->{_dbh};

    #---------------------------------------------------------------------------
    #  batch-insert using LOAD
    #---------------------------------------------------------------------------
    my $temp_table = $self->createTempTable($name_type);

    my $sth = $dbh->prepare(<<"END_loadData");
LOAD DATA LOCAL INFILE ?
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' ($name)
END_loadData

    my $rc = eval { $sth->execute($filename) } or do {
        my $exception;
        if ( $exception =
            Exception::Class->caught('Exception::Class::DBI::STH') )
        {

            # Note: this block catches duplicate key record exceptions among
            # others
            $delegate->add_message(
                { -class => 'error' },
                sprintf(
                    'DBI Error %d: %s',
                    $exception->err, $exception->errstr
                )
            );
        }
        else {

            # Other types of exceptions
            $exception = Exception::Class->caught();
            my $msg =
                 eval { $exception->error }
              || "$exception"
              || 'File appears to be empty';
            $delegate->add_message( { -class => 'error' },
                "No records loaded: $msg" );
        }
        $sth->finish();
        unlink $filename if $delete_file;
        return $temp_table;
    };
    $sth->finish;
    unlink $filename if $delete_file;
    return $temp_table;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  DBHelper
#       METHOD:  getSessionOverrideCGI
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Gets full user name from session and full project name from CGI
#                parameters or session in that order. Also sets project id.
#       THROWS:  SGX::Exception::Internal, Class::Exception::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getSessionOverrideCGI {
    my $delegate = shift;                     # substituting for self
    my $self     = $delegate->{_delegate};    # substituting for delegate

    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};

    # For user name, just look it up from the session
    $self->{_UserFullName} =
      ( defined $s )
      ? $s->{session_cookie}->{full_name}
      : '';

    # :TRICKY:06/28/2011 13:47:09:es: We implement the following behavior: if,
    # in the URI option string, "proj" is set to some value (e.g. "proj=32") or
    # to an empty string (e.g. "proj="), we set the data field _WorkingProject
    # to that value; if the "proj" option is missing from the URI, we use the
    # value of "curr_proj" from session data. This allows us to have all
    # portions of the data accessible via a REST-style interface regardless of
    # current user preferences.
    my $cgi_proj = car $q->param('proj');
    if ( !defined($cgi_proj) && defined($s) ) {
        $cgi_proj = $s->{session_cookie}->{curr_proj};
    }
    if ( !defined($cgi_proj) || $cgi_proj !~ /^\d+$/ ) {
        $cgi_proj = '';
    }
    my $proj_name = '@All Projects';
    if ( $cgi_proj ne '' ) {

        # now need to obtain project name from the database
        my $sth = $dbh->prepare(qq{SELECT prname FROM project WHERE prid=?});
        my $rc  = $sth->execute($cgi_proj);
        if ( $rc == 1 ) {

            # project exists in the database
            ($proj_name) = $sth->fetchrow_array;
            $sth->finish;
        }
        elsif ( $rc < 1 ) {

            # project doesn't exist in the database
            $sth->finish;
            $cgi_proj = '';
        }
        else {
            $sth->finish;
            SGX::Exception::Internal->throw( error =>
                  "More than one result returned where unique was expected\n" );
        }
    }
    $self->{_WorkingProjectName} = $proj_name;
    return 1;
}
1;

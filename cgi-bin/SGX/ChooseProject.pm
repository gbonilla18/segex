
=head1 NAME

SGX::ChooseProject

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::ChooseProject;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

use Data::Dumper;
use Switch;

#use DBI;
{

    package SGX::DropDownData;

    use strict;
    use warnings;

    #use Data::Dumper;
    use CGI::Carp qw/croak/;
    use Tie::IxHash;

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  new
#   PARAMETERS:  0) $self  - object instance
#                1) $dbh   - database handle
#                2) $query - SQL query string (with or without placeholders)
#      RETURNS:  $self
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  :NOTE:06/01/2011 03:32:37:es: preparing query once during
#                  construction
#     SEE ALSO:  n/a
#===============================================================================
    sub new {
        my ( $class, $dbh, $query ) = @_;

        my $sth = $dbh->prepare($query)
          or croak $dbh->errstr;

        my $self = {
            _dbh  => $dbh,
            _sth  => $sth,
            _tied => undef,
            _hash => {},
        };

        # Tying the hash using Tie::IxHash module allows us to keep hash
        # keys ordered
        $self->{_tied} = tie( %{ $self->{_hash} }, 'Tie::IxHash' );

        bless $self, $class;
        return $self;
    }

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  clone
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is a copy constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
    sub clone {
        my $self = shift;

        my $clone = {
            _dbh  => $self->{_dbh},
            _sth  => $self->{_sth},
            _tied => undef,
            _hash => {},
        };

        # Tying the hash using Tie::IxHash module allows us to keep hash
        # keys ordered
        $clone->{_tied} = tie( %{ $clone->{_hash} }, 'Tie::IxHash' );

        # now fill the new hash
        $clone->{_tied}->Push( %{ $self->{_hash} } );

        bless $clone, ref $self;
        return $clone;
    }

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  loadDropDownValues
#   PARAMETERS:  $self
#                @params - array of parameters to be used to fill placeholders
#                in the query statement
#      RETURNS:  reference to drop down data stored in key-value format (hash)
#  DESCRIPTION:  loads values by executing query
#       THROWS:  no exceptions
#     COMMENTS:  :NOTE:06/01/2011 03:31:28:es: allowing this method to be
#                 executed more than once
#     SEE ALSO:  http://search.cpan.org/~chorny/Tie-IxHash-1.22/lib/Tie/IxHash.pm
#===============================================================================
    sub loadDropDownValues {
        my ( $self, @params ) = @_;

        my $rc = $self->{_sth}->execute(@params)
          or croak $self->{_dbh}->errstr;

        my @sthArray = @{ $self->{_sth}->fetchall_arrayref };

        $self->{_sth}->finish;

        my $hash_ref = $self->{_hash};
        foreach (@sthArray) {
            my $k = $_->[0];
            croak "Conflicting key '$k' in output hash"
              if exists $hash_ref->{$k};
            $hash_ref->{$k} = $_->[1];
        }

        return $hash_ref;
    }

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  Push
#   PARAMETERS:  0) $self
#                1) list of key-value pairs, e.g. Push('0' => 'All Values', ...)
#      RETURNS:  Same as Tie::IxHash::Push
#  DESCRIPTION:  Add key-value array to hash using Tie::IxHash object
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
    sub Push {
        my ( $self, @rest ) = @_;
        return $self->{_tied}->Push(@rest);
    }

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  Unshift
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Wraps the Unshift method in Tie::IxHash
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
    sub Unshift {
        my ( $self, @rest ) = @_;
        return $self->{_tied}->Unshift(@rest);
    }

    1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, @param ) = @_;
    my $self = $class->SUPER::new(@param);

    $self->set_attributes(
        _title => 'Choose Project',

        # model
        _curr_proj   => '',
        _projectList => {}
    );

    $self->register_actions(
        'head' => { '' => 'default_head', 'Change' => 'Change_head' },
        'body' => { '' => 'getSwitchProjectFormHTML' }
    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  Change_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================

sub Change_head {
    my $self = shift;
    my $s    = $self->{_UserSession};
    return unless $s->is_authorized('user');

    $self->cp_init();
    $self->changeToCurrent();

    # load data for the form
    $self->loadProjectData();

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  default_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_head {
    my $self = shift;
    my $s    = $self->{_UserSession};

    # default action -- only load data for the form
    return unless $s->is_authorized('user');
    $self->cp_init();
    $self->loadProjectData();

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  changeToCurrent
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub changeToCurrent {
    my $self = shift;
    my $s    = $self->{_UserSession};

    # store id in a permanent cookie (also gets copied to the
    # session cookie automatically)
    $s->perm_cookie_store( curr_proj => $self->{_curr_proj} );

    # no need to store the working project name in permanent storage
    # (only store the working project id there) -- store it only in
    # the session cookie (which is read every time session is
    # initialized).
    $s->session_cookie_store( proj_name => $self->getProjectName() );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Only load form data and URL parameters here -- do not
#                undertake anything here that would cause change of external
#                state.
#     SEE ALSO:  n/a
#===============================================================================
sub cp_init {
    my $self = shift;
    my ( $q, $s ) = @$self{qw{_cgi _UserSession}};

    # First tries to get current project id from the CGI parameter; failing
    # that, looks it up from the session cookie.

    my $curr_proj = $q->param('proj');
    $self->{_curr_proj} =
      defined($curr_proj)
      ? $curr_proj
      : $s->{session_cookie}->{curr_proj};

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  loadProjectData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Display a list of projects
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadProjectData {
    my $self = shift;

    my $sql = 'SELECT prid, prname FROM project ORDER BY prname ASC';
    my $projectDropDown = SGX::DropDownData->new( $self->{_dbh}, $sql );

    $projectDropDown->Push( '' => 'All Projects' );
    $self->{_projectList} = $projectDropDown->loadDropDownValues();

    #warn Dumper( $self->{_projectList} );
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  getProjectName
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  We choose empty string to mean 'All projects'
#     SEE ALSO:  n/a
#===============================================================================
sub getProjectName {
    my $self = shift;
    my $dbh  = $self->{_dbh};

    my $curr_proj = $self->{_curr_proj};

    return '' unless defined($curr_proj);
    my $sth = $dbh->prepare('SELECT prname FROM project WHERE prid=?');
    my $rc  = $sth->execute($curr_proj);
    if ( $rc != 1 ) {
        $sth->finish;
        return '';
    }
    my ($full_name) = $sth->fetchrow_array;
    $sth->finish;
    return $full_name;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  getSwitchProjectFormHTML
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Render the HTML form for changing current project
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {
    my $self = shift;

    my $q = $self->{_cgi};

    #Load the study dropdown to choose which experiments to load into table.
    return $q->h2('Select working project'),
      $q->start_form(
        -method  => 'POST',
        -action  => $q->url( -absolute => 1 ) . '?a=chooseProject',
        -enctype => 'application/x-www-form-urlencoded'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'proj' }, 'Project:' ) ),
        $q->dd(
            $q->popup_menu(
                -name    => 'proj',
                -id      => 'proj',
                -values  => [ keys %{ $self->{_projectList} } ],
                -labels  => $self->{_projectList},
                -default => $self->{_curr_proj},
                -title   => 'Select a project from the list'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -class => 'button black bigrounded',
                -value => 'Change',
                -title => 'Change your working project to the selected one'
            )
        )
      ),
      $q->end_form;
}

1;

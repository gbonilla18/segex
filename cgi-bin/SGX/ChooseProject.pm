
=head1 NAME

SGX::ChooseProject

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHORS
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

use Data::Dumper;
use SGX::DropDownData;
use Switch;
use SGX::Debug qw/assert/;
#use DBI;

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
    my ($class, $dbh, $cgi, $curr_proj) = @_;
    my $self = {
        _dbh                  => $dbh,
        _cgi                  => $cgi,
        _curr_proj            => $curr_proj,
        _ProjectDropdownQuery => 'SELECT prid, prname FROM project ORDER BY prname ASC',
        _LookupProjectQuery   => 'SELECT prname FROM project WHERE prid = ?',
        _projectList          => {}
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch {
    my ( $self, $action ) = @_;
    $action = '' if not defined($action);
    #switch ($action) {
    #    case 'change' {
    #        $self->changeProject();
    #    }
    #    else {
            $self->loadProjectData();
            $self->drawChangeProjectScreen();
    #    }
    #}
    return;
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

    my $projectDropDown =
      SGX::DropDownData->new( $self->{_dbh}, $self->{_ProjectDropdownQuery} );

    $projectDropDown->Push('' => 'All Projects');
    $self->{_projectList} = $projectDropDown->loadDropDownValues();
    return;
}


#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  lookupProjectName
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub lookupProjectName
{
    my $self = shift;
    return undef if not defined($self->{_curr_proj});
    #DBI->trace( 1 );
    my $sth = $self->{_dbh}->prepare($self->{_LookupProjectQuery})
        or croak $self->{_dbh}->errstr;
    my $rc = $sth->execute($self->{_curr_proj})
        or croak $self->{_dbh}->errstr;
    assert($rc == 1);
    my $full_name = $sth->fetchrow_array;
    #warn Dumper(\@full_name);
    $sth->finish;
    return $full_name;
}
#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  drawProjectInfoHeader
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  display area that gets included on each page that shows which 
#                project we have selected
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
#sub drawProjectInfoHeader {
#    my $self = shift;
#
#    $self->{_cgi}->div(
#        { -id => 'projectInfo' },
#        $self->{_cgi}->ul(
#            $self->{_cgi}->li("<h2>Current Project : SEGEX</h2>"),
#            $self->{_cgi}->li(
#                $self->{_cgi}->a(
#                    {
#                        -href => $self->{_cgi}->url( -absolute => 1 )
#                          . '?a=chooseProject',
#                        -title => 'Change Project'
#                    },
#                    'Click here to change current project.'
#                )
#            )
#        )
#    );
#    return;
#}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  drawChangeProjectScreen
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Render the HTML form for changing current project
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub drawChangeProjectScreen {
    my $self = shift;

    #Load the study dropdown to choose which experiments to load into table.
    print 
      $self->{_cgi}->h2('Select working project') .
      $self->{_cgi}->start_form(
        -method => 'POST',
        -action => $self->{_cgi}->url( -absolute => 1 )
          . '?a=chooseProject'
      )
      . $self->{_cgi}->dl(
        $self->{_cgi}->dt('Project:'),
        $self->{_cgi}->dd(
            $self->{_cgi}->popup_menu(
                -name   => 'current_project',
                -id     => 'current_project',
                -values => [keys %{$self->{_projectList}}],
                -labels => $self->{_projectList},
                -default => $self->{_curr_proj}
            )
        ),
        $self->{_cgi}->dt('&nbsp;'),
        $self->{_cgi}->dd(
            $self->{_cgi}->submit(
                -name  => 'change',
                -id    => 'change',
                -class => 'css3button',
                -value => 'Change'
            )
        )
      ) . $self->{_cgi}->end_form;
    return;
}

1;

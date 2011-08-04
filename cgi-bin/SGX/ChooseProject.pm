
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

use Switch;
use Data::Dumper;
use SGX::DropDownData;

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
    my ( $class, %param ) = @_;

    my ( $dbh, $q, $s, $js_src_yui, $js_src_code ) =
      @param{qw{dbh cgi user_session js_src_yui js_src_code}};

    my $self = {
        _dbh         => $dbh,
        _cgi         => $q,
        _UserSession => $s,
        _js_src_yui  => $js_src_yui,
        _js_src_code => $js_src_code,

        # model
        _curr_proj   => '',
        _projectList => {}
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
    my ($self) = @_;
    my $q = $self->{_cgi};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    # regardless of action, show form
    print $self->getFormHTML();

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ChooseProject
#       METHOD:  dispatch_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  deals with model
#       THROWS:  no exceptions
#     COMMENTS:  The most important thing this function *must not* do is print
#                to browser window.
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch_js {
    my ($self) = @_;

    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};
    my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    switch ($action) {
        case 'Change' {
            return unless $s->is_authorized('user');

            $self->init();
            $self->changeToCurrent();

            # load data for the form
            $self->loadProjectData();
        }
        else {

            # default action -- only load data for the form
            return unless $s->is_authorized('user');
            $self->init();
            $self->loadProjectData();
        }
    }

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
sub init {
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
#       METHOD:  getFormHTML
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Render the HTML form for changing current project
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getFormHTML {
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
                -class => 'css3button',
                -value => 'Change',
                -title => 'Change your working project to the selected one'
            )
        )
      ),
      $q->end_form;
}

1;

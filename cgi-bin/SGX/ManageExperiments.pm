
=head1 NAME

SGX::ManageExperiments

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing experiments.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::ManageExperiments;

use strict;
use warnings;

#use Data::Dumper;
use Switch;
use URI::Escape;
use SGX::Model::PlatformStudyExperiment;
use SGX::Abstract::JSEmitter;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  new
#   PARAMETERS:  dbh => $dbh        - DBI database handle
#                cgi => $q          - reference to CGI.pm object instance
#                user_session => $s - SGX::Session::User instance reference
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

    ${$param{title}} = 'Manage Experiments';

    # :TODO:07/01/2011 04:02:51:es: To find out the number of probes for each
    # experiment, run separate queries for better performance
    my $self = {
        _dbh         => $dbh,
        _cgi         => $q,
        _UserSession => $s,
        _js_src_yui  => $js_src_yui,
        _js_src_code => $js_src_code,

        # model
        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $dbh ),

        _Data => undef,
        _stid => undef,
        _pid  => undef,
        _eid  => undef,
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  executes code appropriate for the given action
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

    print $self->getHTML();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  dispatch_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Write JSON model
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

    push @$js_src_yui,
      (
        'yahoo-dom-event/yahoo-dom-event.js', 'connection/connection-min.js',
        'dragdrop/dragdrop-min.js',           'container/container-min.js',
        'element/element-min.js',             'datasource/datasource-min.js',
        'paginator/paginator-min.js',         'datatable/datatable.js',
        'selector/selector-min.js'
      );

    switch ($action) {
        case 'delete' {
            return unless $s->is_authorized('user');

            # :TODO:08/03/2011 10:11:22:es: initialize object from CGI
            # parameters using loadFromForm() or init()
            $self->deleteExperiment(
                id         => $q->param('id'),
                deleteFrom => $q->param('deleteFrom')
            );
            $self->redirectInternal('?a=manageExperiments');
        }
        case 'update' {

            # ajax_update takes care of authorization...
            $self->ajax_update(
                valid_fields => [
                    qw{sample1 sample2 ExperimentDescription AdditionalInformation}
                ],
                table => 'experiment',
                key   => 'eid'
            );
        }
        case 'Load' {
            return unless $s->is_authorized('user');

            $self->{_PlatformStudyExperiment}->init(
                platforms         => 1,
                studies           => 1,
                experiments       => 1,
                platform_by_study => 1,
                extra_platforms   => { 'all' => { name => '@All Platforms' } },
                extra_studies     => { 'all' => { name => '@All Studies' } }
            );
            $self->init();
            $self->loadAllExperimentsFromStudy();

            # load experiments
            push @$js_src_code, { -src  => 'CellUpdater.js' };
            push @$js_src_code, { -code => $self->showExperiments_js() };
            push @$js_src_code, { -src  => 'ManageExperiments.js' };

            # platform drop down
            push @$js_src_code, { -src  => 'PlatformStudyExperiment.js' };
            push @$js_src_code, { -code => $self->getDropDownJS() };
        }
        else {
            return unless $s->is_authorized('user');

            # platform drop down
            $self->{_PlatformStudyExperiment}->init(
                platforms         => 1,
                studies           => 1,
                experiments       => 1,
                platform_by_study => 1,
                extra_platforms   => { 'all' => { name => '@All Platforms' } },
                extra_studies     => { 'all' => { name => '@All Studies' } }
            );
            push @$js_src_code, { -src  => 'PlatformStudyExperiment.js' };
            push @$js_src_code, { -code => $self->getDropDownJS() };
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  redirectInternal
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub redirectInternal {
    my ( $self, $query ) = @_;
    my ( $q,    $s )     = @$self{qw{_cgi _UserSession}};

    # redirect if we know where to... will send a redirect header, so
    # commit the session to data store now
    my $redirectURI =
      ( defined $q->url_param('destination') )
      ? $q->url( -base     => 1 ) . uri_unescape( $q->url_param('destination') )
      : $q->url( -absolute => 1 ) . $query;

    $s->commit();
    print $q->redirect(
        -uri    => $redirectURI,
        -status => 302,                 # 302 Found
        -cookie => $s->cookie_array()
    );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Load state (mostly from CGI parameters)
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    my $q    = $self->{_cgi};

    my $stid = $q->param('stid');
    if ( defined $stid ) {
        $self->{_stid} = $stid;

        # If a study is set, use the corresponding platform while ignoring the
        # platform parameter. Also update the _pid field with the platform id
        # obtained from the lookup by study id.
        my $pid =
          $self->{_PlatformStudyExperiment}->getPlatformFromStudy($stid);
        $self->{_pid} = ( defined $pid ) ? $pid : $q->param('pid');
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  ajax_update
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Update part of CRUD operations. This is a *very generic* method
#                handling AJAX request -- basically update a key-value pair in a
#                specified row in the table.
#       THROWS:  no exceptions
#     COMMENTS:  :TODO:07/04/2011 16:48:45:es: Abstract out this method into a
#                base class for SGX modules.
#                :TODO:07/28/2011 00:38:55:es: Abstract out the model part of
#                this method into the model composable of the abstract class.
#     SEE ALSO:  n/a
#===============================================================================
sub ajax_update {

    my ( $self, %args ) = @_;

    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};

    my $valid_fields = $args{valid_fields};
    my $table        = $args{table};
    my $column       = $args{key};

    my %is_valid_field = map { $_ => 1 } @$valid_fields;

    if ( !$s->is_authorized('user') ) {

        # Send 401 Unauthorized header
        print $q->header( -status => 401 );
        $s->commit;    # must commit session before exit
        exit(0);
    }
    my $field = $q->param('field');
    if ( !defined($field) || $field eq '' || !$is_valid_field{$field} ) {

        # Send 400 Bad Request header
        print $q->header( -status => 400 );
        $s->commit;    # must commit session before exit
        exit(0);
    }

    # after field name has been checked against %valid_fields hash, it
    # is safe to fill it in directly:
    my $query = "update $table set $field=? where $column=?";

    # :TODO:07/27/2011 23:42:00:es: implement transactional updates. Separate
    # statement preparation from execution.

    # Note that when $q->param('value') is undefined, DBI should fill in
    # NULL into the corresponding placeholder.
    my $rc =
      eval { $dbh->do( $query, undef, $q->param('value'), $q->param('id') ); }
      || 0;

    if ( $rc > 0 ) {

        # Normal condition -- at least some rows were updated:
        # Send 200 OK header
        print $q->header( -status => 200 );
        $s->commit;    # must commit session before exit
        exit(1);
    }
    elsif ( my $exception = $@ ) {

        # Error condition -- no rows updated:
        # Send 400 Bad Request header
        print $q->header( -status => 400 );
        $s->commit;    # must commit session before exit
        $exception->throw();
    }
    else {

        # Normal condition -- no rows updated:
        # Send 404 Not Found header
        print $q->header( -status => 404 );
        $s->commit;    # must commit session before exit
        exit(0);
    }
    $s->commit;        # must commit session before exit
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  showExperiments_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Draw the javascript for the experiment table
#       THROWS:  no exceptions
#     COMMENTS:  n/a
#     SEE ALSO:  n/a
#===============================================================================
sub showExperiments_js {
    my ($self) = @_;

    #my @names = @{ $self->{_FieldNames} };
    my $q = $self->{_cgi};

    # set 'destination' URL parameter -- encoded URL to get back to the page we
    # were at.
    my $destination =
      ( defined $q->url_param('destination') )
      ? $q->url_param('destination')
      : uri_escape( $q->url( -absolute => 1, -query => 1 ) );

    my $deleteURL =
      $q->url( -absolute => 1 ) . '?a=manageExperiments'    # top-level action
      . '&b=delete'                    # second-level action
      . "&destination=$destination"    # current URI (encoded)
      . '&id=';    # resource id on which second-level action will be performed

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );
    return $js->define(
        {
            JSStudyList => {
                caption => 'Showing Experiments',
                records => $self->printJSRecords(),
                headers => $self->printJSHeaders()
            },
            url_prefix => $q->url( -absolute => 1 ),
            deleteURL  => $deleteURL
        },
        declare => 1
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  getDropDownJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Returns JSON data plus JavaScript code required to build
#                platform and study dropdowns
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getDropDownJS {
    my $self = shift;

    my $pid  = $self->{_pid};
    my $stid = $self->{_stid};

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );
    return $js->define(
        {
            PlatfStudyExp =>
              $self->{_PlatformStudyExperiment}->get_ByPlatform(),
            currentSelection => {
                'platform' => {
                    element   => undef,
                    selected  => ( defined $pid ) ? { $pid => undef } : {},
                    elementId => 'pid'
                },
                'study' => {
                    element   => undef,
                    selected  => ( defined $stid ) ? { $stid => undef } : {},
                    elementId => 'stid'
                }
            }
        },
        declare => 1
    ) . <<"END_ret";
YAHOO.util.Event.addListener(window, 'load', function() {
    populatePlatform.apply(currentSelection);
    populatePlatformStudy.apply(currentSelection);
});
YAHOO.util.Event.addListener(currentSelection.platform.elementId, 'change', function() {
    populatePlatformStudy.apply(currentSelection);
});
END_ret
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  loadAllExperimentsFromStudy
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loads all experiments from a given study
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadAllExperimentsFromStudy {
    my $self = shift;

    my $dbh = $self->{_dbh};
    my $loadQuery;
    my @exec_param;
    if ( not defined( $self->{_stid} ) or $self->{_stid} eq 'all' ) {

        # all studies -- from a specific platform?
        my $having_platform_clause = '';
        if ( defined $self->{_pid} and not $self->{_pid} eq 'all' ) {
            $having_platform_clause = 'HAVING my_pid=?';
            push @exec_param, $self->{_pid};
        }

# Unassigned experiments will not be linked to a specific study, and the only
# way to find out what platform they are at is through joining probe table.
# We resolve the question of what platform an experiment is on the following
# way: if the experiment is linked to a study, use the platform name/id from the
# study, otherwise determine the platform through joining probe table.

        $loadQuery = <<"END_LoadAllExperimentsQuery";
SELECT
    experiment.eid,
    COALESCE(study.pid, probe.pid) AS my_pid,
    experiment.sample1,
    experiment.sample2,
    COUNT(1),
    ExperimentDescription,
    AdditionalInformation,
    IF(study.stid IS NULL, 'Unknown Study', study.description) AS description,
    IF(
        study.pid IS NULL,
        IF(probe.pid IS NULL, 'Unknown Platform', probe_platform.pname),
        study_platform.pname
    ) AS 'Platform',
    IFNULL(study.stid, '')
FROM experiment
LEFT JOIN StudyExperiment ON experiment.eid = StudyExperiment.eid
LEFT JOIN study ON study.stid = StudyExperiment.stid
LEFT JOIN platform study_platform ON study_platform.pid = study.pid
LEFT JOIN microarray ON microarray.eid = experiment.eid
LEFT JOIN probe ON probe.rid = microarray.rid
LEFT JOIN platform probe_platform ON probe_platform.pid = probe.pid
GROUP BY experiment.eid, study.stid
$having_platform_clause
ORDER BY experiment.eid ASC

END_LoadAllExperimentsQuery
    }
    elsif ( $self->{_stid} eq '' ) {

        # unassigned study -- from a specific platform?
        my $where_platform_clause = '';
        if ( defined $self->{_pid} and not $self->{_pid} eq 'all' ) {
            $where_platform_clause = 'AND platform.pid=?';
            push @exec_param, $self->{_pid};
        }

        # load experiments that are not assigned to any study and may or may not
        # have probes in a specific platform
        $loadQuery = <<"END_LoadUnassignedQuery";
SELECT
    experiment.eid,
    platform.pid,
    experiment.sample1,
    experiment.sample2,
    COUNT(1),
    ExperimentDescription,
    AdditionalInformation,
    'Unknown Study' AS description,
    IF(platform.pid IS NULL, 'Unknown Platform', platform.pname) AS pname,
    '' AS stid
FROM experiment
LEFT JOIN microarray ON microarray.eid = experiment.eid
LEFT JOIN probe ON probe.rid = microarray.rid
LEFT JOIN platform ON platform.pid = probe.pid
WHERE experiment.eid NOT IN (SELECT DISTINCT eid FROM StudyExperiment)
$where_platform_clause
GROUP BY experiment.eid
ORDER BY experiment.eid ASC

END_LoadUnassignedQuery
    }
    else {

        # load experiments when a study is known
        push @exec_param, $self->{_stid};

        # assigned studies -- no need to check platform
        $loadQuery = <<"END_LoadQuery";
SELECT
    experiment.eid,
    study.pid,
    experiment.sample1,
    experiment.sample2,
    (SELECT COUNT(*) FROM microarray WHERE eid=experiment.eid) AS 'Probe Count',
    ExperimentDescription,
    AdditionalInformation,
    IF(study.stid IS NULL, 'Unknown Study', study.description) AS description,
    IF(platform.pid IS NULL, 'Unknown Platform', platform.pname) AS pname,
    IFNULL(study.stid, '')
FROM experiment
INNER JOIN StudyExperiment ON experiment.eid = StudyExperiment.eid
INNER JOIN study ON study.stid = StudyExperiment.stid
LEFT JOIN platform ON platform.pid = study.pid
WHERE study.stid=?
GROUP BY experiment.eid
ORDER BY experiment.eid ASC

END_LoadQuery
    }

    my $sth = $dbh->prepare($loadQuery);
    my $rc  = $sth->execute(@exec_param);
    $self->{_FieldNames} = $sth->{NAME};
    $self->{_Data}       = $sth->fetchall_arrayref;
    $sth->finish;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  getHTML
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Draw the HTML for the experiment table
#       THROWS:  no exceptions
#     COMMENTS:  n/a
#     SEE ALSO:  n/a
#===============================================================================
sub getHTML {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form with the Platform/Study dropdown
    #---------------------------------------------------------------------------
    #Load the study dropdown to choose which experiments to load into table.
    my @return_array = (
        $q->h2('Manage Experiments'),
        $q->start_form(
            -method => 'GET',
            -action => $q->url( -absolute => 1 ),
            -enctype => 'application/x-www-form-urlencoded'
        ),
        $q->dl(
            $q->dt('Platform:'),
            $q->dd(
                $q->popup_menu(
                    -name => 'pid',
                    -id   => 'pid',
                    -title => 'Choose a microarray platform'
                )
            ),
            $q->dt('Study:'),
            $q->dd(
                $q->popup_menu(
                    -name => 'stid',
                    -id   => 'stid',
                    -title => 'Choose a study'
                )
            ),
            $q->dt('&nbsp;'),
            $q->dd(
                $q->hidden(
                    -name  => 'a',
                    -value => 'manageExperiments'
                ),
                $q->submit(
                    -name  => 'b',
                    -class => 'button black bigrounded',
                    -value => 'Load',
                    -title => 'Show matching experiments'
                ),
            )
        ),
        $q->end_form
    );

    #---------------------------------------------------------------------------
    #  Main results table
    #---------------------------------------------------------------------------
    if ( defined( $self->{_Data} ) ) {

        #If we have selected and loaded an experiment, load the table.
        push @return_array,
          (
            $q->h3( { -id => 'caption' }, '' ),
            $q->div(
                $q->a( { -id => 'StudyTable_astext' }, 'View as plain text' )
            ),
            $q->div( { -id => 'StudyTable' }, '' )
          );
    }

    return @return_array;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  printJSRecords
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:
#                eid, pid, sample1, sample2, count(1), ExperimentDescription,
#                AdditionalInfo, Study Description, platform name, stid ->
#                sample1, sample2, count(1), eid, eid,ExperimentDescription,
#                AdditionalInfo, Study Description, platform name, stid, pid.
#
#     SEE ALSO:  n/a
#===============================================================================
sub printJSRecords {
    my $self = shift;

    my $data = $self->{_Data};
    my @columns = ( 2, 3, 4, 0, 0, 5, 6, 7, 8, 9, 1 );

    my @tmp;
    foreach my $row (@$data) {
        push @tmp, [ @$row[@columns] ];
    }
    return \@tmp;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  printJSHeaders
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub printJSHeaders {
    my $self = shift;
    return $self->{_FieldNames};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  deleteExperiment
#   PARAMETERS:  $self              - reference to current object instance
#                id        => $eid  - experiment id
#                deleteFrom => $stid - study to delete experiment from
#      RETURNS:  ????
#  DESCRIPTION:  Either delete experiment data completely from database (when
#  no study id is given) or simply remove it from the specified study (unassign)
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub deleteExperiment {
    my ( $self, %param ) = @_;

    my $dbh = $self->{_dbh};

    my ( $eid, $stid ) = @param{qw{id deleteFrom}};

    if ( defined($eid) and $eid ne '' ) {
        if ( defined($stid) and $stid ne '' ) {

            # Unassign: simply remove from the study
            my $sth = $dbh->prepare(<<"END_UnassignQuery");
DELETE FROM StudyExperiment
WHERE stid = ? AND eid = ?
END_UnassignQuery
            my $rc = $sth->execute( $stid, $eid );
            $sth->finish;
        }
        else {
            my @deleteStatements = map { $dbh->prepare($_) } (
                'DELETE FROM microarray WHERE eid = ?',
                'DELETE FROM StudyExperiment WHERE eid = ?',
                'DELETE FROM experiment WHERE eid = ?'
            );

            # Delete: completely delete
            foreach (@deleteStatements) {
                $_->execute($eid);
            }
            foreach (@deleteStatements) {
                $_->finish;
            }
        }
    }

    return 1;
}

1;

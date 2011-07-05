
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

use SGX::DropDownData;
use Data::Dumper;
use Switch;
use JSON::XS;
use URI::Escape;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  new
#   PARAMETERS:  dbh => $dbh        - DBI database handle
#                cgi => $q          - reference to CGI.pm object instance
#                user_session => $s - SGX::User instance reference
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ($class, %param) = @_;

    my ($dbh, $q, $s, $js_src_yui, $js_src_code) = 
        @param{qw{dbh cgi user_session js_src_yui js_src_code}};

    # :TODO:07/01/2011 04:02:51:es: To find out the number of probes for each
    # experiment, run separate queries for better performance
    my $self = {
        _dbh    => $dbh,
        _cgi    => $q,
        _UserSession => $s,
        _js_src_yui => $js_src_yui,
        _js_src_code => $js_src_code,

        # load experiments when a study is known
        _LoadQuery => <<"END_LoadQuery",
SELECT
    experiment.eid,
    study.pid,
    experiment.sample1,
    experiment.sample2,
    COUNT(1),
    ExperimentDescription,
    AdditionalInformation,
    IF(study.stid IS NULL, 'Unknown Study', study.description) AS description,
    IF(platform.pid IS NULL, 'Unknown Platform', platform.pname) AS pname,
    IFNULL(study.stid, '')
FROM experiment
INNER JOIN StudyExperiment ON experiment.eid = StudyExperiment.eid
INNER JOIN study ON study.stid = StudyExperiment.stid
LEFT JOIN platform ON platform.pid = study.pid
LEFT JOIN microarray ON microarray.eid = experiment.eid
WHERE study.stid=?
GROUP BY experiment.eid
ORDER BY experiment.eid ASC

END_LoadQuery

        # load experiments that are not assigned to any study and may or may not
        # have probes in a specific platform
        _LoadUnassignedQuery => <<"END_LoadUnassignedQuery",
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
WHERE experiment.eid NOT IN (SELECT DISTINCT eid FROM StudyExperiment) %s
GROUP BY experiment.eid
ORDER BY experiment.eid ASC

END_LoadUnassignedQuery

# Unassigned experiments will not be linked to a specific study, and the only
# way to find out what platform they are at is through joining probe table.
# We resolve the question of what platform an experiment is on the following
# way: if the experiment is linked to a study, use the platform name/id from the
# study, otherwise determine the platform through joining probe table.
        _LoadAllExperimentsQuery => <<"END_LoadAllExperimentsQuery",
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
%s
ORDER BY experiment.eid ASC

END_LoadAllExperimentsQuery

        _LoadSingleQuery => <<"END_LoadSingleQuery",
SELECT eid,
    sample1,
    sample2,
    ExperimentDescription,
    AdditionalInformation
FROM experiment
NATURAL JOIN StudyExperiment
NATURAL JOIN study
WHERE experiment.eid = {0}

END_LoadSingleQuery

        _UpdateQuery => <<"END_UpdateQuery",
UPDATE experiment
SET ExperimentDescription = '{0}',
    AdditionalInformation = '{1}',
    sample1 = '{2}',
    sample2 = '{3}'
WHERE eid = {4}
END_UpdateQuery

        _DeleteQueries => [
            'DELETE FROM microarray WHERE eid = ?',
            'DELETE FROM StudyExperiment WHERE eid = ?',
            'DELETE FROM experiment WHERE eid = ?'
        ],

        _UnassignQuery => <<"END_UnassignQuery",
DELETE FROM StudyExperiment
WHERE stid = ? AND eid = ?
END_UnassignQuery

        _StudyQuery => <<"END_StudyQuery",
SELECT 'all', 'All Studies'
UNION SELECT '1010', 'Unassigned Study'
UNION SELECT stid, description
FROM study ORDER BY 1
END_StudyQuery

        _StudyPlatformQuery => <<"END_StudyPlatformQuery",
SELECT pid,stid,description
FROM study ORDER BY 1, 2
END_StudyPlatformQuery

        _PlatformQuery => <<"END_PlatformQuery",
SELECT 'all', 'All Platforms'
UNION SELECT pid, CONCAT(pname, ' \\\\ ', species)
FROM platform ORDER BY 1
END_PlatformQuery

        _FieldNames => undef,
        _Data       => undef,
        _stid       => undef,
        _pid        => undef,
        _eid        => undef,
        _studyList  => {}
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

    switch ($action) {
        case 'delete' {

            # redirect if we know where to...
            if ( defined $q->url_param('destination') ) {
                print "<br />Record removed - Redirecting...<br />";

                my $destination =
                  $q->url( -base => 1 )
                  . uri_unescape( $q->url_param('destination') );
                print
"<script type=\"text/javascript\">window.location = \"$destination\"</script>";
            }
        }
        else {

            # default action: show experiments form
            print $self->showExperiments();
        }
    }
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
    my ( $self ) = @_;

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
            if (!$s->is_authorized('user')) { return; }
            $self->deleteExperiment(
                id         => $q->param('id'),
                deleteFrom => $q->param('deleteFrom')
            );
        }
        case 'update' {
            # This is a *very generic* method handling AJAX request --
            # basically update a key-value pair in a specified row in the table
            # # :TODO:07/04/2011 16:48:45:es: Abstract out this method into a
            # base class for SGX modules.
            #
            my %valid_fields;
            @valid_fields{qw{sample1 sample2 ExperimentDescription AdditionalInformation}} = ();

            if (!$s->is_authorized('user')) {
                # Send 401 Unauthorized header
                print $q->header(-status=>401);
                exit(0);
            }
            my $field = $q->param('field');
            if (not defined($field) or not exists($valid_fields{$field})) {
                # Send 400 Bad Request header
                print $q->header(-status=>400);
                exit(0);
            }
            # after field name has been checked against %valid_fields hash, it
            # is safe to fill it in directly:
            my $query = "update experiment set $field=? where eid=?";
            # Note that when $q->param('value') is undefined, DBI should fill in
            # NULL into the corresponding placeholder.
            my $rc = eval { $dbh->do( $query, undef,
                $q->param('value'),
                $q->param('id')
            )} or 0;

            if ($rc) {
                # Some rows were updated:
                # Send 200 OK header
                print $q->header(-status=>200);
                exit(1);
            } else {
                if (!$@) {
                    # Normal condition -- no rows updated:
                    # Send 404 Not Found header
                    print $q->header(-status=>404);
                    exit(0);
                } else {
                    # Error condition -- no rows updated:
                    # Send 400 Bad Request header
                    print $q->header(-status=>400);
                    $@->throw();
                }
            }
        }
        case 'Load' {
            if (!$s->is_authorized('user')) { return; }
            #$self->loadFromForm();
            $self->{_stid} = $q->param('study');
            $self->{_pid}  = $q->param('platform');
            $self->loadAllExperimentsFromStudy();
            $self->loadStudyData();
            $self->loadPlatformData();
            push @$js_src_code, { -code => $self->showExperiments_js() };
            push @$js_src_code, { -src  => 'ManageExperiments.js' };
        }
        else {
            if (!$s->is_authorized('user')) { return; }
            #$self->loadAllExperimentsFromStudy();
            $self->loadStudyData();
            $self->loadPlatformData();

            push @$js_src_code, { -code => $self->showExperiments_js() };
            push @$js_src_code, { -src => 'ManageExperiments.js' };
        }
    }
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
    my $q = $self->{_cgi};

    my $return_text = sprintf(
        "var studies = %s;\nvar curr_study = '%s';\n",
        $self->getJavaScriptRecordsForFilterDropDowns(),
        $self->{_stid}
    );

    #If we have selected and loaded an experiment, load the table.
    if ( defined( $self->{_Data} ) ) {
        $return_text .= "var show_table = true;\n";

        $return_text .= sprintf(
            "var JSStudyList = %s;\n",
            encode_json({
                caption => 'Showing Experiments from: ',
                records => $self->printJSRecords(),
                headers => $self->printJSHeaders()
            })
        );

        $return_text .= $self->printTableInformation()

        #Now we need to re-select the current StudyID, if we have one.
        #if ( defined( $self->{_stid} ) and $self->{_stid} ne '' ) {
        #    print "selectStudy(document.getElementById(\"study\"),\""
        #      . $self->{_stid} . "\");\n";
        #}
    } else {
        $return_text .= "var show_table = false;\n";
    }
    return $return_text;
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
    my $loadQuery;
    my @exec_param;
    if ( not defined( $self->{_stid} ) or $self->{_stid} eq 'all' ) {

        # all studies -- from a specific platform?
        my $having_platform_clause = '';
        if ( defined $self->{_pid} and not $self->{_pid} eq 'all' ) {
            $having_platform_clause = 'HAVING my_pid=?';
            push @exec_param, $self->{_pid};
        }
        $loadQuery =
          sprintf( $self->{_LoadAllExperimentsQuery}, $having_platform_clause );
    }
    elsif ( $self->{_stid} eq '' ) {

        # unassigned study -- from a specific platform?
        my $where_platform_clause = '';
        if ( defined $self->{_pid} and not $self->{_pid} eq 'all' ) {
            $where_platform_clause = 'AND platform.pid=?';
            push @exec_param, $self->{_pid};
        }
        $loadQuery =
          sprintf( $self->{_LoadUnassignedQuery}, $where_platform_clause );
    }
    else {

        # assigned studies -- no need to check platform
        $loadQuery = $self->{_LoadQuery};
        push @exec_param, $self->{_stid};
    }

    my $sth = $self->{_dbh}->prepare($loadQuery)
      or croak $self->{_dbh}->errstr;
    my $rc = $sth->execute(@exec_param)
      or croak $self->{_dbh}->errstr;

    $self->{_FieldNames} = $sth->{NAME};
    $self->{_Data}       = $sth->fetchall_arrayref;
    $sth->finish;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  loadStudyData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loads information into the object that is used to create the study dropdown.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadStudyData {
    my $self = shift;

    my $studyDropDown =
      SGX::DropDownData->new( $self->{_dbh}, $self->{_StudyQuery} );

    $self->{_studyList} = $studyDropDown->loadDropDownValues();

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  loadPlatformData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loads information into the object that is used to create the study dropdown.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadPlatformData {
    my $self = shift;

    my $platformDropDown =
      SGX::DropDownData->new( $self->{_dbh}, $self->{_PlatformQuery} );

    $self->{_platformList} = $platformDropDown->loadDropDownValues();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  showExperiments
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Draw the HTML for the experiment table
#       THROWS:  no exceptions
#     COMMENTS:  n/a
#     SEE ALSO:  n/a
#===============================================================================
sub showExperiments {
    my $self = shift;
    my $q    = $self->{_cgi};

    #Load the study dropdown to choose which experiments to load into table.
    my @return_array = (
        $q->h2('Manage Experiments'),
        $q->start_form(
            -method => 'GET',
            -action => $q->url( -absolute => 1 )
              . '?a=manageExperiments&b=Load',
            -enctype => 'application/x-www-form-urlencoded',
            -onsubmit => 'return validate_fields(this, [\'study\']);'
        ),
        $q->dl(
            $q->dt('Platform:'),
            $q->dd(
                $q->popup_menu(
                    -name    => 'platform',
                    -id      => 'platform',
                    -values  => [ keys %{ $self->{_platformList} } ],
                    -labels  => $self->{_platformList}
                )
            ),
            $q->dt('Study:'),
            $q->dd(
                $q->popup_menu(
                    -name    => 'study',
                    -id      => 'study',
                    -values  => [],
                    -labels  => {}
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
                    -class => 'css3button',
                    -value => 'Load'
                ),
            )
        ),
        $q->end_form
    );

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
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub printJSRecords {
    my $self = shift;

    my @tempRecordList;
    foreach ( @{ $self->{_Data} } ) {

        # Input order: eid, pid, sample1, sample2, count(1),
        # ExperimentDescription, AdditionalInfo, Study Description, platform
        # name, stid

        # Transform order: sample1, sample2, count(1), eid, eid,
        # ExperimentDescription, AdditionalInfo, Study Description, platform
        # name, stid, pid

        push @tempRecordList,
          [
            $_->[2], $_->[3], $_->[4], $_->[0], $_->[0], $_->[5],
            $_->[6], $_->[7], $_->[8], $_->[9], $_->[1]
          ];
    }
    return \@tempRecordList;
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
#       METHOD:  printTableInformation
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub printTableInformation {
    my $self = shift;

    my @names = @{ $self->{_FieldNames} };
    my $q     = $self->{_cgi};

    # set 'destination' URL parameter -- encoded URL to
    # get back to the page we were at
    my $destination =
      ( defined $q->url_param('destination') )
      ? $q->url_param('destination')
      : uri_escape( $q->url( -absolute => 1, -query => 1 ) );

    my $deleteURL =
      $q->url( absolute => 1 ) . '?a=manageExperiments'    # top-level action
      . '&b=delete'                    # second-level action
      . "&destination=$destination"    # current URI (encoded)
      . '&id=';    # resource id on which second-level action will be performed

    my $ret = sprintf(<<"END_printTableInformation",
var url_prefix = "%s";
var deleteURL = "%s";

END_printTableInformation
        $q->url( absolute => 1 ),
        $deleteURL);

    return $ret;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  getJavaScriptRecordsForFilterDropDowns
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJavaScriptRecordsForFilterDropDowns {
    my $self = shift;

    my $tempRecords = $self->{_dbh}->prepare( $self->{_StudyPlatformQuery} )
      or croak $self->{_dbh}->errstr;
    my $tempRecordCount = $tempRecords->execute
      or croak $self->{_dbh}->errstr;

    my %out;
    while ( my @row = $tempRecords->fetchrow_array ) {

        # Study ID => [Study Description, PID]
        $out{ $row[1] } = [ $row[2], $row[0] ];
    }
    $tempRecords->finish;

    return encode_json( \%out );
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

    my ( $eid, $stid ) = @param{qw{id deleteFrom}};

    if ( defined($eid) and $eid ne '' ) {
        if ( defined($stid) and $stid ne '' ) {

            # Unassign: simply remove from the study
            $self->{_dbh}->do( $self->{_UnassignQuery}, undef, $stid, $eid );
        }
        else {

            # Delete: completely delete
            foreach ( @{ $self->{_DeleteQueries} } ) {
                $self->{_dbh}->do( $_, undef, $eid );
            }
        }
    }

    return 1;
}

1;

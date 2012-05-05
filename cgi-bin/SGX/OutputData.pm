package SGX::OutputData;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

use SGX::Util qw/car cdr bind_csv_handle/;
use JSON qw/encode_json/;
require SGX::Model::PlatformStudyExperiment;
use SGX::Abstract::Exception ();
require SGX::DBHelper;

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    my $dbh  = $self->{_dbh};
    my $s    = $self->{_UserSession};
    $self->SUPER::init();

    my $pse = SGX::Model::PlatformStudyExperiment->new( dbh => $dbh );
    my $curr_proj = $s->{session_cookie}->{curr_proj};
    if ( defined($curr_proj) && $curr_proj =~ m/^\d+$/ ) {

        # limit platforms and studies shown to current project
        $pse->{_Platform}->{table} = <<"Platfform_sql";
platform 
    INNER JOIN study USING(pid)
    INNER JOIN ProjectStudy USING(stid)
    LEFT JOIN species USING(sid)
    WHERE prid=?
Platfform_sql
        push @{ $pse->{_Platform}->{param} }, ($curr_proj);
        $pse->{_PlatformStudy}->{table} = <<"PlatfformStudy_sql";
study
    INNER JOIN ProjectStudy USING(stid)
    WHERE prid=?
PlatfformStudy_sql
        push @{ $pse->{_PlatformStudy}->{param} }, ($curr_proj);
    }

    $self->set_attributes(
        _title            => 'Output Data',
        _permission_level => 'readonly',
        _dbHelper         => SGX::DBHelper->new( delegate => $self ),

        # other
        _PlatformStudyExperiment => $pse,
        _stid                    => '',
        _pid                     => '',
    );

    $self->register_actions(
        Load => { head => 'Load_head', body => 'Load_body' } );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  Load_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub Load_head {
    my $self = shift;

    if ( !$self->initOutputData() ) {
        $self->set_action('');
        $self->default_head();
        return 1;
    }
    $self->loadReportData();

    my $format = $self->{_format};
    if ( $format eq 'html' ) {
        my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};
        push @{ $self->{_css_src_yui} },
          (
            'paginator/assets/skins/sam/paginator.css',
            'datatable/assets/skins/sam/datatable.css'
          );
        push @$js_src_yui,
          (
            'yahoo-dom-event/yahoo-dom-event.js',
            'element/element-min.js',
            'datasource/datasource-min.js',
            'paginator/paginator-min.js',
            'datatable/datatable-min.js'
          );
        push @$js_src_code, { -code => $self->runReport_js() };
        return 1;
    }
    elsif ( $format eq 'csv' ) {
        my ( $q, $s ) = @$self{qw/_cgi _UserSession/};
        $s->commit;
        print $q->header(
            -type       => 'text/csv',
            -attachment => 'output.csv',
            -cookie     => $s->cookie_array()
        );
        $self->{_dbHelper}->getSessionOverrideCGI();
        $self->displayDataCSV();
        exit;
    }
    else {
        SGX::Exception::User->throw(
            error => "Unrecognized parameter value format=$format" );
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  displayDataCSV
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub displayDataCSV {

    my $self = shift;

    # Report Header
    my $print = bind_csv_handle( \*STDOUT );
    $print->( [ 'Output Data',     scalar localtime() ] );
    $print->( [ 'Generated By',    $self->{_UserFullName} ] );
    $print->( [ 'Working Project', $self->{_WorkingProjectName} ] );
    $print->();

    # Print CSV output and exit
    $print->( [ @{ $self->{_ExpNames} }, cdr( @{ $self->{_DataNames} } ) ] );

    my $exp_info = $self->{_ExpRecords};
    $print->( [ @{ $exp_info->{ ( $_->[0] ) } }, cdr(@$_) ] )
      for @{ $self->{_DataRecords} };
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
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
    my ( $s, $js_src_yui, $js_src_code ) =
      @$self{qw{_UserSession _js_src_yui _js_src_code}};

    push @$js_src_yui, 'yahoo-dom-event/yahoo-dom-event.js';

    my $curr_proj = $s->{session_cookie}->{curr_proj};
    my @pse_extra_studies =
        ( defined($curr_proj) && $curr_proj =~ m/^\d+$/ )
      ? ( show_unassigned_experiments => 0 )
      : (
        extra_studies => {
            'all' => { description => '@All Studies' },
            ''    => { description => '@Unassigned Experiments' }
        }
      );
    $self->{_PlatformStudyExperiment}->init(
        platforms       => 1,
        studies         => 1,
        experiments     => 1,
        extra_platforms => { 'all' => { pname => '@All Platforms' } },
        @pse_extra_studies
    );
    push @$js_src_code, { -src  => 'PlatformStudyExperiment.js' };
    push @$js_src_code, { -code => $self->getDropDownJS() };
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::OutputData
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub initOutputData {
    my $self = shift;
    my $q    = $self->{_cgi};

    # optional
    $self->{_pid}    = car $q->param('pid');
    $self->{_stid}   = car $q->param('stid');
    $self->{_format} = ( car $q->param('format') ) || 'html';

    # required
    my @eids = $q->param('eid');
    $self->{_eidList} = \@eids;
    my $eid_count = scalar(@eids);
    if ( $eid_count < 1 ) {
        $self->add_message( { -class => 'error' },
            'You did not specify any experiments to output' );
        return;
    }
    return $eid_count;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::OutputData
#       METHOD:  loadReportData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Run the main query to return the result table
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadReportData {
    my $self        = shift;
    my $dbh         = $self->{_dbh};
    my $experiments = $self->{_eidList};

    #---------------------------------------------------------------------------
    #  get infor pertaining experiments
    #---------------------------------------------------------------------------
    my $query_exp = sprintf(
        <<"END_ExperimentQuery",
SELECT
    eid AS 'Exp. ID',
    ExperimentDescription AS 'Experiment Description',
    CONCAT(sample2, ' / ', sample1) AS 'Sample 2 / Sample 1'
FROM 
    experiment
WHERE eid IN (%s)    
END_ExperimentQuery
        ( @$experiments ? join( ',', map { '?' } @$experiments ) : 'NULL' )
    );
    my $sth_exp = $dbh->prepare($query_exp);
    $sth_exp->execute(@$experiments);
    $self->{_ExpNames} = $sth_exp->{NAME};
    $self->{_ExpRecords} =
      +{ map { $_->[0] => $_ } @{ $sth_exp->fetchall_arrayref() } };
    $sth_exp->finish;

    #---------------------------------------------------------------------------
    #  get data itself
    #---------------------------------------------------------------------------
    # for CSV reports, we include additional fields
    my $gene_fields  = '';
    my $gene_join    = '';
    my $probe_fields = '';
    my $probe_join   = '';
    if ( $self->{_format} eq 'csv' ) {

        # extra info for genes
        $gene_fields = <<"END_EXTRA";
GROUP_CONCAT(DISTINCT concat(gene.gname, if(isnull(gene.gdesc), '', concat(', ', gene.gdesc))) separator '; ') AS 'Gene Name/Desc.',
GROUP_CONCAT(DISTINCT CONCAT(go_term.go_name, ' (GO:', go_term.go_acc, ')' ) ORDER BY go_term.go_acc SEPARATOR '; ') AS 'GO terms',
END_EXTRA
        $gene_join =
          'LEFT JOIN GeneGO USING(gid) LEFT JOIN go_term USING(go_acc)';

        # extra info for probes
        $probe_fields = <<"END_EXTRALOCUS";
probe.probe_sequence AS 'Probe Sequence',
probe.probe_comment  AS 'Probe Note',
GROUP_CONCAT(DISTINCT format_locus(locus.chr, locus.zinterval) separator ' ') AS 'Mapping Location(s)',
END_EXTRALOCUS
        $probe_join = 'LEFT JOIN locus USING(rid)';
    }

    my $query_data = sprintf(
        <<"END_ReportQuery",
SELECT
    microarray.eid AS 'Exp. ID',
    probe.reporter        AS 'Probe ID',
    $probe_fields
    GROUP_CONCAT(DISTINCT if(gene.gtype=0, gene.gsymbol, NULL) separator ', ') AS 'Accession No.',
    GROUP_CONCAT(DISTINCT if(gene.gtype=1, gene.gsymbol, NULL) separator ', ') AS 'Gene Symbol',
    $gene_fields
    microarray.ratio      AS 'Ratio',
    microarray.foldchange AS 'Fold Change',
    microarray.intensity1 AS 'Intensity 1',
    microarray.intensity2 AS 'Intensity 2',
    microarray.pvalue1    AS 'P-1',
    microarray.pvalue2    AS 'P-2',
    microarray.pvalue3    AS 'P-3',
    microarray.pvalue4    AS 'P-4'
FROM (
    SELECT eid FROM experiment WHERE eid IN (%s)
) AS d1
INNER JOIN microarray USING(eid)
LEFT JOIN probe USING(rid)
LEFT JOIN ProbeGene USING(rid)
LEFT JOIN gene USING(gid)
$probe_join
$gene_join
GROUP BY microarray.eid, microarray.rid
ORDER BY microarray.eid, probe.reporter
END_ReportQuery
        ( @$experiments ? join( ',', map { '?' } @$experiments ) : 'NULL' )
    );
    my $sth_data = $dbh->prepare($query_data);
    $sth_data->execute(@$experiments);
    $self->{_DataNames}   = $sth_data->{NAME};
    $self->{_DataRecords} = $sth_data->fetchall_arrayref;
    $sth_data->finish;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Draw the javascript and HTML for the experiment table
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->h2('Output Data'), $q->h3('Choose one or more experiments:'),

      # :TODO:08/03/2011 15:17:36:es: also pull out the study from the form and
      # determine which study we are using by reverse lookup from experiments
      $q->dl(
        $q->dt( $q->label( { -for => 'pid' }, 'Platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 'pid',
                -id    => 'pid',
                -title => 'Choose microarray platform'
            )
        ),
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 'stid',
                -id    => 'stid',
                -title => 'Choose study'
            )
        ),
      ),

      # now start the form element
      $q->start_form(
        -accept_charset => 'ISO-8859-1',
        -method         => 'GET',
        -enctype        => 'application/x-www-form-urlencoded',
        -action         => $q->url( -absolute => 1 ) . '?a=outputData'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'eid' }, 'Experiment(s):' ) ),
        $q->dd(
            $q->popup_menu(
                -name => 'eid',
                -id   => 'eid',
                -title =>
'You can select multiple experiments here by holding down Control or Command key before clicking.',
                -multiple => 'multiple',
                -size     => 7
            )
        ),
        $q->dt('Output Format:'),
        $q->dd(
            $q->radio_group(
                -name    => 'format',
                -default => 'html',
                -values  => [ 'html', 'csv' ],
                -labels  => { 'html' => 'HTML', 'csv' => 'CSV' },
                -title   => 'Output format'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden(
                -name  => 'a',
                -value => 'outputData'
            ),
            $q->hidden( -name => 'b', -value => 'Load' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Output File',
                -title => 'Get data for selected experiments'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::OutputData
#       METHOD:  getDropDownJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Return Javascript code including the JSON model necessary to
#                populate Platform->Study->Experiment select controls.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getDropDownJS {
    my $self = shift;

    my $js = $self->{_js_emitter};
    return $js->let(
        [
            PlatfStudyExp =>
              $self->{_PlatformStudyExperiment}->get_ByPlatform(),
            currentSelection => [
                'platform' => {
                    element  => undef,
                    selected => (
                          ( defined $self->{_pid} )
                        ? { $self->{_pid} => undef }
                        : {}
                    ),
                    elementId    => 'pid',
                    updateViewOn => [ sub { 'window' }, 'load' ],
                    updateMethod => sub { 'populatePlatform' }
                },
                'study' => {
                    element  => undef,
                    selected => (
                          ( defined $self->{_stid} )
                        ? { $self->{_stid} => undef }
                        : {}
                    ),
                    elementId => 'stid',
                    updateViewOn =>
                      [ sub { 'window' }, 'load', 'pid', 'change' ],
                    updateMethod => sub { 'populatePlatformStudy' }
                },
                'experiment' => {
                    element => undef,
                    selected =>
                      +{ map { $_ => undef } @{ $self->{_eidList} || [] } },
                    elementId    => 'eid',
                    updateViewOn => [
                        sub { 'window' }, 'load',
                        'pid',  'change',
                        'stid', 'change'
                    ],
                    updateMethod => sub { 'populateStudyExperiment' }
                }
            ]
        ],
        declare => 1
    ) . $js->apply( 'setupPPDropdowns', [ sub { 'currentSelection' } ] );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::OutputData
#       METHOD:  Load_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Return basic HTML frame for YUI DataTable control
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub Load_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->h3( { -id => 'caption' },
        sprintf( "Found %d records", scalar( @{ $self->{_DataRecords} } ) ) ),
      $q->div( $q->a( { -id => 'OutPut_astext' }, 'View as plain text' ) ),
      $q->div( { -id => 'OutputTable' }, '' );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::OutputData
#       METHOD:  runReport_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Return Javascript to populate YUI DataTable control
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub runReport_js {
    my $self = shift;

    my $records      = $self->{_DataRecords};
    my $headers      = $self->{_DataNames};
    my $OutputReport = encode_json(
        {
            caption => 'Showing all Experiments',
            records => $records,
            headers => $headers
        }
    );
    my @columns = 0 .. $#$headers;

    my $myColumnDefs = encode_json(
        [
            map {
                +{
                    key        => "$_",
                    sortable   => JSON::true,
                    resizeable => JSON::true,
                    label      => $headers->[$_]
                  }
              } @columns
        ]
    );

    my $responseSchemaFields = encode_json( [ map { "$_" } @columns ] );

    return <<"END_JSOuputList";
var OutputReport = $OutputReport;
YAHOO.util.Event.addListener("OutPut_astext", "click", export_table, OutputReport, true);
YAHOO.util.Event.addListener(window, 'load', function() {
    var myColumnDefs = $myColumnDefs;
    var myDataSource = new YAHOO.util.DataSource(OutputReport.records);
    myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSource.responseSchema = {fields: $responseSchemaFields};
    var myData_config = {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
    var myDataTable = new YAHOO.widget.DataTable(
                        "OutputTable", 
                        myColumnDefs, 
                        myDataSource, 
                        myData_config
    );
});

END_JSOuputList

}

1;

__END__


=head1 NAME

SGX::OutputData

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for dumping data.

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut



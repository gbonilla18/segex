package SGX::OutputData;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

use JSON qw/encode_json/;
require SGX::Model::PlatformStudyExperiment;

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
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

    my $dbh = $self->{_dbh};

    $self->set_attributes(
        _title => 'Output Data',

        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $dbh ),

        _Data            => '',
        _RecordsReturned => undef,
        _FieldNames      => '',
        _stid            => '',
        _pid             => '',
        _eidList         => []
    );

    $self->register_actions(
        Load => { head => 'Load_head', body => 'Load_body' } );

    bless $self, $class;
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
    my ( $s, $js_src_yui, $js_src_code ) =
      @$self{qw{_UserSession _js_src_yui _js_src_code}};
    push @{ $self->{_css_src_yui} },
      (
        'paginator/assets/skins/sam/paginator.css',
        'datatable/assets/skins/sam/datatable.css'
      );
    push @$js_src_yui,
      (
        'yahoo-dom-event/yahoo-dom-event.js', 'element/element-min.js',
        'datasource/datasource-min.js',       'paginator/paginator-min.js',
        'datatable/datatable-min.js'
      );
    $self->init();
    $self->loadReportData();
    push @$js_src_code, { -code => $self->runReport_js() };
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

    $self->{_PlatformStudyExperiment}->init(
        platforms       => 1,
        studies         => 1,
        experiments     => 1,
        extra_platforms => { 'all' => { name => '@All Platforms' } },
        extra_studies   => {
            'all' => { name => '@All Studies' },
            ''    => { name => '@Unassigned Experiments' }
        }
    );
    push @$js_src_code, { -src  => 'PlatformStudyExperiment.js' };
    push @$js_src_code, { -code => $self->getDropDownJS() };
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
sub init {
    my $self = shift;
    my $q    = $self->{_cgi};

    # optional
    $self->{_pid}  = $q->param('pid');
    $self->{_stid} = $q->param('stid');

    # required
    $self->{_eidList} = [ $q->param('eid') ];
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
    my $self = shift;

    # cache database handle
    my $dbh = $self->{_dbh};

    my $query_text = sprintf(
        <<"END_ReportQuery",
SELECT  
    study.description     AS 'Study',
    CONCAT(
        experiment.sample1, ' / ', 
        experiment.sample2
    )                     AS 'Sample 1 / Sample 2',
    probe.reporter        AS 'Probe ID',
    gene.accnum           AS 'Accession Number',
    gene.seqname          AS 'Gene',
    microarray.ratio      AS 'Ratio',
    microarray.foldchange AS 'Fold Change',
    microarray.pvalue     AS 'P-value',
    microarray.intensity1 AS 'Intensity 1',
    microarray.intensity2 AS 'Intensity 2'
FROM experiment
LEFT JOIN StudyExperiment USING(eid)
LEFT JOIN study USING(stid)
INNER JOIN microarray USING(eid)
LEFT JOIN probe ON probe.rid = microarray.rid
LEFT JOIN annotates ON annotates.rid = probe.rid
LEFT JOIN gene ON gene.gid = annotates.gid
WHERE experiment.eid IN (%s)
GROUP BY experiment.eid, microarray.rid
ORDER BY experiment.eid

END_ReportQuery
        join( ',', map { '?' } @{ $self->{_eidList} } )
    );

    my $sth = $dbh->prepare($query_text);

    $self->{_RecordsReturned} = $sth->execute( @{ $self->{_eidList} } );

    $self->{_FieldNames} = $sth->{NAME};
    $self->{_Data}       = $sth->fetchall_arrayref;

    $sth->finish;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  getJSRecords
#   PARAMETERS:  none; relies on _Data field
#      RETURNS:  ARRAY reference
#  DESCRIPTION:  Returns data structure containing body of the table.
#       THROWS:  no exceptions
#     COMMENTS:  Remaps an array of array references into an array of hash
#                references.
#     SEE ALSO:  n/a
#===============================================================================
sub getJSRecords {
    my $self = shift;

    return [
        map {
            my $i   = 0;
            my $row = $_;
            +{ map { $i++ => $_ } @$row }
          } @{ $self->{_Data} }
    ];
}

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  getJSHeaders
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  returns data structure containing table headers
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJSHeaders {
    my $self = shift;
    return $self->{_FieldNames};
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
                -title => 'Choose a microarray platform'
            )
        ),

      ),
      $q->start_form(
        -method  => 'GET',
        -enctype => 'application/x-www-form-urlencoded',
        -action  => $q->url( -absolute => 1 ) . '?a=outputData'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 'stid',
                -id    => 'stid',
                -title => 'Choose a study'
            )
        ),
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
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden(
                -name  => 'a',
                -value => 'outputData'
            ),
            $q->submit(
                -name  => 'b',
                -id    => 'b',
                -class => 'button black bigrounded',
                -value => 'Load',
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

    my $PlatfStudyExp =
      encode_json( $self->{_PlatformStudyExperiment}->get_ByPlatform() );

    my $currentSelection = encode_json(
        {
            'platform' => {
                element   => undef,
                selected  => +{ $self->{_pid} => undef },
                elementId => 'pid'
            },
            'study' => {
                element   => undef,
                selected  => +{ $self->{_stid} => undef },
                elementId => 'stid'
            },
            'experiment' => {
                element   => undef,
                selected  => +{ map { $_ => undef } @{ $self->{_eidList} } },
                elementId => 'eid'
            }
        }
    );

    return <<"END_ret";
var PlatfStudyExp = $PlatfStudyExp;
var currentSelection = $currentSelection;
YAHOO.util.Event.addListener(window, 'load', function() {
    populatePlatform.apply(currentSelection);
    populatePlatformStudy.apply(currentSelection);
    populateStudyExperiment.apply(currentSelection);
});
YAHOO.util.Event.addListener('pid', 'change', function() {
    populatePlatformStudy.apply(currentSelection);
    populateStudyExperiment.apply(currentSelection);
});
YAHOO.util.Event.addListener('stid', 'change', function() {
    populateStudyExperiment.apply(currentSelection);
});
END_ret
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
        sprintf( "Found %d records", $self->{_RecordsReturned} ) ),
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

    my $headers_ref = getJSHeaders($self);
    my $records     = encode_json( getJSRecords($self) );
    my $headers     = encode_json($headers_ref);

    my @columns = 0 .. ( @$headers_ref - 1 );

    my $myColumnDefs = encode_json(
        [
            map {
                +{
                    key        => "$_",
                    sortable   => JSON::XS::true,
                    resizeable => JSON::XS::true,
                    label      => $headers_ref->[$_]
                  }
              } @columns
        ]
    );

    my $responseSchemaFields = encode_json( [ map { "$_" } @columns ] );

 # :TODO:07/12/2011 10:00:04:es: rewrite export_table() Javascript function such
 # that it assumes that .headers field is in the same format as DataTable column
 # definitions. Then change column definition code everytwhere from being
 # hardcoded into Javascript to being Perl-generated and JSON-encoded.
 #
 # Also conider treating DataSource responseSchema.fields the same way.
 #
    return <<"END_JSOuputList";
var OutputReport = {
    caption: "Showing all Experiments",
    records: $records,
    headers: $headers
};
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



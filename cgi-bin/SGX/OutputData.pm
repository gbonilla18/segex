
=head1 NAME

SGX::OutputData

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for dumping data.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::OutputData;

use strict;
use warnings;
use Data::Dumper;
use Switch;
use JSON::XS;
use SGX::Model::PlatformStudyExperiment;

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
    my ( $class, %param ) = @_;

    my ( $dbh, $q, $s, $js_src_yui, $js_src_code ) =
      @param{qw{dbh cgi user_session js_src_yui js_src_code}};

    my $self = {
        _dbh         => $dbh,
        _cgi         => $q,
        _UserSession => $s,
        _js_src_yui  => $js_src_yui,
        _js_src_code => $js_src_code,

        _ReportQuery => <<"END_ReportQuery",
SELECT  
    CONCAT(
        study.description, ' - ', 
        experiment.sample2, ' / ', 
        experiment.sample1
    ) AS 'Study',
    probe.reporter AS 'Reporter',
    gene.accnum AS 'Accession Number',
    gene.seqname AS 'Gene',
    microarray.ratio AS 'Ratio',
    microarray.foldchange AS 'Fold Change',
    microarray.pvalue AS 'P-value',
    microarray.intensity1 AS 'Intensity 1',
    microarray.intensity2 AS 'Intensity 2'
FROM experiment
LEFT JOIN StudyExperiment USING(eid)
LEFT JOIN Study USING(stid)
INNER JOIN microarray USING(eid)
LEFT JOIN probe ON probe.rid = microarray.rid
LEFT JOIN annotates ON annotates.rid = probe.rid
LEFT JOIN gene ON gene.gid = annotates.gid
WHERE experiment.eid IN (%s)
GROUP BY experiment.eid, microarray.rid
ORDER BY experiment.eid

END_ReportQuery

        _Data            => '',
        _RecordsReturned => undef,
        _FieldNames      => ''
    };

    bless $self, $class;
    return $self;
}

#---------------------------------------------------------------------------
#  Controller methods
#---------------------------------------------------------------------------
#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  dispatch_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
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

    push @$js_src_yui, ('yahoo-dom-event/yahoo-dom-event.js');
    switch ($action) {
        case 'Load' {
            return if not $s->is_authorized('user');
            push @$js_src_yui,
              (
                'yahoo-dom-event/yahoo-dom-event.js',
                'element/element-min.js',
                'datasource/datasource-min.js',
                'paginator/paginator-min.js',
                'datatable/datatable-min.js'
              );
            my @eids = $self->{_cgi}->param('eids');
            $self->{_eidList} = \@eids;
            $self->loadReportData();
            push @$js_src_code, { -code => $self->runReport_js() };
        }
        else {
            return if not $s->is_authorized('user');
            push @$js_src_code, { -src => 'OutputData.js' };
            push @$js_src_code,
              { -code => $self->getJSRecordsForExistingDropDowns() };
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  executes appropriate method for the given action
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch {
    my ($self) = @_;

    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    switch ($action) {
        case 'Load' {
            print $self->LoadHTML();
        }
        else {

            # default action: show form
            print $self->showForm();
        }
    }
    return 1;
}

#---------------------------------------------------------------------------
#  Model methods
#---------------------------------------------------------------------------
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

    my $query_text = sprintf($self->{_ReportQuery},
        join(',', map { '?' } 1..scalar(@{$self->{_eidList}})));

    my $sth = $dbh->prepare( $query_text );

    $self->{_RecordsReturned} = $sth->execute( @{$self->{_eidList}} );

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


#---------------------------------------------------------------------------
#  View methods
#---------------------------------------------------------------------------
#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  showForm
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Draw the javascript and HTML for the experiment table
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub showForm {
    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->h2('Output Data'), $q->h3('Select Items to output'), $q->dl(
        $q->dt( $q->label( { -for => 'platform' }, 'Platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name => 'platform',
                -id   => 'platform'
            )
        ),

      ),
      $q->start_form(
        -method  => 'GET',
        -enctype => 'application/x-www-form-urlencoded',
        -action  => $q->url( -absolute => 1 ) . '?a=outputData'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'study' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name => 'study',
                -id   => 'study'
            )
        ),
        $q->dt( $q->label( { -for => 'eids' }, 'Experiment(s):' ) ),
        $q->dd(
            $q->popup_menu(
                -name     => 'eids',
                -id       => 'eids',
                -multiple => 'multiple'
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
                -class => 'css3button',
                -value => 'Load'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::OutputData
#       METHOD:  getJSRecordsForExistingDropDowns
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Return Javascript code including the JSON model necessary to 
#                populate Platform->Study->Experiment select controls.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJSRecordsForExistingDropDowns {
    my $self = shift;

    my $model_obj =
      SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} );
    my $model = $model_obj->getByPlatformStudyExperiment(
        platform_info   => 1,
        experiment_info => 1
    );

    return sprintf(
        <<"END_ret",
var PlatfStudyExp = %s;
YAHOO.util.Event.addListener(window, 'load', function() {
    populatePlatform();
    populatePlatformStudy();
    populateStudyExperiment();
});
YAHOO.util.Event.addListener('platform', 'change', function() {
    populatePlatformStudy();
    populateStudyExperiment();
});
YAHOO.util.Event.addListener('study', 'change', function() {
    populateStudyExperiment();
});
END_ret
        encode_json($model)
    );
}


#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::OutputData
#       METHOD:  LoadHTML
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Return basic HTML frame for YUI DataTable control
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub LoadHTML {
    my $self = shift;
    my $q = $self->{_cgi};

    return
      $q->h3( { -id => 'caption' }, "Found $self->{_RecordsReturned} records" ),
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

    my $records = encode_json( getJSRecords($self) );
    my $headers = encode_json( getJSHeaders($self) );

    return <<"END_JSOuputList";
var OutputReport = {
    caption: "Showing all Experiments",
    records: $records,
    headers: $headers
};
YAHOO.util.Event.addListener("OutPut_astext", "click", export_table, OutputReport, true);
YAHOO.util.Event.addListener(window, 'load', function() {
    var myColumnDefs = [
        {key:"0", sortable:true, resizeable:true, label:OutputReport.headers[0]},
        {key:"1", sortable:true, resizeable:true, label:OutputReport.headers[1]},
        {key:"2", sortable:true, resizeable:true, label:OutputReport.headers[2]},
        {key:"3", sortable:true, resizeable:true, label:OutputReport.headers[3]},
        {key:"4", sortable:true, resizeable:true, label:OutputReport.headers[4]},
        {key:"5", sortable:true, resizeable:true, label:OutputReport.headers[5]},
        {key:"6", sortable:true, resizeable:true, label:OutputReport.headers[6]},
        {key:"7", sortable:true, resizeable:true, label:OutputReport.headers[7]},
        {key:"8", sortable:true, resizeable:true, label:OutputReport.headers[8]}
    ];

    var myDataSource = new YAHOO.util.DataSource(OutputReport.records);
    myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSource.responseSchema = {fields: ["0","1","2","3","4","5","6","7","8"]};
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

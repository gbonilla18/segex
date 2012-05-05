package SGX::CompareExperiments;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

#use Benchmark;
use JSON qw/encode_json decode_json/;
require SGX::FindProbes;
require SGX::DBHelper;
require SGX::Model::PlatformStudyExperiment;

#use SGX::Abstract::Exception ();
use SGX::Util qw/car/;
use SGX::Config qw/$IMAGES_DIR $YUI_BUILD_ROOT/;
use SGX::Debug;

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Initialize parts tht deal with responding to CGI queries
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    my $dbh  = $self->{_dbh};
    my $q    = $self->{_cgi};
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

    push @{ $pse->{_Platform}->{attr} }, ( 'def_p_cutoff', 'def_f_cutoff' );
    push @{ $pse->{_Experiment}->{attr} }, 'PValFlag';

    # Using FindProbes module
    my $findProbes = SGX::FindProbes->new_lite(
        _dbh         => $self->{_dbh},
        _cgi         => $q,
        _UserSession => $self->{_UserSession}
    );
    $findProbes->set_attributes(
        _dbHelper => SGX::DBHelper->new( delegate => $findProbes ) );

    # usual initialization stuff
    $self->set_attributes(
        _title                   => 'Compare Experiments',
        _permission_level        => 'readonly',
        _PlatformStudyExperiment => $pse,
        _FindProbes              => $findProbes,
        _dbHelper                => SGX::DBHelper->new( delegate => $self )
    );
    $self->register_actions(
        Submit => { head => 'Compare_head', body => 'Compare_body' },
        'Search GO terms' => { body => 'SearchGO_body' }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
#       METHOD:  Compare_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub Compare_head {
    my $self = shift;

    my $q = $self->{_cgi};
    $self->{_chkAllProbes}  = car $q->param('chkAllProbes');
    $self->{_specialFilter} = car $q->param('specialFilter');
    $self->{_user_pse}      = car $q->param('user_pse');
    $self->{_user_pse}      = '{}' if not defined $self->{_user_pse};
    my $pse_json = decode_json( $self->{_user_pse} ) || {};
    $self->{_pid} = $pse_json->{pid};

    $self->{_user_selection} = car $q->param('user_selection');
    $self->{_user_selection} = '[]' if not defined $self->{_user_selection};
    $self->{_xExpList}       = decode_json( $self->{_user_selection} ) || [];
    if ( !@{ $self->{_xExpList} } ) {
        $self->add_message( { -class => 'error' },
            'You did not provide any input' );
        $self->set_action('');
        $self->default_head();
        return 1;
    }

    my ( $s, $js_src_yui, $js_src_code ) =
      @$self{qw{_UserSession _js_src_yui _js_src_code}};

    # process form and display results
    push @{ $self->{_css_src_yui} },
      (
        'paginator/assets/skins/sam/paginator.css',
        'datatable/assets/skins/sam/datatable.css'
      );
    push @$js_src_yui,
      (
        'element/element-min.js',       'paginator/paginator-min.js',
        'datasource/datasource-min.js', 'datatable/datatable-min.js'
      );

    #---------------------------------------------------------------------------
    #  filters?
    #---------------------------------------------------------------------------
    if ( $self->{_specialFilter} ) {
        my $findProbes = $self->{_FindProbes};
        $findProbes->{_dbHelper}->getSessionOverrideCGI();
        my $next_action = $findProbes->FindProbes_init();
        if ( $next_action == 1 ) {

            # get probe ids only
            $findProbes->{_extra_fields} = 0;

            my ( $headers, $records );
            $self->safe_execute(
                sub { ( $headers, $records ) = $findProbes->xTableQuery(); },
                "Could not execute query. Database response was: %s"
            );
            $self->{_ProbeList} = [ map { int( $_->[0] ) } @$records ];
            my $dbLists = $self->{_dbHelper};
            $self->{_ProbeTmpTable} = $dbLists->createTempList(
                items     => $self->{_ProbeList},
                name_type => [ 'rid', 'int(10) unsigned' ]
            );
        }
        elsif ( $next_action == 2 ) {

            # GO terms
            $self->safe_execute( sub { $findProbes->getGOTerms(); },
                "Could not execute query. Database response was: %s" );
            push @$js_src_code,
              (
                { -code => $findProbes->goTerms_js() },
                { -src  => 'GoTerms.js' }
              );
            $self->set_action('Search GO terms');
            return 1;
        }
    }

    push @$js_src_code, { -code => $self->getResultsJS() };
    push @$js_src_code, { -src  => 'CompExp.js' };
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
#       METHOD:  SearchGO_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub SearchGO_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    my $findProbes = $self->{_FindProbes};
    return $findProbes->SearchGO_body(
        action_a     => $q->url( absolute => 1 ) . '?a=compareExperiments',
        action_b     => 'Submit',
        extra_fields => [
            $q->hidden(
                -name  => 'chkAllProbes',
                -value => $self->{_chkAllProbes}
            ),
            $q->hidden(
                -name  => 'specialFilter',
                -value => $self->{_specialFilter}
            ),
            $q->hidden(
                -name  => 'user_pse',
                -value => $self->{_user_pse}
            ),
            $q->hidden(
                -name  => 'user_selection',
                -value => $self->{_user_selection}
            ),
        ]
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
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
    my ( $js_src_yui, $js_src_code, $css_src_yui, $css_src_code ) =
      @$self{qw{_js_src_yui _js_src_code _css_src_yui _css_src_code}};

    #---------------------------------------------------------------------------
    #  CSS
    #---------------------------------------------------------------------------
    push @$css_src_yui,
      (
        'button/assets/skins/sam/button.css',
        'tabview/assets/skins/sam/tabview.css',
        'datatable/assets/skins/sam/datatable.css',
        'container/assets/skins/sam/container.css'
      );

    # background image from: http://subtlepatterns.com/?p=703
    push @$css_src_code, +{ -code => <<"END_css"};
.yui-skin-sam .yui-navset .yui-content { 
    background-image:url('$IMAGES_DIR/fancy_deboss.png'); 
}
END_css

    #---------------------------------------------------------------------------
    #  Javascript
    #---------------------------------------------------------------------------
    push @$js_src_yui,
      (
        'element/element-min.js',     'dragdrop/dragdrop-min.js',
        'button/button-min.js',       'datasource/datasource-min.js',
        'datatable/datatable-min.js', 'tabview/tabview-min.js',
        'container/container-min.js'
      );
    push @$js_src_code, +{ -code => <<"END_onload"};
var tabView = new YAHOO.widget.TabView('property_editor');
YAHOO.util.Event.addListener(window, 'load', function() {
    selectTabFromHash(tabView);
});
END_onload

    my $curr_proj = $s->{session_cookie}->{curr_proj};
    my @pse_extra_studies =
        ( defined($curr_proj) && $curr_proj =~ m/^\d+$/ )
      ? ( show_unassigned_experiments => 0 )
      : (
        extra_studies => { '' => { description => '@Unassigned Experiments' } }
      );
    $self->{_PlatformStudyExperiment}->init(
        platforms   => 1,
        studies     => 1,
        experiments => 1,
        @pse_extra_studies
    );

    push @$js_src_code,
      (
        +{ -src  => 'PlatformStudyExperiment.js' },
        +{ -src  => 'collapsible.js' },
        +{ -src  => 'FormFindProbes.js' },
        +{ -src  => 'FormCompExp.js' },
        +{ -code => $self->getDropDownJS() },
      );

    return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  default_body
#      PURPOSE:  return HTML for Form in Compare Experiments
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {

    my ($self) = @_;
    my $q = $self->{_cgi};

    return $q->h2('Compare Experiments'), $q->p(<<"COMPARE_SUMMARY"),
This tool lets you obtain lists of probes with a specific pattern of expression
across specified experiments.
COMPARE_SUMMARY
      $q->div(
        { -class => 'clearfix' },
        $q->h3('1. Choose experiments'),
        $q->dl(
            $q->dt( $q->label( { -for => 'pid' }, 'Platform:' ) ),
            $q->dd(
                $q->popup_menu(
                    -id    => 'pid',
                    -title => 'Choose microarray platform'
                )
            ),
            $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
            $q->dd(
                $q->popup_menu(
                    -id    => 'stid',
                    -title => 'Choose study'
                )
            ),
            $q->dt( $q->label( { -for => 'eid' }, 'Experiment:' ) ),
            $q->dd(
                $q->popup_menu(
                    -id    => 'eid',
                    -title => 'Choose experiment'
                )
            ),
            $q->dt('&nbsp;'),
            $q->dd(
                $q->button(
                    -id     => 'add',
                    -script => '',
                    -class  => 'button black bigrounded',
                    -value  => 'Add'
                )
            ),
        )
      ),

      # experiment table
      $q->div(
        { -class => 'clearfix' },
        $q->h3('2. Specify comparison options'),
        $q->div( { -class => 'clearfix', -id => 'exp_table' }, '' )
      ),

      # form below the table
      $q->div(
        { -class => 'clearfix' },
        $q->h3('3. Perform comparison'),
        $q->start_form(
            -accept_charset => 'utf8',
            -method         => 'POST',
            -enctype        => 'multipart/form-data',
            -id             => 'form_compareExperiments',
            -action => $q->url( absolute => 1 ) . '?a=compareExperiments'
        ),
        $q->dl(
            $q->dt('Filter(s):'),
            $q->dd(
                $q->p(
                    $q->checkbox(
                        -name => 'chkAllProbes',
                        -id   => 'chkAllProbes',
                        -title =>
'Include probes not significant in all experiments labeled \'TFS 0\'',
                        -label => 'Include not significant probes'
                    ),
                    $q->p(
                        $q->checkbox(
                            -id    => 'specialFilter',
                            -name  => 'specialFilter',
                            -title => 'Special filter on probes',
                            -label => 'Special filter'
                        )
                    ),
                    $q->div(
                        {
                            -id    => 'specialFilterForm',
                            -class => "yui-pe-content"
                        },
                        $q->div( { -class => 'hd' }, 'Filter options' ),
                        $q->div(
                            { -class => 'bd' },
                            $self->{_FindProbes}->mainFormDD()
                        )
                    )
                ),

            ),
            $q->dt('&nbsp;'),
            $q->dd(
                $q->hidden(
                    -name => 'user_pse',
                    -id   => 'user_pse',
                ),
                $q->hidden(
                    -name => 'user_selection',
                    -id   => 'user_selection',
                ),
                $q->submit(
                    -name  => 'b',
                    -class => 'button black bigrounded',
                    -value => 'Submit'
                )
            )
        ),
        $q->endform
      );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
#       METHOD:  getResultsJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getResultsJS {
    my $self = shift;
    my $q    = $self->{_cgi};
    my $dbh  = $self->{_dbh};

    my $probeList = $self->{_ProbeList};
    my $probeListPredicate =
      $self->{_ProbeTmpTable}
      ? "INNER JOIN $self->{_ProbeTmpTable} USING(rid)"
      : '';
    my @query_fs_body;
    my @query_fs_body_params;

    #This flag tells us whether or not to ignore the thresholds.
    my $includeAllProbes = $self->{_chkAllProbes};
    my $rows             = $self->{_xExpList};
    for ( my $i = 0 ; $i < @$rows ; $i++ ) {
        my $row = $rows->[$i];
        my ( $eid, $sample1, $sample2, $fc, $pval, $pValClass ) =
          @$row{qw/eid sample1 sample2 fchange pval pValClass/};

        #Flagsum breakdown query
        my $flag = 1 << $i;

        push @query_fs_body, ($includeAllProbes)
          ? <<"END_part_all"
SELECT rid, IF(pvalue$pValClass < ? AND ABS(foldchange)  > ?, ?, 0) AS flag
FROM microarray 
WHERE eid=?
END_part_all
          : <<"END_part_significant";
SELECT rid, ? AS flag 
FROM microarray
WHERE eid=? AND pvalue$pValClass < ? AND ABS(foldchange)  > ?
END_part_significant
        push @query_fs_body_params,
          ($includeAllProbes)
          ? ( $pval, $fc, $flag, $eid )
          : ( $flag, $eid, $pval, $fc );
    }

    my $exp_count = @$rows;    # number of experiments being compared
    my $d1SubQuery = join( ' UNION ALL ', @query_fs_body );

    my $query_fs = <<"END_query_fs";
SELECT fs, COUNT(*) AS c 
FROM (
    SELECT BIT_OR(flag) AS fs
    FROM ($d1SubQuery) AS d1
    $probeListPredicate
    GROUP BY rid
) AS d2
GROUP BY fs
END_query_fs

    #Run the Flag Sum Query.
    my $sth_fs = $dbh->prepare($query_fs);
    $sth_fs->execute(@query_fs_body_params);
    my $h = $sth_fs->fetchall_hashref('fs');
    $sth_fs->finish;

    # counts mapping array
    my $probe_count = 0;
    my @hc = ( (0) x scalar(@$rows) );

    foreach my $value ( values %$h ) {

        # use of bitwise AND operator to test for bit presence
        ( $hc[$_] += ( 1 << $_ & $value->{fs} ) ? $value->{c} : 0 )
          for 0 .. $#$rows;
        $probe_count += $value->{c};
    }

    my $query_total = 'SELECT COUNT(*) from probe WHERE pid=?';
    my $sth_total   = $dbh->prepare($query_total);
    $sth_total->execute( $self->{_pid} );
    my $probes_in_platform = int( $sth_total->fetchrow_arrayref()->[0] );
    $sth_total->finish;

    my $js = $self->{_js_emitter};
    return ''
      . $js->let(
        [
            _xExpList          => $self->{_xExpList},
            h                  => $h,
            hc                 => \@hc,
            searchFilter       => $probeList,
            probe_count        => $probe_count,
            probes_in_platform => $probes_in_platform,
            includeAllProbes   => $includeAllProbes,
        ],
        declare => 1
      );
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
#        CLASS:  CompareExperiments
#       METHOD:  Compare_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub Compare_body {
    my $self = shift;

    my $q = $self->{_cgi};

    return
      $q->div( { -id => 'venn' }, '' ),
      $q->h2('Experiments compared'),
      $q->p( { -id => 'comparison_note' }, '' ),
      $q->div( { -id => 'summary_table', -class => 'table_cont' }, '' ),
      $q->start_form(
        -accept_charset => 'utf8',
        -method         => 'POST',
        -action         => $q->url( -absolute => 1 ) . '?a=getTFS',
        -class          => 'getTFS',
        -enctype        => 'application/x-www-form-urlencoded'
      ),
      $q->hidden( -name => 'selectedFS',  -id => 'selectedFS' ),
      $q->hidden( -name => 'selectedExp', -id => 'selectedExp' ),
      $q->hidden(
        -name  => 'user_selection',
        -id    => 'user_selection',
        -value => $self->{_user_selection}
      ),
      $q->hidden( -name => 'includeAllProbes', -id => 'includeAllProbes' ),
      $q->hidden( -name => 'searchFilter',     -id => 'searchFilter' ),
      $q->h2('Probes significant in different experiment combinations'),
      $q->p(<<"END_MATRIX"),
Rows correspond to experiment combinations, and columns labeled with pound signs
correspond to experiments (P-value used indicated in parentheses). Other
columns: <strong>Probe Subset</strong> - subsets enumerated by flagsum,
<strong>Probes</strong> - observed number of probes in the given subset,
<strong>Signif. in</strong> - number of experiments in which probes from the
given subset are significant, <strong>Log Odds Ratio</strong> - natural
logarithm of the number of observed probes (in the given subset) over the
expected (calculated assuming probes for each subset are drawn at random).
END_MATRIX
      $q->dl(
        $q->dt( $q->strong('Report format:') ),
        $q->dd(
            $q->p(
                $q->radio_group(
                    -name       => 'get',
                    -values     => [qw/HTML CSV/],
                    -default    => 'CSV',
                    -attributes => {
                        HTML => {
                            id    => 'getHTML',
                            title => 'Display data in HTML format'
                        },
                        CSV => {
                            id    => 'getCSV',
                            title => 'Download a CSV report of selected subset'
                        }
                    }
                )
            ),
            $q->p(
                { -id => 'display_format', -style => 'display:none;' },
                $q->radio_group(
                    -name    => 'opts',
                    -values  => [qw/basic data annot/],
                    -default => 'basic',
                    -labels  => {
                        'basic' => 'Basic',
                        'data'  => 'w/ Data',
                        'annot' => 'w/ Data and Annotation'
                    }
                )
            )
        )
      ),
      $q->div( { -style => 'clear:left;' },
        $q->a( { -id => 'tfs_astext' }, 'View as plain text' ) ),

      # "TFS breakdown table" -- actually a permutation matrix where rows
      # correpond to probe sets and columns correspond to experiments.
      $q->div( { -id => 'tfs_table', -class => 'table_cont' }, '' ),
      $q->endform;
}

1;

__END__

#===============================================================================
#
#         FILE:  CompareExperiments.pm
#
#  DESCRIPTION:
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  06/27/2011 21:07:40
#     REVISION:  ---
#===============================================================================



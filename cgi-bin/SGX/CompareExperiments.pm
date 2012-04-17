package SGX::CompareExperiments;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

#use Benchmark;
use JSON qw/encode_json decode_json/;
require SGX::FindProbes;
require SGX::Abstract::JSEmitter;
require SGX::DBLists;
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
    $self->SUPER::init();

    my $pse = SGX::Model::PlatformStudyExperiment->new( dbh => $dbh );
    push @{ $pse->{_Platform}->{attr} }, ( 'def_p_cutoff', 'def_f_cutoff' );
    push @{ $pse->{_Experiment}->{attr} }, 'PValFlag';

    my $findProbes = SGX::FindProbes->new(
        _dbh         => $self->{_dbh},
        _cgi         => $self->{_cgi},
        _UserSession => $self->{_UserSession}
    );

    $self->set_attributes(
        _title                   => 'Compare Experiments',
        _PlatformStudyExperiment => $pse,
        _FindProbes              => $findProbes
    );
    $self->register_actions(
        Submit => { head => 'Compare_head', body => 'Compare_body' } );

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

    $self->set_attributes( _dbLists => SGX::DBLists->new( delegate => $self ),
    );

    my $q = $self->{_cgi};
    $self->{_user_selection} = car $q->param('user_selection');
    $self->{_xExpList} = decode_json( $self->{_user_selection} ) || [];
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
    push @$js_src_code, { -code => $self->getResultsJS() };
    push @$js_src_code, { -src  => 'CompExp.js' };
    return 1;
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

    push @$js_src_code,
      (
        +{ -src => 'collapsible.js' },
        +{ -src => 'FormFindProbes.js' },
        +{ -src => 'FormCompExp.js' }
      );

    $self->{_PlatformStudyExperiment}->init(
        platforms     => 1,
        studies       => 1,
        experiments   => 1,
        extra_studies => { '' => { description => '@Unassigned Experiments' } }
    );
    push @$js_src_code, { -src  => 'PlatformStudyExperiment.js' };
    push @$js_src_code, { -code => $self->getDropDownJS() };

    $self->{_species_data} = $self->{_FindProbes}->get_species();
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

    return $q->h2('Compare Experiments'),
      $q->div(
        { -class => 'clearfix' },
        $q->h3('1. Choose experiments:'),
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
            $q->dt( $q->label( { -for => 'eid' }, 'Experiment:' ) ),
            $q->dd(
                $q->popup_menu(
                    -name  => 'eid',
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
        $q->h3('2. Specify comparison options:'),
        $q->div( { -class => 'clearfix', -id => 'exp_table' }, '' )
      ),

      # form below the table
      $q->div(
        { -class => 'clearfix' },
        $q->h3('3. Run comparison:'),
        $q->start_form(
            -method  => 'POST',
            -enctype => 'multipart/form-data',
            -id      => 'form_compareExperiments',
            -action  => $q->url( absolute => 1 ) . '?a=compareExperiments'
        ),
        $q->dl(
            $q->dt('Filter(s):'),
            $q->dd(
                $q->p(
                    $q->checkbox(
                        -name  => 'chkAllProbes',
                        -id    => 'chkAllProbes',
                        -value => '1',
                        -title =>
'Include probes not significant in all experiments labeled \'TFS 0\'',
                        -label => 'Include not significant probes'
                    ),
                    $q->p(
                        $q->checkbox(
                            -id    => 'specialFilter',
                            -name  => 'specialFilter',
                            -value => '1',
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
                            $self->{_FindProbes}
                              ->mainFormDD( $self->{_species_data} )
                        )
                    )
                ),

            ),
            $q->dt('&nbsp;'),
            $q->dd(
                $q->hidden(
                    -name  => 'user_selection',
                    -id    => 'user_selection',
                    -value => ''
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
#       METHOD:  getResults
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getResults {
    my $self = shift;
    my $q    = $self->{_cgi};
    my $dbh  = $self->{_dbh};
    my $s    = $self->{_UserSession};

    #This flag tells us whether or not to ignore the thresholds.
    my $includeAllProbes = $q->param('chkAllProbes');

    my $findProbes = SGX::FindProbes->new(
        _dbh         => $dbh,
        _cgi         => $q,
        _UserSession => $s
    );
    $findProbes->getSessionOverrideCGI();
    my $probeListPredicate = '';
    my $probeList          = [];

    if ( $findProbes->FindProbes_init() ) {

        # get probe ids only
        $findProbes->{_extra_fields} = 0;
        my ( $headers, $records ) = $findProbes->xTableQuery();
        $probeList = [ map { $_->[0] } @$records ];
        my $dbLists  = $self->{_dbLists};
        my $tmpTable = $dbLists->createTempList(
            items     => $probeList,
            name_type => [ 'rid', 'int(10) unsigned' ]
        );
        $probeListPredicate = "INNER JOIN $tmpTable USING(rid)";
    }

    #If we are filtering, generate the SQL statement for the rid's.
    my @query_titles;
    my @query_titles_params;
    my @query_fs_body;
    my @query_fs_body_params;

    my $rows = $self->{_xExpList};
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
    my $sth_fs      = $dbh->prepare($query_fs);
    my $rowcount_fs = $sth_fs->execute(@query_fs_body_params);
    my $h           = $sth_fs->fetchall_hashref('fs');
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

    return {
        h                => $h,
        hc               => \@hc,
        probeList        => $probeList,
        probe_count      => $probe_count,
        includeAllProbes => $includeAllProbes,
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
#       METHOD:  getResultsJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is called when experiments are compared.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getResultsJS {
    my $self    = shift;
    my $results = $self->getResults();

    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );
    return ''
      . $js->let(
        [
            _xExpList        => $self->{_xExpList},
            h                => $results->{h},
            hc               => $results->{hc},
            searchFilter     => $results->{probeList},
            probe_count      => $results->{probe_count},
            includeAllProbes => $results->{includeAllProbes},
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

    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );
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
      $q->div( { -id => 'summary_table', -class => 'table_cont' }, '' ),
      $q->start_form(
        -method  => 'POST',
        -action  => $q->url( -absolute => 1 ) . '?a=getTFS',
        -target  => '_blank',
        -class   => 'getTFS',
        -enctype => 'application/x-www-form-urlencoded'
      ),
      $q->hidden( -name => 'selectedFS', -id => 'selectedFS' ),
      $q->hidden(
        -name  => 'user_selection',
        -id    => 'user_selection',
        -value => $self->{_user_selection}
      ),
      $q->hidden( -name => 'includeAllProbes', -id => 'includeAllProbes' ),
      $q->hidden( -name => 'searchFilter',     -id => 'searchFilter' ),
      $q->h2('Probes significant in different experiment combinations'),
      $q->p( $q->strong('Data to display:') ),
      $q->p(
        $q->radio_group(
            -name    => 'opts',
            -values  => [qw/basic data annot/],
            -default => 'basic',
            -labels  => {
                'basic' => 'Basic',
                'data'  => 'Include Data',
                'annot' => 'Include Data & Annotation'
            }
        )
      ),
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



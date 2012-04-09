package SGX::CompareExperiments;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

#use Benchmark;
#use SGX::Debug;
use URI::Escape qw/uri_escape/;
use JSON qw/encode_json decode_json/;
require Tie::IxHash;
require SGX::FindProbes;
require SGX::Abstract::JSEmitter;
require SGX::DBLists;
require SGX::Model::PlatformStudyExperiment;
use SGX::Abstract::Exception ();
use SGX::Util qw/car count_gtzero max abbreviate/;
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

    $self->set_attributes(
        _title                   => 'Compare Experiments',
        _PlatformStudyExperiment => $pse
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
    $self->{_xExpList} = decode_json( $q->param('user_selection') ) || [];
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

    my $findProbes = SGX::FindProbes->new(
        _dbh         => $self->{_dbh},
        _cgi         => $self->{_cgi},
        _UserSession => $self->{_UserSession}
    );
    $self->{_species_data} = $findProbes->get_species();
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

    my $findProbes = SGX::FindProbes->new(
        _dbh         => $self->{_dbh},
        _cgi         => $q,
        _UserSession => $self->{_UserSession}
    );

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
                    -id    => 'add',
                    -class => 'button black bigrounded',
                    -value => 'Add'
                )
            ),
        )
      ),

      # experiment table
      $q->div(
        { -class => 'clearfix' },
        $q->h3('2. Set experiment options:'),
        $q->div( { -class => 'clearfix', -id => 'exp_table' }, '' )
      ),

      # form below the table
      $q->div(
        { -class => 'clearfix' },
        $q->h3('3. Compare:'),
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
                            $findProbes->mainFormDD( $self->{_species_data} )
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
    my $allProbes = $q->param('chkAllProbes');

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
    my ( @stid_eid, @reverses, @fcs, @pvals );

    my $rows = $self->{_xExpList};
    for ( my $i = 0 ; $i < @$rows ; $i++ ) {
        my $row = $rows->[$i];
        my ( $stid, $eid, $fc, $pval, $pValClass, $reverse ) =
          @$row{qw/stid eid fchange pval pValClass reverse/};

        $reverse = ( $reverse eq JSON::true ) ? 1 : 0;

        #Prepare the four arrays that will be used to display data
        push @stid_eid, [ $stid, $eid ];
        push @reverses, $reverse;
        push @fcs,      $fc;
        push @pvals,    $pval;

        #Flagsum breakdown query
        my $flag = 1 << $i;

        push @query_fs_body, ($allProbes)
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
        push @query_fs_body_params, ($allProbes)
          ? ($pval, $fc, $flag, $eid)
          : ( $flag, $eid, $pval, $fc );

        # account for sample order when building title query
        my $title =
          ($reverse)
          ? "experiment.sample1, ' / ', experiment.sample2"
          : "experiment.sample2, ' / ', experiment.sample1";

        push @query_titles, <<"END_query_titles";
SELECT eid, CONCAT(GROUP_CONCAT(study.description SEPARATOR ','), ': ', ?) AS title 
FROM experiment 
LEFT JOIN StudyExperiment USING(eid)
LEFT JOIN study USING(stid)
WHERE eid=?
GROUP BY eid
END_query_titles
        push @query_titles_params, ($title, $eid);
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

    my $query_titles = join( ' UNION ALL ', @query_titles );

    my $sth_titles      = $dbh->prepare($query_titles);
    my $rowcount_titles = $sth_titles->execute(@query_titles_params);

    #assert( $rowcount_titles == $exp_count );

    my $ht = $sth_titles->fetchall_hashref('eid');
    $sth_titles->finish;

    my $rep_count = 0;

    # counts mapping array
    my @hc = ( (0) x $rowcount_titles );
    foreach my $value ( values %$h ) {

        #for ( $i = 0 ; $i < $rowcount_titles ; $i++ ) {

        #    # use of bitwise AND operator to test for bit presence
        #    $hc[$i] += $value->{c} if 1 << $i & $value->{fs};
        #}
        ( $hc[$_] += ( 1 << $_ & $value->{fs} ) ? $value->{c} : 0 )
          for 0 .. ( $rowcount_titles - 1 );
        $rep_count += $value->{c};
    }

    return {
        stid_eid        => \@stid_eid,
        reverses        => \@reverses,
        fcs             => \@fcs,
        pvals           => \@pvals,
        hc              => \@hc,
        ht              => $ht,
        h               => $h,
        rep_count       => $rep_count,
        rowcount_titles => $rowcount_titles,
        allProbes       => $allProbes,
        probeList       => $probeList,
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
#       METHOD:  getVennURI
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Draw a 750x300 area-proportional Venn diagram using Google API
#                if $rowcount_titles is (2,3).
#
#                http://code.google.com/apis/chart/types.html#venn
#                http://code.google.com/apis/chart/formats.html#data_scaling
#
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getVennURI {
    my %args            = @_;
    my $rowcount_titles = $args{rowcount_titles};
    my $h               = $args{h};
    my $ht              = $args{ht};
    my $hc              = $args{hc};
    my $stid_eid        = $args{stid_eid};

    my $qstring = '';
    if ( $rowcount_titles == 2 ) {

        # draw two circles
        my @c;
        for ( my $i = 1 ; $i < 4 ; $i++ ) {

            # replace undefined values with zeros
            push @c, ( defined( $h->{$i} ) ) ? $h->{$i}->{c} : 0;
        }
        my $AB = $c[2];
        my ( $A, $B ) = @$hc[ 0 .. 1 ];

        #assert( $A == $c[0] + $AB );
        #assert( $B == $c[1] + $AB );

        # scale must be equal to the area of the largest circle
        my $scale = max( $A, $B );
        my @nums = ( $A, $B, 0, $AB );
        $qstring =
            'http://chart.apis.google.com/chart?cht=v&amp;chd=t:'
          . join( ',', @nums )
          . '&amp;chds=0,'
          . $scale
          . '&amp;chs=750x300&chtt=Significant+Probes&amp;chco=ff0000,00ff00&amp;chdl='
          . join( '|',
            map { uri_escape( "$_. " . abbreviate( $ht->{$_}->{title}, 60 ) ) }
            map { $_->[1] } @$stid_eid[ 0 .. 1 ] );
    }
    elsif ( $rowcount_titles == 3 ) {

        # draw three circles
        my @c;
        for ( my $i = 1 ; $i < 8 ; $i++ ) {

            # replace undefined values with zeros
            push @c, ( defined( $h->{$i} ) ) ? $h->{$i}->{c} : 0;
        }
        my $ABC = $c[6];
        my $AB  = $c[2] + $ABC;
        my $AC  = $c[4] + $ABC;
        my $BC  = $c[5] + $ABC;
        my ( $A, $B, $C ) = @$hc[ 0 .. 2 ];

        my $chart_title =
          ( count_gtzero( $A, $B, $C ) > 2 )
          ? 'Significant+Probes+(Approx.)'
          : 'Significant+Probes';

        #assert( $A == $c[0] + $c[2] + $c[4] + $ABC );
        #assert( $B == $c[1] + $c[2] + $c[5] + $ABC );
        #assert( $C == $c[3] + $c[4] + $c[5] + $ABC );

        # scale must be equal to the area of the largest circle
        my $scale = max( $A, $B, $C );
        my @nums = ( $A, $B, $C, $AB, $AC, $BC, $ABC );
        $qstring =
            'http://chart.apis.google.com/chart?cht=v&amp;chd=t:'
          . join( ',', @nums )
          . '&amp;chds=0,'
          . $scale
          . "&amp;chs=750x300&chtt=$chart_title&amp;chco=ff0000,00ff00,0000ff&amp;chdl="
          . join( '|',
            map { uri_escape( "$_. " . abbreviate( $ht->{$_}->{title}, 60 ) ) }
            map { $_->[1] } @$stid_eid[ 0 .. 2 ] );
    }
    return $qstring;
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
    my $self = shift;
    my $obj  = $self->getResults();

    # scalars
    my $rep_count       = $obj->{rep_count};
    my $rowcount_titles = $obj->{rowcount_titles};
    my $allProbes       = $obj->{allProbes};
    my $probeList       = $obj->{probeList};

    # references
    my $reverses = $obj->{reverses};
    my $stid_eid = $obj->{stid_eid};
    my $hc       = $obj->{hc};
    my $h        = $obj->{h};
    my $ht       = $obj->{ht};
    my $fcs      = $obj->{fcs};
    my $pvals    = $obj->{pvals};

    my $out = '';
    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );

    my $vennURI = getVennURI(
        rowcount_titles => $rowcount_titles,
        h               => $h,
        ht              => $ht,
        hc              => $hc,
        stid_eid        => $stid_eid
    );
    $out .= $js->let(
        [
            venn => ($vennURI)
            ? "<img alt=\"Venn Diagram\" src=\"$vennURI\" />"
            : ''
        ],
        declare => 1
    );

    # Summary table -------------------------------------
    my @tmpArray;
    for ( my $i = 0 ; $i < @$stid_eid ; $i++ ) {
        my ( $currentSTID, $currentEID ) = @{ $stid_eid->[$i] };
        push @tmpArray,
          [
            $currentEID, $ht->{$currentEID}->{title},
            $fcs->[$i],  $pvals->[$i],
            $hc->[$i]
          ];
    }

    $out .= $js->let(
        [
            rep_count => $rep_count,
            eid       => join( ',', map { join( '|', @$_ ) } @$stid_eid ),
            rev       => join( ',', @$reverses ),
            fc        => join( ',', @$fcs ),
            pval      => join( ',', @$pvals ),
            allProbes => (
                ( defined $allProbes )
                ? $allProbes
                : ''
            ),
            searchFilter => $probeList,
            summary      => {
                caption => 'Experiments compared',
                records => \@tmpArray
            }
        ],
        declare => 1
    );

    # TFS breakdown table ------------------------------
    my $tfs_defs =
"{key:\"0\", sortable:true, resizeable:false, label:\"FS\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},\n";
    my $tfs_response_fields = "{key:\"0\", parser:\"number\"},\n";
    my $i;
    for ( $i = 1 ; $i <= @$stid_eid ; $i++ ) {
        my ( $this_stid, $this_eid ) = @{ $stid_eid->[ $i - 1 ] };
        $tfs_defs .=
"{key:\"$i\", sortable:true, resizeable:false, label:\"#$this_eid\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},\n";
        $tfs_response_fields .= "{key:\"$i\"},\n";
    }
    $tfs_defs .=
"{key:\"$i\", sortable:true, resizeable:true, label:\"Probe Count\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}}, {key:\""
      . ( $i + 1 )
      . "\", sortable:false, resizeable:true, label:\"View probes\", formatter:\"formatDownload\"}\n";
    $tfs_response_fields .=
        "{key:\"$i\", parser:\"number\"}, {key:\""
      . ( $i + 1 )
      . "\", parser:\"number\"}\n";

    my @tfsBreakdown;
    foreach my $key ( sort { $h->{$b}->{fs} <=> $h->{$a}->{fs} } keys %$h ) {

        # numerical sort on hash value
        push @tfsBreakdown,
          {
            0 => $key,
            (
                map { $_ => ( 1 << ( $_ - 1 ) & $h->{$key}->{fs} ) ? 'x' : '' }
                  1 .. $rowcount_titles
            ),
            ( $rowcount_titles + 1 ) => $h->{$key}->{c}
          };
    }
    $out .= $js->let(
        [
            tfs => {
                caption =>
'Probes grouped by significance in different experiment combinations',
                records => \@tfsBreakdown
            }
        ],
        declare => 1
    ) . <<"END_extra_js";
YAHOO.util.Event.addListener(window, "load", function() {
    var Dom = YAHOO.util.Dom;
    Dom.get("eid").value = eid;
    Dom.get("rev").value = rev;
    Dom.get("fc").value = fc;
    Dom.get("pval").value = pval;
    Dom.get("allProbes").value = allProbes;
    Dom.get("searchFilter").value = searchFilter;
    Dom.get("venn").innerHTML = venn;
    Dom.get("summary_caption").innerHTML = summary.caption;
    var summary_table_defs = [
        {key:"0", sortable:true, resizeable:false, label:"#"},
        {key:"1", sortable:true, resizeable:true, label:"Experiment"},
        {key:"2", sortable:true, resizeable:false, label:"&#124;Fold Change&#124; &gt;"}, 
        {key:"3", sortable:true, resizeable:false, label:"P &lt;"},
        {key:"4", sortable:true, resizeable:false, label:"Probe Count"}
    ];
    var summary_data = new YAHOO.util.DataSource(summary.records);
    summary_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    summary_data.responseSchema = { fields: [
        {key:"0", parser:"number"},
        {key:"1"},
        {key:"2", parser:"number"},
        {key:"3", parser:"number"},
        {key:"4", parser:"number"}
    ]};
    var summary_table = new YAHOO.widget.DataTable("summary_table", summary_table_defs, summary_data, {});

    YAHOO.widget.DataTable.Formatter.formatDownload = function(elCell, oRecord, oColumn, oData) {
        var fs = oRecord.getData("0");
        elCell.innerHTML = "<input class=\\"plaintext\\" type=\\"submit\\" name=\\"get\\" value=\\"TFS " + fs + " (HTML)\\" />&nbsp;&nbsp;&nbsp;<input class=\\"plaintext\\" type=\\"submit\\" name=\\"get\\" value=\\"TFS " + fs + " (CSV)\\" />";
    }
    Dom.get("tfs_caption").innerHTML = tfs.caption;
    Dom.get("tfs_all_dt").innerHTML = "View data for $rep_count probes:";
    Dom.get("tfs_all_dd").innerHTML = "<input type=\\"submit\\" name=\\"get\\" class=\\"plaintext\\" value=\\"TFS (HTML)\\" /><span class=\\"separator\\"> / </span><input type=\\"submit\\" class=\\"plaintext\\" name=\\"get\\" value=\\"TFS (CSV)\\" />";
    var tfs_table_defs = [ $tfs_defs ];
    var tfs_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 50 
        })
    };
    var tfs_data = new YAHOO.util.DataSource(tfs.records);
    tfs_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    tfs_data.responseSchema = {
        fields: [$tfs_response_fields]
    };
    var tfs_table = new YAHOO.widget.DataTable("tfs_table", tfs_table_defs, tfs_data, tfs_config);
});
END_extra_js

    return $out;
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

    my %opts_dropdown;
    my $opts_dropdown_t = tie(
        %opts_dropdown, 'Tie::IxHash',
        '0' => 'Basic (ratios and p-value only)',
        '1' => 'Experiment data',
        '2' => 'Experiment data with annotations'
    );

    return
      $q->div( { -id => 'venn' }, '' ),
      $q->h2( { -id => 'summary_caption' }, '' ),
      $q->div( { -id => 'summary_table', -class => 'table_cont' }, '' ),
      $q->start_form(
        -method  => 'POST',
        -action  => $q->url( -absolute => 1 ) . '?a=getTFS',
        -target  => '_blank',
        -class   => 'getTFS',
        -enctype => 'application/x-www-form-urlencoded'
      ),
      $q->hidden( -name => 'eid',          -id => 'eid' ),
      $q->hidden( -name => 'rev',          -id => 'rev' ),
      $q->hidden( -name => 'fc',           -id => 'fc' ),
      $q->hidden( -name => 'pval',         -id => 'pval' ),
      $q->hidden( -name => 'allProbes',    -id => 'allProbes' ),
      $q->hidden( -name => 'searchFilter', -id => 'searchFilter' ),
      $q->h2( { -id => 'tfs_caption' }, '' ),
      $q->dl(
        $q->dt( $q->label( { -for => 'opts' }, 'Data to display:' ) ),
        $q->dd(
            $q->popup_menu(
                -name    => 'opts',
                -id      => 'opts',
                -values  => [ keys %opts_dropdown ],
                -default => '0',
                -labels  => \%opts_dropdown
            )
        ),
        $q->dt( { -id => 'tfs_all_dt' }, "&nbsp;" ),
        $q->dd( { -id => 'tfs_all_dd' }, "&nbsp;" )
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



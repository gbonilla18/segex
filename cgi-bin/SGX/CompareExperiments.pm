#
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

package SGX::CompareExperiments;

use strict;
use warnings;

use Benchmark;
use Switch;
use URI::Escape;
use JSON::XS;
use Tie::IxHash;
use SGX::Debug qw/assert/;
use SGX::FindProbes;
use Data::Dumper;
use SGX::Abstract::Exception;
use SGX::Abstract::JSEmitter;
use SGX::Util qw/count_gtzero max/;

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
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
        _js_src_code => $js_src_code
    };

    # find out what the current project is set to
    if ( defined $s ) {
        $self->{_WorkingProject}     = $s->{session_cookie}->{curr_proj};
        $self->{_WorkingProjectName} = $s->{session_cookie}->{proj_name};
        $self->{_UserFullName}       = $s->{session_cookie}->{full_name};
    }

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
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
    my ( $q,          $s )           = @$self{qw{_cgi _UserSession}};
    my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    push @$js_src_yui, ('yahoo-dom-event/yahoo-dom-event.js');
    switch ($action) {
        case 'Compare' {

            # process form and display results
            return unless $s->is_authorized('user');
            push @$js_src_yui,
              (
                'yahoo-dom-event/yahoo-dom-event.js',
                'element/element-min.js',
                'paginator/paginator-min.js',
                'datasource/datasource-min.js',
                'datatable/datatable-min.js'
              );
            push @$js_src_code, { -code => $self->getResultsJS() };
        }
        else {

            # show form
            return unless $s->is_authorized('user');
            push @$js_src_yui,
              (
                'yahoo-dom-event/yahoo-dom-event.js',
                'element/element-min.js',
                'button/button-min.js'
              );
            push @$js_src_code,
              (
                +{ -code => $self->getFormJS() },
                +{ -src  => 'FormCompareExperiments.js' }
              );
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
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

    my ( $q, $s ) = @$self{qw{_cgi _UserSession}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    switch ($action) {
        case 'Compare' {

            # show results
            print $self->getResultsHTML();

            #print SGX::CompareExperiments::getResultsHTML( $q, DOWNLOADTFS );
        }
        else {

            # default action: show form
            print $self->getFormHTML();

            #print SGX::CompareExperiments::getFormHTML( $q, FORM .
            #    COMPAREEXPERIMENTS, COMPAREEXPERIMENTS );
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CompareExperiments
#       METHOD:  getFormJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getFormJS {
    my $self = shift;
    my $s    = $self->{_UserSession};
    my $dbh  = $self->{_dbh};

    # find out what the current project is set to
    my $curr_proj = $s->{session_cookie}->{curr_proj};

    # get a list of platforms and cutoff values
    my $query_text;
    my @query_params;
    if ( !defined($curr_proj) || $curr_proj eq '' ) {

        # current project not set or set to 'All Projets'
        $query_text =
          qq{SELECT pid, pname, def_p_cutoff, def_f_cutoff FROM platform};
    }
    else {

        # current project is set
        push @query_params, $curr_proj;
        $query_text = <<"END_PLATFORM_QUERY"
SELECT pid, pname, def_p_cutoff, def_f_cutoff 
FROM platform 
RIGHT JOIN study USING(pid) 
RIGHT JOIN ProjectStudy USING(stid)
WHERE prid=? 
GROUP BY pid

END_PLATFORM_QUERY
    }
    my $sth      = $dbh->prepare($query_text);
    my $rowcount = $sth->execute(@query_params);
    assert($rowcount);

    ### populate a Javascript hash with the content of the platform recordset
    my %json_platform;
    while ( my @row = $sth->fetchrow_array ) {

        # format:
        # 0 - platform id => [
        #   1 - platform name
        #   2 - P-value cutoff
        #   3 - fold-change cutoff
        # ];
        $json_platform{ $row[0] } = [ $row[1], $row[2], $row[3] ];
    }
    $sth->finish;

    # get a list of studies
    if ( !defined($curr_proj) || $curr_proj eq '' ) {

        # current project not set or set to 'All Projects'
        $sth      = $dbh->prepare(qq{select stid, description, pid from study});
        $rowcount = $sth->execute();
    }
    else {

        # current project is set
        $sth = $dbh->prepare(
qq{select stid, description, pid from study RIGHT JOIN ProjectStudy USING(stid) WHERE prid=? group by stid}
        );
        $rowcount = $sth->execute($curr_proj);
    }
    assert($rowcount);

    ### populate a Javascript hash with the content of the study recordset
    my %json_study;
    while ( my @row = $sth->fetchrow_array ) {

        # format:
        # study_id => [
        #   0 - study description
        #   1 - sample 1 name
        #   2 - sample 2 name
        #   3 - platform id
        # ];
        $json_study{ $row[0] } = [ $row[1], {}, {}, $row[2] ];
    }
    $sth->finish;

    # get a list of all experiments
    if ( !defined($curr_proj) || $curr_proj eq '' ) {
        $sth = $dbh->prepare(<<"END_EXP_QUERY");
select stid, eid, experiment.sample2 as s2_desc, experiment.sample1 as s1_desc 
from study 
inner join StudyExperiment USING(stid)
inner join experiment using(eid)
GROUP BY eid

END_EXP_QUERY
        $rowcount = $sth->execute();
    }
    else {
        $sth = $dbh->prepare(<<"END_EXP_QUERY");
select stid, eid, experiment.sample2 as s2_desc, experiment.sample1 as s1_desc 
from experiment
inner join StudyExperiment USING(eid)
inner join study using(stid)
inner join ProjectStudy USING(stid)
WHERE prid = ?
GROUP BY eid

END_EXP_QUERY
        $rowcount = $sth->execute($curr_proj);
    }
    assert($rowcount);

    ### populate the Javascript hash with the content of the experiment recordset
    while ( my @row = $sth->fetchrow_array ) {
        $json_study{ $row[0] }->[1]->{ $row[1] } = $row[2];
        $json_study{ $row[0] }->[2]->{ $row[1] } = $row[3];
    }
    $sth->finish;

    return sprintf(
        <<"END_form_compareExperiments_js",
var form = "%s";
var platform = %s;
var study = %s;
END_form_compareExperiments_js
        'form_compareExperiments',
        encode_json( \%json_platform ),
        encode_json( \%json_study )
    );
}

#===  FUNCTION  ================================================================
#         NAME:  getFormHTML
#      PURPOSE:  return HTML for Form in Compare Experiments
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getFormHTML {

    #my ( $q, $form_action, $submit_action ) = @_;
    my ($self) = @_;
    my $q = $self->{_cgi};

    my %gene_dropdown;
    my $gene_dropdown_t = tie(
        %gene_dropdown, 'Tie::IxHash',
        'gene'   => 'Gene Symbols',
        'accnum' => 'Accession Numbers',
        'probe'  => 'Probes'
    );
    my %match_dropdown;
    my $match_dropdown_t = tie(
        %match_dropdown, 'Tie::IxHash',
        'full'   => 'Full Word',
        'prefix' => 'Prefix',
        'part'   => 'Part of the Word / Regular Expression*'
    );

    return
      $q->h2('Compare Experiments'),
      $q->dl(
        $q->dt('Add experiment from platform:'),
        $q->dd(
            $q->popup_menu( -name => 'platform', -id => 'platform' ),
            $q->span( { -class => 'separator' }, ' : ' ),
            $q->a( { -id => 'add_experiment' }, 'Add experiment' )
        )
      ),
      $q->start_form(
        -method => 'POST',
        -id     => 'form_compareExperiments',
        -action => $q->url( absolute => 1 ) . '?a=compareExperiments'
      ),
      $q->dl(
        $q->dt('Include not significant probes:'),
        $q->dd(
            $q->checkbox(
                -name  => 'chkAllProbes',
                -id    => 'chkAllProbes',
                -value => '1',
                -label =>
'(probes not significant in all experiments labeled \'TFS 0\')'
            )
        ),
        $q->dt('Filter on:'),
        $q->dd( { -id => 'geneFilter' }, '' )
      ),
      $q->div(
        { -id => 'filterList', -style => 'display:none;' },
        $q->h3('Filter on the following terms:'),
        $q->dl(
            $q->dt( $q->label( { -for => 'terms' }, 'Search term(s):' ) ),
            $q->dd(
                $q->textarea(
                    -rows     => 10,
                    -columns  => 50,
                    -tabindex => 1,
                    -name     => 'terms',
                    -id       => 'terms'
                )
            ),
        )
      ),
      $q->div(
        { -id => 'filterUpload', -style => 'display:none;' },
        $q->h3('Filter on uploaded file:'),
        $q->dl(
            $q->dt( $q->label( { -for => 'upload_file' }, 'Upload File:' ) ),
            $q->dd(
                $q->filefield(
                    -name => 'upload_file',
                    -id   => 'upload_file',
                    -title =>
'File must be in tab-delimited format, without a header, and with search terms in the first column.'
                ),
            )
        )
      ),
      $q->dl(
        { -id => 'filterAny', -style => 'display:none;' },
        $q->dt('Terms are:'),
        $q->dd(
            $q->popup_menu(
                -name    => 'type',
                -values  => [ keys %gene_dropdown ],
                -default => 'gene',
                -labels  => \%gene_dropdown
            )
        ),
        $q->dt('Patterns to match:'),
        $q->dd(
            $q->radio_group(
                -tabindex  => 2,
                -name      => 'match',
                -values    => [ keys %match_dropdown ],
                -default   => 'full',
                -linebreak => 'true',
                -labels    => \%match_dropdown
            )
        )
      ),
      $q->dl(
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -class => 'button black bigrounded',
                -value => 'Compare'
            )
        )
      ),
      $q->endform;
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
    my $s    = $self->{_UserSession};
    my $dbh  = $self->{_dbh};

    #This flag tells us whether or not to ignore the thresholds.
    my $allProbes = $q->param('chkAllProbes');

    my $probeListPredicate = '';
    my $probeList          = '';

    if ( $q->param('upload_file') ) {

       # if $q->param('upload_file') is not set, all other fields in Upload File
       # subsection don't matter
       #assert( !$q->param('terms') );
        my $findProbes = SGX::FindProbes->new(
            dbh          => $dbh,
            cgi          => $q,
            user_session => $s
        );

        # parse uploaded file (highly likely to fail!)
        my $fh = $q->upload('upload_file')
          or SGX::Abstract::Exception::User->throw(
            error => "Failed to upload file.\n" );

        my $ok = eval { $findProbes->init($fh) } || 0;

        # :TODO:07/29/2011 16:59:31:es: test zero-length upload files here
        if ( ( my $exception = $@ ) || !$ok ) {
            close $fh;
            $exception->throw();
        }
        close $fh;

        $findProbes->getSessionOverrideCGI();
        $findProbes->build_InsideTableQuery();
        $findProbes->build_SimpleProbeQuery();

        #my $t0 = Benchmark->new;
        $findProbes->loadProbeData();

        #my $t1 = Benchmark->new;
        #my $td = timediff( $t1, $t0 );
        #warn "the code took:", timestr($td), "\n";

        # get list of probe record ids (rid)
        my $probeList = $findProbes->getProbeList();
        $probeListPredicate = sprintf( ' WHERE rid IN (%s) ',
            ( @$probeList > 0 ) ? join( ',', @$probeList ) : 'NULL' );
    }
    elsif ( $q->param('terms') ) {

        # if $q->param('terms') is not set, all other fields in Filter List
        # subsection don't matter
        assert( !$q->param('upload_file') );
        my $findProbes = SGX::FindProbes->new(
            dbh          => $dbh,
            cgi          => $q,
            user_session => $s
        );

        $findProbes->init();    # followed by build_ProbeQuery
        $findProbes->getSessionOverrideCGI();
        $findProbes->build_InsideTableQuery();
        $findProbes->build_SimpleProbeQuery();
        $findProbes->loadProbeData();

        # get list of probe record ids (rid)
        my $probeList = $findProbes->getProbeList();
        $probeListPredicate = sprintf( ' WHERE rid IN (%s) ',
            ( @$probeList > 0 ) ? join( ',', @$probeList ) : 'NULL' );
    }

    #If we are filtering, generate the SQL statement for the rid's.
    my @query_titles;
    my @query_fs_body;
    my ( @eids, @reverses, @fcs, @pvals, @true_eids );

    my $i;
    for ( $i = 1 ; defined( $q->param("eid_$i") ) ; $i++ ) {
        my ( $eid, $fc, $pval ) =
          ( $q->param("eid_$i"), $q->param("fc_$i"), $q->param("pval_$i") );
        my $reverse = ( defined( $q->param("reverse_$i") ) ) ? 1 : 0;

        #Prepare the four arrays that will be used to display data
        push @eids,     $eid;
        push @reverses, $reverse;
        push @fcs,      $fc;
        push @pvals,    $pval;

        my ( $currentSTID, $currentEID ) = split( /\|/, $eid );

        push @true_eids, $currentEID;

        #Flagsum breakdown query
        my $flag = 1 << $i - 1;

        push @query_fs_body, ($allProbes)
          ? <<"END_part_all"
SELECT rid, IF(pvalue < $pval AND ABS(foldchange)  > $fc, $flag, 0) AS flag
FROM microarray 
WHERE eid=$currentEID
END_part_all
          : <<"END_part_significant";
SELECT rid, $flag AS flag 
FROM microarray
WHERE eid=$currentEID AND pvalue < $pval AND ABS(foldchange)  > $fc
END_part_significant

        # account for sample order when building title query
        my $title =
          ($reverse)
          ? "experiment.sample1, ' / ', experiment.sample2"
          : "experiment.sample2, ' / ', experiment.sample1";

        push @query_titles, <<"END_query_titles";
SELECT eid, CONCAT(study.description, ': ', $title) AS title 
FROM experiment 
INNER JOIN StudyExperiment USING(eid)
INNER JOIN study USING(stid)
WHERE eid=$currentEID AND StudyExperiment.stid=$currentSTID
END_query_titles
    }

    my $exp_count = $i - 1;    # number of experiments being compared
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
    my $rowcount_fs = $sth_fs->execute();
    my $h           = $sth_fs->fetchall_hashref('fs');
    $sth_fs->finish;

    my $sth_titles = $dbh->prepare( join( ' UNION ALL ', @query_titles ) );
    my $rowcount_titles = $sth_titles->execute();

    assert( $rowcount_titles == $exp_count );
    my $ht = $sth_titles->fetchall_hashref('eid');
    $sth_titles->finish;

    my $rep_count = 0;

    # initialize the hash
    my %hc = map { $_ => 0 } ( 0 .. ( $exp_count - 1 ) );
    foreach my $value ( values %$h ) {
        for ( $i = 0 ; $i < $exp_count ; $i++ ) {

            # use of bitwise AND operator to test for bit presence
            $hc{$i} += $value->{c} if 1 << $i & $value->{fs};
        }
        $rep_count += $value->{c};
    }

    # Draw a 750x300 area-proportional Venn diagram using Google API if
    # $exp_count is (2,3).
    #
    # http://code.google.com/apis/chart/types.html#venn
    # http://code.google.com/apis/chart/formats.html#data_scaling
    #
    my $out = '';
    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );

    switch ($exp_count) {
        case 2 {

            # draw two circles
            my @c;
            for ( $i = 1 ; $i < 4 ; $i++ ) {

                # replace undefined values with zeros
                push @c, ( defined( $h->{$i} ) ) ? $h->{$i}->{c} : 0;
            }
            my $AB = $c[2];
            my ( $A, $B ) = ( $hc{0}, $hc{1} );

            #assert( $A == $c[0] + $AB );
            #assert( $B == $c[1] + $AB );

            my ( $currentSTID1, $currentEID1 ) = split( /\|/, $eids[0] );
            my ( $currentSTID2, $currentEID2 ) = split( /\|/, $eids[1] );

            # scale must be equal to the area of the largest circle
            my $scale = max( $A, $B );
            my @nums = ( $A, $B, 0, $AB );
            my $qstring =
                'cht=v&amp;chd=t:'
              . join( ',', @nums )
              . '&amp;chds=0,'
              . $scale
              . '&amp;chs=750x300&chtt=Significant+Probes&amp;chco=ff0000,00ff00&amp;chdl='
              . uri_escape( "$currentEID1. " . $ht->{$currentEID1}->{title} )
              . '|'
              . uri_escape( "$currentEID2. " . $ht->{$currentEID2}->{title} );

            $out .= $js->define(
                {
                    venn =>
"<img alt=\"Venn Diagram\" src=\"http://chart.apis.google.com/chart?$qstring\" />"
                },
                declare => 1
            );
        }
        case 3 {

            # draw three circles
            my @c;
            for ( $i = 1 ; $i < 8 ; $i++ ) {

                # replace undefined values with zeros
                push @c, ( defined( $h->{$i} ) ) ? $h->{$i}->{c} : 0;
            }
            my $ABC = $c[6];
            my $AB  = $c[2] + $ABC;
            my $AC  = $c[4] + $ABC;
            my $BC  = $c[5] + $ABC;
            my ( $A, $B, $C ) = ( $hc{0}, $hc{1}, $hc{2} );

            my $chart_title =
              ( count_gtzero( $A, $B, $C ) > 2 )
              ? 'Significant+Probes+(Approx.)'
              : 'Significant+Probes';

            #assert( $A == $c[0] + $c[2] + $c[4] + $ABC );
            #assert( $B == $c[1] + $c[2] + $c[5] + $ABC );
            #assert( $C == $c[3] + $c[4] + $c[5] + $ABC );

            my ( $currentSTID1, $currentEID1 ) = split( /\|/, $eids[0] );
            my ( $currentSTID2, $currentEID2 ) = split( /\|/, $eids[1] );
            my ( $currentSTID3, $currentEID3 ) = split( /\|/, $eids[2] );

            # scale must be equal to the area of the largest circle
            my $scale = max( $A, $B, $C );
            my @nums = ( $A, $B, $C, $AB, $AC, $BC, $ABC );
            my $qstring =
                'cht=v&amp;chd=t:'
              . join( ',', @nums )
              . '&amp;chds=0,'
              . $scale
              . "&amp;chs=750x300&chtt=$chart_title&amp;chco=ff0000,00ff00,0000ff&amp;chdl="
              . uri_escape(
                sprintf( '%d. %s', $currentEID1, $ht->{$currentEID1}->{title} )
              )
              . '|'
              . uri_escape(
                sprintf( '%d. %s', $currentEID2, $ht->{$currentEID2}->{title} )
              )
              . '|'
              . uri_escape(
                sprintf( '%d. %s', $currentEID3, $ht->{$currentEID3}->{title} )
              );

            $out .= $js->define(
                {
                    venn =>
"<img alt=\"Venn Diagram\" src=\"http://chart.apis.google.com/chart?$qstring\" />"
                },
                declare => 1
            );
        }
        else {
            $out .= $js->define(
                {
                    venn => ''
                },
                declare => 1
            );
        }
    }

    # Summary table -------------------------------------
    my @tmpArray;
    for ( $i = 0 ; $i < @eids ; $i++ ) {
        my ( $currentSTID, $currentEID ) = split( /\|/, $eids[$i] );

        my $j = 0;
        push @tmpArray,
          +{
            map { $j++ => $_ } (
                $true_eids[$i], $ht->{$currentEID}->{title},
                $fcs[$i],       $pvals[$i],
                $hc{$i}
            )
          };
    }

    $out .= $js->define(
        {
            rep_count => $rep_count,
            eid       => join( ',', @eids ),
            rev       => join( ',', @reverses ),
            fc        => join( ',', @fcs ),
            pval      => join( ',', @pvals ),
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
        },
        declare => 1
    );

    # TFS breakdown table ------------------------------
    my $tfs_defs =
"{key:\"0\", sortable:true, resizeable:false, label:\"FS\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},\n";
    my $tfs_response_fields = "{key:\"0\", parser:\"number\"},\n";
    for ( $i = 1 ; $i <= @true_eids ; $i++ ) {
        my $true_eid = $true_eids[ $i - 1 ];
        $tfs_defs .=
"{key:\"$i\", sortable:true, resizeable:false, label:\"#$true_eid\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},\n";
        $tfs_response_fields .= "{key:\"$i\"},\n";
    }
    $tfs_defs .=
"{key:\"$i\", sortable:true, resizeable:true, label:\"Probe Count\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},
{key:\""
      . ( $i + 1 )
      . "\", sortable:false, resizeable:true, label:\"View probes\", formatter:\"formatDownload\"}\n";
    $tfs_response_fields .= "{key:\"$i\", parser:\"number\"},
{key:\"" . ( $i + 1 ) . "\", parser:\"number\"}\n";

    my @tfsBreakdown;
    foreach my $key ( sort { $h->{$b}->{fs} <=> $h->{$a}->{fs} } keys %$h ) {

        # numerical sort on hash value
        push @tfsBreakdown,
          {
            0 => $key,
            (
                map { $_ => ( 1 << ( $_ - 1 ) & $h->{$key}->{fs} ) ? 'x' : '' }
                  1 .. $exp_count
            ),
            ( $exp_count + 1 ) => $h->{$key}->{c}
          };
    }
    $out .= $js->define(
        {
            tfs => {
                caption =>
'Probes grouped by significance in different experiment combinations',
                records => \@tfsBreakdown
            }
        },
        declare => 1
      )
      . '

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
        elCell.innerHTML = "<input class=\"plaintext\" type=\"submit\" name=\"get\" value=\"TFS: " + fs + "\" />&nbsp;&nbsp;&nbsp;<input class=\"plaintext\" type=\"submit\" name=\"CSV\" value=\"(TFS: " + fs + " CSV)\" />";
    }
    Dom.get("tfs_caption").innerHTML = tfs.caption;
    Dom.get("tfs_all_dt").innerHTML = "View data for '
      . $rep_count . ' probes:";
    Dom.get("tfs_all_dd").innerHTML = "<input type=\"submit\" name=\"get\" class=\"plaintext\" value=\"HTML-formatted\" /><span class=\"separator\"> / </span><input type=\"submit\" class=\"plaintext\" name=\"CSV\" value=\"CSV-formatted\" />";
    var tfs_table_defs = [
' . $tfs_defs . '
    ];
    var tfs_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 50 
        })
    };
    var tfs_data = new YAHOO.util.DataSource(tfs.records);
    tfs_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    tfs_data.responseSchema = {
        fields: [' . $tfs_response_fields . ']
    };
    var tfs_table = new YAHOO.widget.DataTable("tfs_table", tfs_table_defs, tfs_data, tfs_config);
});
';
    return $out;
}

#===  FUNCTION  ================================================================
#         NAME:  getResultsHTML
#      PURPOSE:  Get HTML for result display
#   PARAMETERS:  $q - CGI.pm object
#                $action - action to be performed on results (DOWNLOADTFS)
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getResultsHTML {
    my ($self) = @_;

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

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

use Switch;
use URI::Escape;
use JSON::XS;
use Tie::IxHash;
use SGX::Debug qw/assert/;
use SGX::FindProbes;
use List::Util qw/max/;

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
    # This is the constructor
    my ($class, %param) = @_;

    my $self = {
        _dbh            => $param{dbh},
        _cgi        => $param{cgi},
        _UserSession    => $param{user_session},
        _FormAction  => $param{form_action},
        _SubmitAction => $param{submit_action}
    };

    # find out what the current project is set to
    if (defined($self->{_UserSession})) {
        $self->{_WorkingProject} =
            $self->{_UserSession}->{session_cookie}->{curr_proj};
        $self->{_WorkingProjectName} =
            $self->{_UserSession}->{session_cookie}->{proj_name};
        $self->{_UserFullName} =
            $self->{_UserSession}->{session_cookie}->{full_name};
    }

    bless $self, $class;
    return $self;
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
sub getFormJS
{
    my $self = shift;
    my $s = $self->{_UserSession};
    my $dbh = $self->{_dbh};

    # find out what the current project is set to
    my $curr_proj = $s->{session_cookie}->{curr_proj};

    # get a list of platforms and cutoff values
    my $query_text;
    my @query_params;
    if (!defined($curr_proj) || $curr_proj eq '') {
        # current project not set or set to 'All Projets'
        $query_text = qq{SELECT pid, pname, def_p_cutoff, def_f_cutoff FROM platform};
    } else {
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
    my $sth = $dbh->prepare($query_text);
    my $rowcount = $sth->execute(@query_params);
    assert($rowcount);

    ### populate a Javascript hash with the content of the platform recordset
    my %json_platform;
    while (my @row = $sth->fetchrow_array) {
        # format:
        # 0 - platform id => [
        #   1 - platform name
        #   2 - P-value cutoff
        #   3 - fold-change cutoff 
        # ];
        $json_platform{$row[0]} = [ $row[1], $row[2], $row[3] ];
    }
    $sth->finish;

    # get a list of studies
    if (!defined($curr_proj) || $curr_proj eq '') {
        # current project not set or set to 'All Projects'
        $sth = $dbh->prepare(qq{select stid, description, pid from study});
        $rowcount = $sth->execute();
    } else {
        # current project is set
        $sth = $dbh->prepare(qq{select stid, description, pid from study RIGHT JOIN ProjectStudy USING(stid) WHERE prid=? group by stid});
        $rowcount = $sth->execute($curr_proj);
    }
    assert($rowcount);

    ### populate a Javascript hash with the content of the study recordset
    my %json_study;
    while (my @row = $sth->fetchrow_array) {
        # format:
        # study_id => [
        #   0 - study description
        #   1 - sample 1 name
        #   2 - sample 2 name
        #   3 - platform id
        # ];
        $json_study{$row[0]} = [$row[1], {}, {}, $row[2] ];
    }
    $sth->finish;

    # get a list of all experiments
    if (!defined($curr_proj) || $curr_proj eq '') {
        $sth = $dbh->prepare(<<"END_EXP_QUERY");
select stid, eid, experiment.sample2 as s2_desc, experiment.sample1 as s1_desc 
from study 
inner join StudyExperiment USING(stid)
inner join experiment using(eid)
GROUP BY eid

END_EXP_QUERY
        $rowcount = $sth->execute()
    } else {
        $sth = $dbh->prepare(<<"END_EXP_QUERY");
select stid, eid, experiment.sample2 as s2_desc, experiment.sample1 as s1_desc 
from experiment
inner join StudyExperiment USING(eid)
inner join study using(stid)
inner join ProjectStudy USING(stid)
WHERE prid = ?
GROUP BY eid

END_EXP_QUERY
        $rowcount = $sth->execute($curr_proj)
    }
    assert($rowcount);

    ### populate the Javascript hash with the content of the experiment recordset
    while (my @row = $sth->fetchrow_array) {
        $json_study{$row[0]}->[1]->{$row[1]} = $row[2];
        $json_study{$row[0]}->[2]->{$row[1]} = $row[3];
    }
    $sth->finish;

    return sprintf(<<"END_form_compareExperiments_js",
var form = "%s";
var platform = %s;
var study = %s;
END_form_compareExperiments_js
        $self->{_FormAction},
        encode_json(\%json_platform),
        encode_json(\%json_study)
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
    my ($q, $form_action, $submit_action) = @_;

    my %gene_dropdown;
    my $gene_dropdown_t = tie(%gene_dropdown, 'Tie::IxHash',
        'gene'=>'Gene Symbols',
        'accnum'=>'Accession Numbers',
        'probe'=>'Probes'
    );
    my %match_dropdown;
    my $match_dropdown_t = tie(%match_dropdown, 'Tie::IxHash',
        'full'=>'Full Word',
        'prefix'=>'Prefix',
        'part'=>'Part of the Word / Regular Expression*'
    );

    return 
    $q->h2('Compare Experiments'),
    $q->dl(
        $q->dt('Add experiment from platform:'),
        $q->dd($q->popup_menu(-name=>'platform', -id=>'platform'),
            $q->span({-class=>'separator'},' : '),
            $q->button(
                -value=>'Add experiment',
                -class=>'plaintext',
                -id=>'add_experiment'
            )
        )
    ),
    $q->start_form(
            -method=>'POST',
            -id=>$form_action,
            -action=>$q->url(absolute=>1).'?a='.$submit_action
    ),
    $q->dl(
        $q->dt($q->label({-for=>'chkAllProbes'},'Include all probes in output:')),
        $q->dd(
            $q->checkbox(-name=>'chkAllProbes',-id=>'chkAllProbes',-value=>'1',-label=>''),
            $q->p({-style=>'color:#777;'}, 'Probes without a TFS will be labeled \'TFS 0\'')
        ),
        $q->dt('Filter on:'),
        $q->dd({-id=>'geneFilter'}, '')
    ),
    $q->div({-id=>'filterList', -style=>'display:none;'},
        $q->h3('Filter on the following terms:'),
        $q->dl(
            $q->dt($q->label({-for=>'search_terms'}, 'Search term(s):')),
            $q->dd($q->textarea(-rows=>10, -columns=>50, -tabindex=>1, -name=>'search_terms', -id=>'search_terms')),
        )
    ),
    $q->div({-id=>'filterUpload',-style=>'display:none;'},
        $q->h3('Filter on uploaded file:'),
        $q->dl(
            $q->dt($q->label({-for=>'upload_file'},'Upload File:')),
            $q->dd(
                $q->filefield(-name=>'upload_file',-id=>'upload_file'),
                $q->p({-style=>'color:#777;'},
                    'File must be in plain-text format with one search term per line')
            )
        )
    ),
    $q->dl({-id=>'filterAny',-style=>'display:none;'},
        $q->dt('Terms are:'),
        $q->dd($q->popup_menu(
                   -name=>'type',
                   -values=>[keys %gene_dropdown],
                   -default=>'gene',
                   -labels=>\%gene_dropdown
               )
        ),
        $q->dt('Patterns to match:'),
        $q->dd($q->radio_group(
                      -tabindex=>2, 
                      -name=>'match', 
                      -values=>[keys %match_dropdown], 
                      -default=>'full', 
                      -linebreak=>'true', 
                      -labels=>\%match_dropdown
              )
        )
    ),
    $q->dl(
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(-name=>'submit',-class=>'css3button',-value=>'Compare'),
            $q->hidden(-name=>'a',-value=>$submit_action, -override=>1)
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
sub getResultsJS
{
    my $self = shift;
    my $q = $self->{_cgi};
    my $s = $self->{_UserSession};
    my $dbh = $self->{_dbh};

    #This flag tells us whether or not to ignore the thresholds.
    my $allProbes         = '';
    $allProbes             = ($q->param('chkAllProbes')) if defined($q->param('chkAllProbes'));
    
    my $searchFilter    = '';
    $searchFilter         = ($q->param('chkUseGeneList')) if defined($q->param('chkUseGeneList'));

    my $filterType        = '';
    $filterType         = ($q->param('geneFilter')) if defined($q->param('geneFilter'));    
    
    my $probeListQuery    = '';
    my $probeList        = '';
    
    my $curr_proj = $s->{session_cookie}->{curr_proj};

    if($q->param('upload_file'))
    {
        # if $q->param('upload_file') is not set, all other fields in Upload File
        # subsection don't matter
        assert(!$q->param('search_terms'));
        my $findProbes = SGX::FindProbes->new(dbh => $dbh, cgi => $q);
        $findProbes->{_WorkingProject} = $curr_proj;

        # parse uploaded file (highly likely to fail!)
        my $fh = $q->upload('upload_file');

        # call to createInsideTableQueryFromFile() is followed by
        # loadProbeReporterData() which uses _ProbeReporterQuery (similar to
        # query called by build_ProbeQuery()
        eval { $findProbes->createInsideTableQueryFromFile($fh); } 
        or close($fh) and croak $@;

        $findProbes->loadProbeReporterData($findProbes->getQueryTerms());

        # get list of probe record ids (rid)
        $probeList     = $findProbes->getProbeList();
        $probeListQuery    = " WHERE rid IN ($probeList) ";
    }
    elsif($q->param('search_terms'))
    {
        # if $q->param('search_terms') is not set, all other fields in Filter List
        # subsection don't matter
        assert(!$q->param('upload_file'));
        my $findProbes = SGX::FindProbes->new(dbh => $dbh, cgi => $q);
        $findProbes->{_WorkingProject} = $curr_proj;

        $findProbes->createInsideTableQuery(); # followed by build_ProbeQuery
        $findProbes->build_ProbeQuery(extra_fields => 0);
        $findProbes->loadProbeData($findProbes->getQueryTerms);
        $findProbes->setProbeList();

        # get list of probe record ids (rid)
        $probeList     = $findProbes->getProbeList();
        $probeListQuery    = " WHERE rid IN ($probeList) ";
    }

    #If we are filtering, generate the SQL statement for the rid's.    
    my $thresholdQuery    = '';
    my $query_titles     = '';
    my $query_fs         = 'SELECT fs, COUNT(*) as c FROM (SELECT BIT_OR(flag) AS fs FROM (';
    my $query_fs_body     = '';
    my (@eids, @reverses, @fcs, @pvals);

    my $i;
    for ($i = 1; defined($q->param("eid_$i")); $i++) 
    {
        my ($eid, $fc, $pval) = ($q->param("eid_$i"), $q->param("fc_$i"), $q->param("pval_$i"));
        my $reverse = (defined($q->param("reverse_$i"))) ? 1 : 0;
        
        #Prepare the four arrays that will be used to display data
        push @eids,     $eid; 
        push @reverses, $reverse; 
        push @fcs,         $fc; 
        push @pvals,     $pval;

        my @IDSplit = split(/\|/,$eid);

        my $currentSTID = $IDSplit[0];
        my $currentEID = $IDSplit[1];        
        
        #Flagsum breakdown query
        my $flag = 1 << $i - 1;

        #This is the normal threshold.
        $thresholdQuery    = " AND pvalue < $pval AND ABS(foldchange)  > $fc ";

        $query_fs_body .= "SELECT rid, $flag AS flag FROM microarray WHERE eid=$currentEID $thresholdQuery UNION ALL ";
        
        #This is part of the query when we are including all probes.
        if($allProbes eq "1")
        {
            $query_fs_body .= "SELECT rid, 0 AS flag FROM microarray WHERE eid=$currentEID AND rid NOT IN (SELECT RID FROM microarray WHERE eid=$currentEID $thresholdQuery) UNION ALL ";
        }

        # account for sample order when building title query
        my $title = ($reverse) ? "experiment.sample1, ' / ', experiment.sample2" : "experiment.sample2, ' / ', experiment.sample1";
        
        $query_titles .= " SELECT eid, CONCAT(study.description, ': ', $title) AS title FROM experiment NATURAL JOIN StudyExperiment NATURAL JOIN study WHERE eid=$currentEID AND StudyExperiment.stid=$currentSTID UNION ALL ";
    }

    my $exp_count = $i - 1;    # number of experiments being compared

    # strip trailing 'UNION ALL' plus any trailing white space
    $query_fs_body =~ s/UNION ALL\s*$//i;
    $query_fs = sprintf($query_fs, $exp_count) . $query_fs_body . ") AS d1 $probeListQuery GROUP BY rid) AS d2 GROUP BY fs";

    #Run the Flag Sum Query.
    my $sth_fs = $dbh->prepare(qq{$query_fs});
    my $rowcount_fs = $sth_fs->execute();
    my $h = $sth_fs->fetchall_hashref('fs');
    $sth_fs->finish;

    # strip trailing 'UNION ALL' plus any trailing white space
    $query_titles =~ s/UNION ALL\s*$//i;
    my $sth_titles = $dbh->prepare(qq{$query_titles});
    my $rowcount_titles = $sth_titles->execute();

    assert($rowcount_titles == $exp_count);
    my $ht = $sth_titles->fetchall_hashref('eid');
    $sth_titles->finish;

    my $rep_count = 0;
    my %hc;
    # initialize a hash using a slice:
    @hc{ 0 .. ($exp_count - 1) } = 0; #for ($i = 0; $i < $exp_count; $i++) { $hc{$i} = 0 }
    foreach my $value (values %$h) {
        for ($i = 0; $i < $exp_count; $i++) {
            # use of bitwise AND operator to test for bit presence
            $hc{$i} += $value->{c} if 1 << $i & $value->{fs};
        }
        $rep_count += $value->{c};
    }



    ### Draw a 750x300 area-proportional Venn diagram using Google API if $exp_count is (2,3)
    # http://code.google.com/apis/chart/types.html#venn
    # http://code.google.com/apis/chart/formats.html#data_scaling
    #
    my $out = '';
    switch ($exp_count) {
    case 2 {
        # draw two circles
        my @c;
        for ($i = 1; $i < 4; $i++) {
            # replace undefined values with zeros
            if (defined($h->{$i})) { push @c, $h->{$i}->{c} }
            else { push @c, 0 }
        }
        my $AB = $c[2];
        my $A = $hc{0}; 
        my $B = $hc{1}; 
        #assert(defined($A));
        #assert(defined($B));
        assert($A == $c[0] + $AB);
        assert($B == $c[1] + $AB);

        my @IDSplit1 = split(/\|/,$eids[0]);
        my @IDSplit2 = split(/\|/,$eids[1]);

        my $currentEID1 = $IDSplit1[1];        
        my $currentEID2 = $IDSplit2[1];

        my $scale = max($A, $B); # scale must be equal to the area of the largest circle
        my @nums = ($A, $B, 0, $AB);
        my $qstring = 'cht=v&amp;chd=t:'.join(',', @nums).'&amp;chds=0,'.$scale.
            '&amp;chs=750x300&chtt=Significant+Probes&amp;chco=ff0000,00ff00&amp;chdl='.
            uri_escape('1. '.$ht->{$currentEID1}->{title}).'|'.
            uri_escape('2. '.$ht->{$currentEID2}->{title});

        $out .= "var venn = '<img src=\"http://chart.apis.google.com/chart?$qstring\" />';\n";
    }
    case 3 {
        # draw three circles
        my @c;
        for ($i = 1; $i < 8; $i++) {
            # replace undefined values with zeros
            if (defined($h->{$i})) { push @c, $h->{$i}->{c} }
            else { push @c, 0 }
        }
        my $ABC = $c[6];
        my $AB = $c[2] + $ABC;
        my $AC = $c[4] + $ABC;
        my $BC = $c[5] + $ABC;
        my $A = $hc{0};
        my $B = $hc{1};
        my $C = $hc{2};
        assert($A == $c[0] + $c[2] + $c[4] + $ABC);
        assert($B == $c[1] + $c[2] + $c[5] + $ABC);
        assert($C == $c[3] + $c[4] + $c[5] + $ABC);

        my @IDSplit1 = split(/\|/,$eids[0]);
        my @IDSplit2 = split(/\|/,$eids[1]);
        my @IDSplit3 = split(/\|/,$eids[2]);

        my $currentEID1 = $IDSplit1[1];        
        my $currentEID2 = $IDSplit2[1];
        my $currentEID3 = $IDSplit3[1];

        my $scale = max($A, $B, $C); # scale must be equal to the area of the largest circle
        my @nums = ($A, $B, $C, $AB, $AC, $BC, $ABC);
        my $qstring = 'cht=v&amp;chd=t:'.join(',', @nums).'&amp;chds=0,'.$scale.
            '&amp;chs=750x300&chtt=Significant+Probes+(Approx.)&amp;chco=ff0000,00ff00,0000ff&amp;chdl='.
            uri_escape('1. '.$ht->{$currentEID1}->{title}).'|'.
            uri_escape('2. '.$ht->{$currentEID2}->{title}).'|'.
            uri_escape('3. '.$ht->{$currentEID3}->{title});

        $out .= "var venn = '<img src=\"http://chart.apis.google.com/chart?$qstring\" />';\n";
    }
    else {
        $out .= "var venn = '';\n";
    } }

    # Summary table -------------------------------------
$out .= '
var rep_count="'.$rep_count.'";
var eid="'.join(',',@eids).'";
var rev="'.join(',',@reverses).'";
var fc="'.join(',',@fcs).'";
var pval="'.join(',',@pvals).'";
var allProbes = "' . $allProbes . '";
var searchFilter = "' . $probeList . '";

var summary = {
caption: "Experiments compared",
records: [
';

    for ($i = 0; $i < @eids; $i++) 
    {
        my @IDSplit = split(/\|/,$eids[$i]);

        my $currentSTID = $IDSplit[0];
        my $currentEID = $IDSplit[1];        
        
        my $escapedTitle        = $ht->{$currentEID}->{title};
        $escapedTitle        =~ s/\\/\\\\/g;
        $escapedTitle        =~ s/"/\\\"/g;

        $out .= '{0:"'. ($i + 1) . '",1:"' . $escapedTitle . '",2:"' . $fcs[$i] . '",3:"' . $pvals[$i] . '",4:"'.$hc{$i} . "\"},\n";
    }
    $out =~ s/,\s*$//;      # strip trailing comma
    $out .= '
]};
';

    # TFS breakdown table ------------------------------

    $out .= '
var tfs = {
caption: "View data for reporters significant in unique experiment combinations",
records: [
';

    # numerical sort on hash value
    foreach my $key (sort {$h->{$b}->{fs} <=> $h->{$a}->{fs}} keys %$h) {
        $out .= '{0:"'.$key.'",';
        for ($i = 0; $i < $exp_count; $i++) {
            # use of bitwise AND operator to test for bit presence
            if (1 << $i & $h->{$key}->{fs})    { 
                $out .= ($i + 1).':"x",';
            } else {
                $out .= ($i + 1).':"",';
            }
        }
        $out .= ($i + 1).':"'.$h->{$key}->{c}."\"},\n";
    }
    $out =~ s/,\s*$//;      # strip trailing comma

    my $tfs_defs = "{key:\"0\", sortable:true, resizeable:false, label:\"FS\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},\n";
    my $tfs_response_fields = "{key:\"0\", parser:\"number\"},\n";
    for ($i = 1; $i <= $exp_count; $i++) {
        $tfs_defs .= "{key:\"$i\", sortable:true, resizeable:false, label:\"$i\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},\n";
        $tfs_response_fields .= "{key:\"$i\"},\n";
    }
    $tfs_defs .= "{key:\"$i\", sortable:true, resizeable:true, label:\"Reporters\", sortOptions:{defaultDir:YAHOO.widget.DataTable.CLASS_DESC}},
{key:\"".($i + 1)."\", sortable:false, resizeable:true, label:\"View probes\", formatter:\"formatDownload\"}\n";
    $tfs_response_fields .= "{key:\"$i\", parser:\"number\"},
{key:\"".($i + 1)."\", parser:\"number\"}\n";

    $out .= '
]};

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
        {key:"0", sortable:true, resizeable:false, label:"&nbsp;"},
        {key:"1", sortable:true, resizeable:true, label:"Experiment"},
        {key:"2", sortable:true, resizeable:false, label:"&#124;Fold Change&#124; &gt;"}, 
        {key:"3", sortable:true, resizeable:false, label:"P &lt;"},
        {key:"4", sortable:true, resizeable:false, label:"Reporters"}
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
    Dom.get("tfs_all_dt").innerHTML = "View probes significant in at least one experiment:";
    Dom.get("tfs_all_dd").innerHTML = "<input type=\"submit\" name=\"get\" class=\"plaintext\" value=\"'.$rep_count.' significant probes\" /> <span class=\"separator\">/</span><input type=\"submit\" class=\"plaintext\" name=\"CSV\" value=\"CSV-formatted\" />";
    var tfs_table_defs = [
'.$tfs_defs.'
    ];
    var tfs_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 50 
        })
    };
    var tfs_data = new YAHOO.util.DataSource(tfs.records);
    tfs_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    tfs_data.responseSchema = {
        fields: ['.$tfs_response_fields.']
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
    my ($q, $action) = @_;

    my %opts_dropdown;
    my $opts_dropdown_t = tie(%opts_dropdown, 'Tie::IxHash',
        '0'=>'Basic (ratios and p-value only)',
        '1'=>'Experiment data',
        '2'=>'Experiment data with annotations'
    );

    return 
        $q->div({-id=>'venn'},''),
        $q->h2({-id=>'summary_caption'},''),
        $q->div({-id=>'summary_table', -class=>'table_cont'},''),
        $q->start_form(
            -method=>'POST',
            -action=>$q->url(-absolute=>1) . "?a=" . $action,
            -target=>'_blank',
            -class=>'getTFS',
            -enctype=>'application/x-www-form-urlencoded'
        ),
        $q->hidden(-name=>'a',-value=>$action, -override=>1),
        $q->hidden(-name=>'eid', -id=>'eid'),
        $q->hidden(-name=>'rev', -id=>'rev'),
        $q->hidden(-name=>'fc', -id=>'fc'),
        $q->hidden(-name=>'pval', -id=>'pval'),
        $q->hidden(-name=>'allProbes', -id=>'allProbes'),
        $q->hidden(-name=>'searchFilter', -id=>'searchFilter'),
        $q->h2({-id=>'tfs_caption'},''),
        $q->dl(
            $q->dt('Data to display:'),
            $q->dd($q->popup_menu(
                    -name=>'opts',
                    -values=>[keys %opts_dropdown], 
                    -default=>'0',
                    -labels=>\%opts_dropdown
            )),
            $q->dt({-id=>'tfs_all_dt'}, "&nbsp;"),
            $q->dd({-id=>'tfs_all_dd'}, "&nbsp;")
        ),
        $q->div({-id=>'tfs_table', -class=>'table_cont'}, ''),
        $q->endform;
}

1;

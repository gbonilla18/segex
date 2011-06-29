#!/usr/bin/perl -w

use strict;
use warnings;
use CGI;
use Switch;

#use URI::Escape;
# debug includes
use Data::Dumper;
use SGX::Debug;

use SGX::Config;
use SGX::Util qw/label_format bounds/;
use SGX::User 0.07;    # user authentication, sessions and cookies

# dbi and sql statement to get the fold changes for all experiments based on the accnum annotation for this reporter

my $dbh = sgx_db_connect();
my $s   = SGX::User->new(
    dbh       => $dbh,
    expire_in => 3600,    # expire in 3600 seconds (1 hour)
    check_ip  => 1
);

$s->restore;              # restore old session if it exists

my $q         = new CGI;
my $reporter  = $q->param('reporter');
my $transform = $q->param('trans');

if ( $reporter eq '' ) {
    $s->commit;
    exit(0);
}

#$s->read_perm_cookie();
my $curr_proj = $s->{session_cookie}->{curr_proj};

if ( !$s->is_authorized('user') ) {

    #$s->commit;
    #print $q->header(-type=>'text/plain', -cookie=>$s->cookie_array());
    #print "not logged in";
    #exit(0);
}

$s->commit;

####################################################################
my $y_start;
my $sql_trans;
my $sql_cutoff;
my $ytitle_text;
my $middle_label;
switch ($transform) {
    case 'fold' {
        $y_start      = 1;
        $sql_trans    = 'if(foldchange>0,foldchange-1,foldchange+1)';
        $sql_cutoff   = '(def_f_cutoff-1)';
        $ytitle_text  = 'Fold Change';
        $middle_label = '&#177;1';
    }
    case 'ln' {
        $y_start    = 0;
        $sql_trans  = 'if(foldchange>0, log2(foldchange), log2(-1/foldchange))';
        $sql_cutoff = 'log2(def_f_cutoff)';
        $ytitle_text  = 'Log2 of Intensity Ratio';
        $middle_label = '0';
    }
    else {
        assert(0);
    }
}

####################################################################
my $sql_join_clause  = '';
my $sql_where_clause = '';
my @exec_array_title = ($reporter);
if ( defined($curr_proj) and $curr_proj ne '' ) {
    $sql_join_clause =
      'INNER JOIN study USING(pid) INNER JOIN ProjectStudy USING(stid)';
    $sql_where_clause = 'AND prid=?';
    push @exec_array_title, $curr_proj;
}

# Get the sequence name for the title
my $sth = $dbh->prepare(
    qq{
SELECT 
GROUP_CONCAT(DISTINCT IF(seqname IS NULL, '', seqname) SEPARATOR ', ') AS seqname, 
$sql_cutoff AS cutoff, 
def_p_cutoff AS cutoff_p 
FROM probe 
INNER JOIN platform USING(pid) $sql_join_clause
LEFT JOIN (annotates NATURAL JOIN gene) USING(rid)
WHERE reporter=? $sql_where_clause
GROUP BY probe.rid
}
);
my $rowcount = $sth->execute(@exec_array_title);

if ( $rowcount == 0 ) {
    warn "Probe $reporter does not exist in the database";
}
#elsif ($rowcount > 1) {
#    warn "More than one record found with reporter ID $reporter";
#}
my $result = $sth->fetchrow_arrayref;
$sth->finish;

my ( $seqname, $cutoff, $cutoff_p ) = @$result;

####################################################################
# Get the data
my $title_text  = "$seqname Differential Expression Reported by $reporter";
my $xtitle_text = 'Experiment';

my $sql_project_clause = '';
my @exec_array         = ($reporter);

if ( defined($curr_proj) and $curr_proj ne '' ) {
    $sql_project_clause = 'NATURAL JOIN ProjectStudy WHERE prid=?';
    push @exec_array, $curr_proj;
}

$sth = $dbh->prepare(
    qq{
SELECT 
experiment.eid,
CONCAT(GROUP_CONCAT(study.description SEPARATOR ', '), ': ', experiment.sample2, '/', experiment.sample1) AS label, 
$sql_trans as y, 
pvalue 
FROM microarray 
RIGHT JOIN (
    SELECT rid FROM probe WHERE reporter=?
) AS d3 ON microarray.rid=d3.rid 
NATURAL JOIN experiment 
NATURAL JOIN StudyExperiment 
NATURAL JOIN study 
$sql_project_clause
GROUP BY experiment.eid
ORDER BY experiment.eid ASC
}
);

$rowcount = $sth->execute(@exec_array);
exit() if $rowcount == 0;

my @exp_ids;
my @labels;
my @y;
my @pvalues;

while ( my $row = $sth->fetchrow_arrayref ) {
    push @exp_ids, $row->[0];
    push @labels,  $row->[1];
    push @y,       $row->[2];
    push @pvalues, $row->[3];
}

$sth->finish;
####################################################################

#Set particulars for graph
my $xl                   = 55;
my $yl                   = 24;
my $body_width           = 500;
my $body_height          = 300;
my $body_height_extended = 400;
my $longest_xlabel       = 550;
my $text_breath          = 6;     # pixels
my $text_fudge           = 4;     # fudge factor
my $text_fudge_inv       = 10;    # inverse fudge factor

#my $total_width = $xl + $body_width
my $total_width = $xl + $body_width + $longest_xlabel;
my $label_shift = $yl + $body_height + $text_breath + $text_fudge;

#my $total_height = $label_shift + $longest_xlabel;
my $total_height = $label_shift + 265;
my $golden_ratio =
  1.61803399;    # space between bars is wider than the bars by golden ratio
my $bar_width =
  $body_width / ( @y * ( 1 + $golden_ratio ) + $golden_ratio );    # bar width
my ( $min_data, $max_data ) = bounds( \@y );
$max_data = ( $max_data > $cutoff )  ? $max_data : $cutoff;
$min_data = ( $min_data < -$cutoff ) ? $min_data : -$cutoff;
my $spread = $max_data - $min_data;
assert( $spread > 0 );
my $body_prop = 0.9;
my $scale     = $body_prop * $body_height / $spread;
my $wspace    = ( 1 - $body_prop ) / 2 * $body_height;
my $yupper    = $wspace + $max_data * $scale;
my $ylower    = $body_height - $yupper;
my $xaxisy    = $yupper + $yl;
my $left_pos  = $xl - $text_breath;

my $xlabels       = '';
my $legend        = '';
my $vguides       = '';
my $datapoints    = '';
my $rw            = $golden_ratio * $bar_width;
my $wrw           = $bar_width + $rw;
my $left          = $xl + $rw;
my $vguides_shift = $left + $bar_width / 2;
my $text_left     = $vguides_shift + $text_fudge;

# legend
my $text_height = $text_fudge_inv + 2;
my $legend_left = $xl + $body_width + $text_fudge_inv;
my $legend_top  = $yl + $text_fudge_inv;
for ( my $i = 0 ; $i < @y ; $i++ ) {
    my ( $yvalue, $lab_class, $leg_class );
    if ( defined( $y[$i] ) ) {
        $lab_class = 'xAxisLabel';
        $leg_class = 'legendLabel';
        $yvalue    = $y[$i];
    }
    else {
        $lab_class = 'xAxisLabel xNALabel';
        $leg_class = 'legendLabel xNALabel';
        $yvalue    = 0;
    }
    my $top       = $xaxisy - $scale * $yvalue;

#$xlabels .= "<text x=\"$text_left\" y=\"$label_shift\" class=\"$lab_class\" transform=\"rotate(270 $text_left $label_shift)\">".$labels[$i]."</text>\n";
    $xlabels .=
        "<text x=\"$text_left\" y=\"$label_shift\" class=\"$lab_class\" transform=\"rotate(270 $text_left $label_shift)\">"
      . $exp_ids[$i]
      . "</text>\n";
    $legend .=
        "<text x=\"$legend_left\" y=\"$legend_top\" class=\"$leg_class\" >"
      . $exp_ids[$i] . '. '
      . $labels[$i]
      . "</text>\n";
    $vguides .=
      "<path d=\"M$vguides_shift $yl v$body_height\" class=\"vGuideLine\" />\n";
    my $fill_class;
    if ( defined( $pvalues[$i] ) ) {
        $fill_class = ( $pvalues[$i] < $cutoff_p ) ? 'fill2' : 'fill1';
    }
    else {
        $fill_class = 'fill3';
    }
    $datapoints .=
"<path d=\"M$left $xaxisy V$top h$bar_width V$xaxisy Z\" class=\"$fill_class\"/>\n";
    $text_left     += $wrw;
    $left          += $wrw;
    $legend_top    += $text_height;
    $vguides_shift += $wrw;
}

my $hguides = '';
my $ylabels = '';

# make sure we have at least around 4 labels
my $num_sep = label_format( $spread / 4 )
  ;   # round to one significant figure which then becomes either 1, 2, 5, or 10
my $split = 0;
if ( $body_height / ( $scale * $num_sep ) < 6 ) {

    # make sure we have at least around 6 gridlines
    $num_sep /= 2;
    $split = 1;
}
my $ysep      = $scale * $num_sep;
my $offset    = $ysep;
my $ylabel    = $y_start;
my $put_label = 0;
while ( $offset <= $yupper ) {
    $ylabel += $num_sep;
    my $real_offset = $xaxisy - $offset;
    my $text_offset = $real_offset + $text_fudge;
    if ($split) {
        if ($put_label) {
            $ylabels .=
"<text x=\"$left_pos\" y=\"$text_offset\" class=\"yAxisLabel\">$ylabel</text>\n";
            $put_label = 0;    # skip next time
        }
        else {
            $put_label = 1;    # do it next time
        }
    }
    else {
        $ylabels .=
"<text x=\"$left_pos\" y=\"$text_offset\" class=\"yAxisLabel\">$ylabel</text>\n";
    }
    $hguides .=
      "<path d=\"M$xl $real_offset h$body_width\" class=\"hGuideLine\"/>\n";
    $offset += $ysep;
}

$ylabel    = -$y_start;
$offset    = $ysep;
$put_label = 0;
while ( $offset <= $ylower ) {
    $ylabel -= $num_sep;
    my $real_offset = $xaxisy + $offset;
    my $text_offset = $real_offset + $text_fudge;
    if ($split) {
        if ($put_label) {
            $ylabels .=
"<text x=\"$left_pos\" y=\"$text_offset\" class=\"yAxisLabel\">$ylabel</text>\n";
            $put_label = 0;    # skip next time
        }
        else {
            $put_label = 1;    # do it next time
        }
    }
    else {
        $ylabels .=
"<text x=\"$left_pos\" y=\"$text_offset\" class=\"yAxisLabel\">$ylabel</text>\n";
    }
    $hguides .=
      "<path d=\"M$xl $real_offset h$body_width\" class=\"hGuideLine\"/>\n";
    $offset += $ysep;
}
$cutoff = $scale * $cutoff;
if ( $cutoff <= $yupper ) {
    my $real_offset = $xaxisy - $cutoff;
    $hguides .=
      "<path d=\"M$xl $real_offset h$body_width\" class=\"hThreshold\"/>\n";
}
if ( $cutoff <= $ylower ) {
    my $real_offset = $xaxisy + $cutoff;
    $hguides .=
      "<path d=\"M$xl $real_offset h$body_width\" class=\"hThreshold\"/>\n";
}
my $text_offset = $xaxisy + $text_fudge;
$ylabels .=
"<text x=\"$left_pos\" y=\"$text_offset\" class=\"yAxisLabel\">$middle_label</text>\n";

my $titlex  = $xl;
my $titley  = $yl / 2;
my $ytitlex = $text_fudge_inv;          # + $text_breath;
my $ytitley = $yl + $body_height / 2;

### main block ####################################
#
# not drawing the Y-axis anymore -- if needed, the SVG code to show it was:
# 	<path d="M$xl $yl v$body_height" id="yAxis"/>
# also not showing label for the X-axis. The SVG code was:
# 	<text x=\"$xtitlex\" y=\"$xtitley\" id=\"xAxisTitle\">$xtitle_text</text>
# and the Perl code to find xy coords was:
#	my $xtitlex = $xl + $body_width / 2;
#	my $xtitley = $total_height - $yl / 3;

print $q->header( -type => 'image/svg+xml', -cookie => $s->cookie_array() );

print qq{<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.0//EN"
	"http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd">
<svg width="$total_width" height="$total_height" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<defs>
<style type="text/css"><![CDATA[
#svgBackground{
	fill: #fff;
}
#graphBackground{
	fill: #f2f2f2;
}
#mainTitle{
	text-anchor: left;
	fill: #000;
	font-size: 14px;
	font-family: HelveticaNeue, Helvetica, Arial, sans-serif;
	font-weight: bold;
}
#xAxisTitle, #yAxisTitle {
	text-anchor: middle;
	fill: #000;
	font-size: 12px;
	font-family: HelveticaNeue, Helvetica, Arial, sans-serif;
}
#xAxis, #yAxis{
	fill: none;
	stroke: #000;
	stroke-width: 1px;
}
.hGuideLine, .vGuideLine {
	fill: none;
	stroke: #999;
	stroke-width: 0.2px;
}
.hThreshold {
	fill: none;
	stroke: #0f0;
	stroke-width: 1.5px;
}
.legendLabel, .xAxisLabel, .yAxisLabel, .xNALabel {
	fill: #000;
	font-size: 12px;
	font-family: HelveticaNeue, Helvetica, Arial, sans-serif;
	font-weight: normal;
}
.xAxisLabel, .yAxisLabel, .xNALabel {
	text-anchor: end;
}
.xNALabel {
	fill: #00f;
}
.fill1, .fill2, .fill3 {
	fill: #f00;
	fill-opacity: 0.25;
}
.fill2 {
	fill-opacity: 0.62;
}
.fill3 {
	fill: #00f;
}
]]></style>
</defs>

<!-- background fills -->
<rect x="0" y="0" width="$total_width" height="$total_height" id="svgBackground"/>
<rect x="$xl" y="$yl" width="$body_width" height="$body_height" id="graphBackground"/>
 
<!-- axes -->
<path d="M$xl $xaxisy h$body_width" id="xAxis"/>

$xlabels
$ylabels
$legend
 
$vguides
$hguides

$datapoints

<text x=\"$ytitlex\" y=\"$ytitley\" id=\"yAxisTitle\" transform=\"rotate(270 $ytitlex $ytitley)\">$ytitle_text</text>
<text x=\"$titlex\" y=\"$titley\" id=\"mainTitle\">$title_text</text>
 
</svg>
};

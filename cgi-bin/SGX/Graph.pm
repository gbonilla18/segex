package SGX::Graph;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

use List::Util qw/max min/;
use SGX::Util qw/car label_format/;

#===  CLASS METHOD  ============================================================
#        CLASS:  Graph
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
    my ( $dbh, $q, $s ) = @$self{qw/_dbh _cgi _UserSession/};

    my $reporter  = car $q->param('rid');
    my $transform = car $q->param('trans');
    my $curr_proj = car $q->param('proj');
    return unless defined $reporter;

    $self->{_reporter_name} = $q->param('reporter');

    my $sql_trans;
    my $sql_cutoff;

    my $y_start;
    my $ytitle_text;
    my $middle_label;

    if ( $transform eq 'Log Ratio' ) {
        $sql_trans  = 'if(foldchange>0, log2(foldchange), log2(-1/foldchange))';
        $sql_cutoff = 'log2(def_f_cutoff)';

        $ytitle_text  = 'Log2 of Normalized Ratio';
        $y_start      = 0;
        $middle_label = '0';
    }
    else {

        # default: $transform eq 'fold'
        $sql_trans  = 'if(foldchange>0,foldchange-1,foldchange+1)';
        $sql_cutoff = '(def_f_cutoff-1)';

        $ytitle_text  = 'Fold Change (Normalized Ratio)';
        $y_start      = 1;
        $middle_label = '&#177;1';
    }
    $self->{_meta} = [ $ytitle_text, $y_start, $middle_label ];
    ####################################################################
    my $sql_join_clause  = '';
    my $sql_where_clause = '';
    my @exec_array_title = ($reporter);

    # check if proj parameter is numeric
    if ( defined($curr_proj) and $curr_proj =~ m/^\d+$/ ) {
        $sql_join_clause =
          'INNER JOIN study USING(pid) INNER JOIN ProjectStudy USING(stid)';
        $sql_where_clause = 'AND prid=?';
        push @exec_array_title, $curr_proj;
    }

    # Get the sequence name for the title
    my $sql1 = <<"END_SQL1";
SELECT 
group_concat(if(gtype=1, gsymbol, NULL) separator ', ') AS 'Gene Symb.',
$sql_cutoff AS cutoff, 
def_p_cutoff AS cutoff_p 
FROM probe 
INNER JOIN platform USING(pid) $sql_join_clause
LEFT JOIN (ProbeGene NATURAL JOIN gene) USING(rid)
WHERE rid=? $sql_where_clause
GROUP BY probe.rid
END_SQL1

    my $sth1     = $dbh->prepare($sql1);
    my $rowcount = $sth1->execute(@exec_array_title);
    $self->{_scc} = $sth1->fetchrow_arrayref;
    $sth1->finish;

####################################################################
    # Get the data
    my $xtitle_text        = 'Experiment';
    my $sql_project_clause = 'WHERE response.rid=?';
    my @exec_array         = ($reporter);

    if ( defined($curr_proj) and $curr_proj =~ m/^\d+$/ ) {
        $sql_project_clause =
'NATURAL JOIN ProjectStudy WHERE response.rid=? AND ProjectStudy.prid=?';
        push @exec_array, $curr_proj;
    }

    my $sql2 = <<"END_SQL2";
SELECT 
experiment.eid,
CONCAT(GROUP_CONCAT(study.description SEPARATOR ', '), ': ', experiment.sample2, '/', experiment.sample1) AS label, 
$sql_trans as y, 
pvalue1
FROM response 
NATURAL JOIN experiment 
NATURAL JOIN StudyExperiment 
NATURAL JOIN study 
$sql_project_clause
GROUP BY experiment.eid
ORDER BY experiment.eid ASC
END_SQL2

    my $sth2 = $dbh->prepare($sql2);
    $rowcount = $sth2->execute(@exec_array);
    return if $rowcount < 1;

    my @exp_ids;
    my @labels;
    my @y;
    my @pvalues;

    while ( my $row = $sth2->fetchrow_arrayref ) {
        push @exp_ids, $row->[0];
        push @labels,  $row->[1];
        push @y,       $row->[2];
        push @pvalues, $row->[3];
    }
    $self->{_data} = [ \@exp_ids, \@labels, \@y, \@pvalues ];
    $sth2->finish;

    # this is a hack (temporary until we put content wrapping into
    # Strategy::Base): call body to send data to the client but do not do it
    # normal way (do not return true value).  normally we would just return 1
    # and let the default_body() be called by the main controller.
    $s->commit();
    print $q->header( -type => 'image/svg+xml', -cookie => $s->cookie_array() ),
      $self->default_body();

    exit;    # do not show body
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Graph
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {
    my $self          = shift;
    my $reporter_name = $self->{_reporter_name};
    my ( $exp_ids, $labels, $y, $pvalues ) = @{ $self->{_data} };
    my ( $ytitle_text, $y_start, $middle_label ) = @{ $self->{_meta} };
    my ( $seqname,     $cutoff,  $cutoff_p )     = @{ $self->{_scc} };

    $seqname = '' if not defined $seqname;
    my $title_text = "$seqname Differential Expression: Probe $reporter_name";

    #Set particulars for graph
    my $xl                   = 55;
    my $yl                   = 24;
    my $body_width           = 500;
    my $body_height          = 300;
    my $body_height_extended = 400;
    my $longest_xlabel       = 7 * max( map { length($_) } @$labels );
    my $text_breath          = 6;                                       # pixels
    my $text_fudge     = 4;     # fudge factor
    my $text_fudge_inv = 10;    # inverse fudge factor

    #my $total_width = $xl + $body_width
    my $total_width = $xl + $body_width + $longest_xlabel;
    my $label_shift = $yl + $body_height + $text_breath + $text_fudge;

    # space between bars is wider than the bars by golden ratio
    my $golden_ratio = 1.61803399;
    my $bar_width =
      $body_width / ( @$y * ( 1 + $golden_ratio ) + $golden_ratio );

    my $min_data = min( grep { defined } @$y ) || 0;
    my $max_data = max( grep { defined } @$y ) || 0;
    $max_data = $cutoff  if $max_data < $cutoff;
    $min_data = -$cutoff if $min_data > -$cutoff;

    my $spread    = $max_data - $min_data;
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
    my $left_off      = $xl + $rw;
    my $vguides_shift = $left_off + $bar_width / 2;
    my $text_left     = $vguides_shift + $text_fudge;

    # legend
    my $text_height = $text_fudge_inv + 2;
    my $legend_left = $xl + $body_width + $text_fudge_inv;
    my $legend_top  = $yl + $text_fudge_inv;
    for ( my $i = 0 ; $i < @$y ; $i++ ) {
        my ( $yvalue, $lab_class, $leg_class );
        if ( defined $y->[$i] ) {
            $lab_class = 'xAxisLabel';
            $leg_class = 'legendLabel';
            $yvalue    = $y->[$i];
        }
        else {
            $lab_class = 'xAxisLabel xNALabel';
            $leg_class = 'legendLabel legendNALabel';
            $yvalue    = 0;
        }
        my $top = $xaxisy - $scale * $yvalue;

#$xlabels .= "<text x=\"$text_left\" y=\"$label_shift\" class=\"$lab_class\" transform=\"rotate(270 $text_left $label_shift)\">".$labels[$i]."</text>\n";
        $xlabels .=
"<text x=\"$text_left\" y=\"$label_shift\" class=\"$lab_class\" transform=\"rotate(270 $text_left $label_shift)\">"
          . $exp_ids->[$i]
          . "</text>\n";
        $legend .=
            "<text x=\"$legend_left\" y=\"$legend_top\" class=\"$leg_class\" >"
          . $exp_ids->[$i] . '. '
          . $labels->[$i]
          . "</text>\n";
        $vguides .=
"<path d=\"M$vguides_shift $yl v$body_height\" class=\"vGuideLine\" />\n";
        my $fill_class =
            ( defined $pvalues->[$i] )
          ? ( $pvalues->[$i] < $cutoff_p ? 'fill2' : 'fill1' )
          : 'fill3';
        $datapoints .=
"<path d=\"M$left_off $xaxisy V$top h$bar_width V$xaxisy Z\" class=\"$fill_class\"/>\n";

        $text_left     += $wrw;
        $left_off      += $wrw;
        $legend_top    += $text_height;
        $vguides_shift += $wrw;
    }
    my $total_height = max( $label_shift, $legend_top ) + 50;

    my $hguides = '';
    my $ylabels = '';

    # Make sure we have at least around 4 labels. Round to one significant
    # figure which then becomes either 1, 2, 5, or 10
    my $num_sep = label_format( $spread / 4 );
    my $split   = 0;
    if ( $body_height / ( $scale * $num_sep ) < 6 ) {

        # make sure we have at least around 6 gridlines
        $num_sep /= 2;
        $split = 1;
    }

    my $ysep = $scale * $num_sep;

    #---------------------------------------------------------------------------
    for (
        my ( $put_label, $offset, $ylabel ) =
        ( 0, $ysep, $y_start + $num_sep ) ;
        $offset <= $yupper ;
        $offset += $ysep, $ylabel += $num_sep
      )
    {
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
    }

    #---------------------------------------------------------------------------
    for (
        my ( $put_label, $offset, $ylabel ) =
        ( 0, $ysep, -$y_start - $num_sep ) ;
        $offset <= $ylower ;
        $offset += $ysep, $ylabel -= $num_sep
      )
    {
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
    }

    #---------------------------------------------------------------------------

    $cutoff = $scale * $cutoff;

    $hguides .=
        "<path d=\"M$xl "
      . ( $xaxisy - $cutoff )
      . " h$body_width\" class=\"hThreshold\"/>\n"
      if $cutoff <= $yupper;

    $hguides .=
        "<path d=\"M$xl "
      . ( $xaxisy + $cutoff )
      . " h$body_width\" class=\"hThreshold\"/>\n"
      if $cutoff <= $ylower;

    my $text_offset = $xaxisy + $text_fudge;

    $ylabels .=
"<text x=\"$left_pos\" y=\"$text_offset\" class=\"yAxisLabel\">$middle_label</text>\n";

    my $titlex  = $xl;
    my $titley  = $yl / 2;
    my $ytitlex = $text_fudge_inv;          # + $text_breath;
    my $ytitley = $yl + $body_height / 2;

 #---------------------------------------------------------------------------
 #  Including CSS into SVG so that one could save and use the SVG as a
 #  stand-alone file.
 #
 # not drawing the Y-axis anymore -- if needed, the SVG code to show it was:
 #     <path d="M$xl $yl v$body_height" id="yAxis"/>
 # also not showing label for the X-axis. The SVG code was:
 #     <text x=\"$xtitlex\" y=\"$xtitley\" id=\"xAxisTitle\">$xtitle_text</text>
 # and the Perl code to find xy coords was:
 #    my $xtitlex = $xl + $body_width / 2;
 #    my $xtitley = $total_height - $yl / 3;
 #---------------------------------------------------------------------------
    return <<"END_SVG";
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.0//EN"
    "http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd">
<svg width="$total_width" height="$total_height" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
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
.legendLabel, .xAxisLabel, .yAxisLabel, .xNALabel, .legendNALabel {
    fill: #000;
    font-size: 12px;
    font-family: HelveticaNeue, Helvetica, Arial, sans-serif;
    font-weight: normal;
}
.xAxisLabel, .yAxisLabel, .xNALabel {
    text-anchor: end;
}
.xNALabel, .legendNALabel {
    fill: #bbb;
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
END_SVG
}

1;

__END__
#===============================================================================
#
#         FILE:  Graph.pm
#
#  DESCRIPTION:
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  10/13/2011 14:57:32
#     REVISION:  ---
#===============================================================================




=head1 NAME

SGX::FindProbes

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::FindProbes;

use strict;
use warnings;

use Switch;
use CGI::Carp;
use Tie::IxHash;
use Data::Dumper;
use File::Basename;
use JSON::XS;
use File::Temp;
use SGX::Abstract::Exception;
use List::Util qw/min/;
use SGX::Util qw/all_match/;
use SGX::Model::PlatformStudyExperiment;

use SGX::Util qw/trim/;
use SGX::Debug qw/assert/;

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
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

    my %type_dropdown;
    my $type_dropdown_t = tie(
        %type_dropdown, 'Tie::IxHash',
        'gene'   => 'Gene Symbols',
        'accnum' => 'Accession Numbers',
        'probe'  => 'Probes'
    );
    my %match_dropdown;
    my $match_dropdown_t = tie(
        %match_dropdown, 'Tie::IxHash',
        'full'   => 'Full Word',
        'prefix' => 'Prefix',
        'part'   => 'Part of the Word / Regular Expression'
    );

    my $self = {
        _dbh         => $dbh,
        _cgi         => $q,
        _UserSession => $s,
        _js_src_yui  => $js_src_yui,
        _js_src_code => $js_src_code,

        _typeDesc  => \%type_dropdown,
        _matchDesc => \%match_dropdown,

        _ProbeHash               => undef,
        _Names                   => undef,
        _ProbeCount              => undef,
        _ProbeExperimentHash     => '',
        _FullExperimentData      => '',
        _InsideTableQuery        => '',
        _SearchItems             => '',
        _ProbeQuery              => '',
        _ExperimentListHash      => '',
        _ExperimentStudyListHash => '',
        _ExperimentNameListHash  => '',
        _ExperimentDataQuery     => undef,
    };

#Probe ID, Accession Number, Gene Name, Probe Sequence, {Ratio,FC,P-Val,Intensity1,Intensity2}

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
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
        case 'Search' {
            return unless $s->is_authorized('user');
            push @$js_src_yui,
              (
                'yahoo-dom-event/yahoo-dom-event.js',
                'connection/connection-min.js',
                'dragdrop/dragdrop-min.js',
                'container/container-min.js',
                'element/element-min.js',
                'datasource/datasource-min.js',
                'paginator/paginator-min.js',
                'datatable/datatable-min.js',
                'selector/selector-min.js'
              );
            $self->init();
            $self->getSessionOverrideCGI();
            push @$js_src_code, { -code => $self->findProbes_js($s) };
            push @$js_src_code, { -src  => 'FindProbes.js' };
        }
        else {
            return unless $s->is_authorized('user');
            $self->getSessionOverrideCGI();
            push @$js_src_code, { -src => 'FormFindProbes.js' };
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

    my ( $q, $s ) = @$self{qw{_cgi _UserSession}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    switch ($action) {
        case 'Search' {
            print $self->getResultTableHTML();
        }
        else {

            # default action: show form
            print $self->getFormHTML();
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my ( $self, $fh ) = @_;

    my $q = $self->{_cgi};

    my $match =
      ( defined $q->param('match') )
      ? $q->param('match')
      : 'full';

    my @textSplit;

    if ( defined $fh ) {
        my @lines = split(
            /\r\n|\n|\r/,
            do { local $/ = <$fh> }
        );
        my $csv_in =
          Text::CSV->new( { sep_char => "\t", allow_whitespace => 1 } );

        # Generate a custom function that matches all members of an array to see
        # if they all are empty strings.
        my $is_empty = all_match( qr/^$/, ignore_undef => 1 );
        while ( $csv_in->parse( shift @lines ) ) {

            # grab first field of each row
            my @fields = $csv_in->fields();
            my $term   = shift @fields;
            next if $is_empty->($term);
            push @textSplit, $term;
        }

        # check for errors
        if ( my $error = $csv_in->error_diag() ) {
            SGX::Abstract::Exception::User->throw( error => $error );
        }
    }
    else {

        #Split the input on commas and spaces
        my $text = $q->param('terms');
        @textSplit = split( /[,\s]+/, trim($text) );
    }

    return $self->_setSearchPredicate( $match, \@textSplit );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  getSessionOverrideCGI
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Gets full user name from session and full project name from CGI
#                parameters or session in that order. Also sets project id.
#       THROWS:  SGX::Abstract::Exception::Internal, Class::Exception::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getSessionOverrideCGI {
    my ($self) = @_;
    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};

    # For user name, just look it up from the session
    $self->{_UserFullName} =
      ( defined $s )
      ? $s->{session_cookie}->{full_name}
      : '';

    # :TRICKY:06/28/2011 13:47:09:es: We implement the following behavior: if,
    # in the URI option string, "proj" is set to some value (e.g. "proj=32") or
    # to an empty string (e.g. "proj="), we set the data field _WorkingProject
    # to that value; if the "proj" option is missing from the URI, we use the
    # value of "curr_proj" from session data. This allows us to have all
    # portions of the data accessible via a REST-style interface regardless of
    # current user preferences.
    if ( defined( my $cgi_proj = $q->param('proj') ) ) {
        $self->{_WorkingProject} = $cgi_proj;
        if ( $cgi_proj ne '' ) {

            # now need to obtain project name from the database
            my $sth =
              $dbh->prepare(qq{SELECT prname FROM project WHERE prid=?});
            my $rc = $sth->execute($cgi_proj);
            if ( $rc == 1 ) {

                # project exists in the database
                $self->{_WorkingProject} = $cgi_proj;
                ( $self->{_WorkingProjectName} ) = $sth->fetchrow_array;
            }
            elsif ( $rc < 1 ) {

                # project doesn't exist in the database
                $self->{_WorkingProject}     = '';
                $self->{_WorkingProjectName} = '';
            }
            else {
                SGX::Abstract::Exception::Internal->throw( error =>
"More than one result returned where unique was expected\n"
                );
            }
            $sth->finish;
        }
        else {
            $self->{_WorkingProjectName} = '';
        }
    }
    elsif ( defined $s ) {
        $self->{_WorkingProject}     = $s->{session_cookie}->{curr_proj};
        $self->{_WorkingProjectName} = $s->{session_cookie}->{proj_name};
    }
    else {
        $self->{_WorkingProject}     = '';
        $self->{_WorkingProjectName} = '';
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  _setSearchPredicate
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _setSearchPredicate {
    my ( $self, $match, $items ) = @_;

    my $qtext;
    my $predicate;

    switch ($match) {
        case 'full' {
            $predicate = 'IN (' . join( ',', map { '?' } @$items ) . ')';
            $qtext = [@$items];
        }
        case 'prefix' {
            $predicate = 'REGEXP ?';
            $qtext = [ join( '|', map { "^$_" } @$items ) ];
        }
        case 'part' {
            $predicate = 'REGEXP ?';
            $qtext = [ join( '|', @$items ) ];
        }
        else { croak "Invalid match value $match" }
    }

    $self->{_Predicate}   = $predicate;
    $self->{_SearchItems} = $qtext;
    return 1;
}
#######################################################################################

sub build_ExperimentDataQuery {

    # :TODO:07/24/2011 10:56:30:es: Move this function to a separate
    # class in SGX::Model namespace.
    my $self = shift;
    my $whereSQL;
    my $curr_proj = $self->{_WorkingProject};
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj = $self->{_dbh}->quote($curr_proj);
        $whereSQL  = <<"END_whereSQL";
INNER JOIN ProjectStudy USING(stid)
WHERE prid=$curr_proj AND rid=?
END_whereSQL
    }
    else {
        $whereSQL = 'WHERE rid=?';
    }
    $self->{_ExperimentDataQuery} = <<"END_ExperimentDataQuery";
SELECT
    experiment.eid, 
    microarray.ratio,
    microarray.foldchange,
    microarray.pvalue,
    microarray.intensity1,
    microarray.intensity2,
    CONCAT(
        GROUP_CONCAT(study.description SEPARATOR ','), ': ', 
        experiment.sample2, '/', experiment.sample1
    ) AS 'Name',
    GROUP_CONCAT(study.stid SEPARATOR ','),
    study.pid
FROM microarray 
INNER JOIN experiment USING(eid)
INNER JOIN StudyExperiment USING(eid)
INNER JOIN study USING(stid)
$whereSQL
GROUP BY experiment.eid
ORDER BY experiment.eid ASC
END_ExperimentDataQuery

    return 1;
}

#######################################################################################
# Get a list of the probes here so that we can get all experiment data for each
# probe in another query.
#######################################################################################
sub loadProbeData {
    my ($self) = @_;

    my $dbh         = $self->{_dbh};
    my $searchItems = $self->{_SearchItems};
    my $sth         = $dbh->prepare( $self->{_ProbeQuery} );
    my $rc          = $sth->execute( @$searchItems, @$searchItems );
    $self->{_ProbeCount} = $rc;

    # :TRICKY:07/24/2011 12:27:32:es: accessing NAME array will fail if is done
    # after any data were fetched. The line below splices off all
    # elements of the NAME array but the first two.

    $self->{_Names} =
      [ splice( @{ $sth->{NAME} }, min( 2, scalar( @{ $sth->{NAME} } ) ) ) ];
    my $result = $sth->fetchall_arrayref;

    $sth->finish;

    # From each row in the result, create a key-value pair such that the first
    # column becomes the key and the rest of the columns are sliced off into an
    # anonymous array.
    $self->{_ProbeHash} = +{ map { ( shift @$_ ) => $_ } @$result };

    return 1;
}

#######################################################################################
#For each probe in the list get all the experiment data.
#######################################################################################
sub loadExperimentData {
    my $self                 = shift;
    my $experimentDataString = '';

    $self->{_ProbeExperimentHash}     = {};
    $self->{_ExperimentListHash}      = {};
    $self->{_ExperimentStudyListHash} = {};
    $self->{_ExperimentNameListHash}  = {};

#Grab the format for the output from the form.
#$transform = (defined($self->{_cgi}->param('trans'))) ? $self->{_cgi}->param('trans') : '';
#Build SQL statement based on desired output type.
#my $sql_trans                    = '';
#switch ($transform)
#{
#    case 'fold' {
#        $sql_trans = 'if(foldchange>0,foldchange-1,foldchange+1)';
#    }
#    case 'ln' {
#        $sql_trans = 'if(foldchange>0, log2(foldchange), log2(-1/foldchange))';
#    }
#    else  {
#        $sql_trans = '';
#    }
#}

    $self->build_ExperimentDataQuery();
    my $sth = $self->{_dbh}->prepare( $self->{_ExperimentDataQuery} );

    foreach my $key ( keys %{ $self->{_ProbeHash} } ) {
        my $rc  = $sth->execute($key);
        my $tmp = $sth->fetchall_arrayref;

        #We use a temp hash that gets added to the _ProbeExperimentHash.
        my %tempHash;

        #For each experiment
        foreach (@$tmp) {

            # EID => [ratio, foldchange, pvalue, intensity1, intensity2]
            $tempHash{ $_->[0] } = [ @$_[ 1 .. 5 ] ];

            # EID => PID
            $self->{_ExperimentListHash}->{ $_->[0] } = $_->[8];

            # [EID, STID] => 1
            $self->{_ExperimentStudyListHash}->{ $_->[0] . '|' . $_->[7] } = 1;

            # EID => Name
            $self->{_ExperimentNameListHash}->{ $_->[0] } = $_->[6];

        }

        #Add the hash of experiment data to the hash of reporters.
        $self->{_ProbeExperimentHash}->{$key} = \%tempHash;

    }
    $sth->finish;
    return;
}

#######################################################################################
#Print the data from the hashes into a CSV file.
#######################################################################################
sub printFindProbeCSV {
    my $self       = shift;
    my $currentPID = 0;

    #Clear our headers so all we get back is the CSV file.
    $self->{_UserSession}->commit() if defined( $self->{_UserSession} );
    my $cookie_array =
      ( defined $self->{_UserSession} )
      ? $self->{_UserSession}->cookie_array()
      : [];
    print $self->{_cgi}->header(
        -type       => 'text/csv',
        -attachment => 'results.csv',
        -cookie     => $cookie_array
    );

    #Print a line to tell us what report this is.
    my $workingProjectText =
      ( defined( $self->{_WorkingProjectName} ) )
      ? $self->{_WorkingProjectName}
      : 'N/A';

    my $generatedByText =
      ( defined( $self->{_UserFullName} ) )
      ? $self->{_UserFullName}
      : '';

    print 'Find Probes Report,' . localtime() . "\n";
    print "Generated by,$generatedByText\n";
    print "Working Project,$workingProjectText\n\n";

    # initialize platform model
    my $platforms =
      SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} );
    $platforms->init( platforms => 1 );

    # Sort the hash so the PID's are together.
    foreach my $key (
        sort {
            $self->{_ProbeHash}->{$a}->[0] cmp $self->{_ProbeHash}->{$b}->[0]
        }
        keys %{ $self->{_ProbeHash} }
      )
    {

        # This lets us know if we should print the headers.
        my $printHeaders = 0;

        # Extract the PID from the string in the hash.
        my $row = $self->{_ProbeHash}->{$key};

        if ( $currentPID == 0 ) {

            # grab first PID from the hash
            $currentPID   = $row->[0];
            $printHeaders = 1;
        }
        elsif ( $row->[0] != $currentPID ) {

            # if different from the current one, print a seperator
            print "\n\n";
            $currentPID   = $row->[0];
            $printHeaders = 1;
        }

        if ( $printHeaders == 1 ) {

            # Print the name of the current platform.
            my $currentPlattformName =
              $platforms->getPlatformNameFromPID($currentPID);
            print "\"$currentPlattformName\"\n";
            print
"Experiment Number,Study Description, Experiment Heading,Experiment Description\n";

            # String representing the list of experiment names.
            my $experimentList = ",,,,,,,";

            # Temporarily hold the string we are to output so we can trim the
            # trailing ",".
            my $outLine = "";

            # Loop through the list of experiments and print out the ones for
            # this platform.
            foreach my $value (
                sort { $a <=> $b }
                keys %{ $self->{_ExperimentListHash} }
              )
            {
                if ( $self->{_ExperimentListHash}->{$value} == $currentPID ) {

                    #Experiment Number, Study Description, Experiment
                    #Heading, Experiment Description
                    my $fullExperimentDataValue =
                      $self->{_FullExperimentData}->{$value};
                    print join(
                        ',',
                        (
                            $value,
                            $fullExperimentDataValue->{description},
                            $fullExperimentDataValue->{experimentHeading},
                            $fullExperimentDataValue->{ExperimentDescription}
                        )
                      ),
                      "\n";

                    #Current experiment name.
                    my $currentExperimentName =
                      $self->{_ExperimentNameListHash}->{$value};
                    $currentExperimentName =~ s/\,//g;

                    # The list of experiments goes with the Ratio line for each
                    # block of 5 columns.
                    $experimentList .= "$value : $currentExperimentName,,,,,,";

                    # Form the line that goes above the data. Each experiment
                    # gets a set of 5 columns.
                    $outLine .=
",$value:Ratio,$value:FC,$value:P-Val,$value:Intensity1,$value:Intensity2,";
                }
            }

            #Trim trailing comma off experiment list.
            $experimentList =~ s/\,$//;

            #Trim trailing comma off data row header.
            $outLine =~ s/\,$//;

            #Print list of experiments.
            print "$experimentList\n";

            #Print header line for probe rows.
            print
"Probe ID,Accession Number,Gene,Probe Sequence,Official Gene Name,Gene Ontology,$outLine\n";
        }

        # Trim any commas out of the Gene Name, Gene Description, and Gene
        # Ontology
        my $geneName = ( defined( $row->[4] ) ) ? $row->[4] : '';
        $geneName =~ s/\,//g;
        my $probeSequence = ( defined( $row->[6] ) ) ? $row->[6] : '';
        $probeSequence =~ s/\,//g;
        my $geneDescription = ( defined( $row->[7] ) ) ? $row->[7] : '';
        $geneDescription =~ s/\,//g;
        my $geneOntology = ( defined( $row->[8] ) ) ? $row->[8] : '';
        $geneOntology =~ s/\,//g;

        # Print the probe info: Probe ID, Accession, Gene Name, Probe
        # Sequence, Gene description, Gene Ontology
        my $outRow =
"$row->[1],$row->[3],$geneName,$probeSequence,$geneDescription,$geneOntology,,";

        # For this reporter we print out a column for all the experiments that
        # we have data for.
        foreach my $EIDvalue (
            sort { $a <=> $b }
            keys %{ $self->{_ExperimentListHash} }
          )
        {

            # Only try to see the EID's for platform $currentPID.
            if ( $self->{_ExperimentListHash}->{$EIDvalue} == $currentPID ) {

                # Add all the experiment data to the output string.
                my $outputColumns =
                  $self->{_ProbeExperimentHash}->{$key}->{$EIDvalue};
                my @outputColumns_array =
                  ( defined $outputColumns )
                  ? @$outputColumns
                  : map { undef } 1 .. 5;
                $outRow .= join( ',',
                    map { ( defined $_ ) ? $_ : '' } @outputColumns_array )
                  . ',,';
            }
        }

        print "$outRow\n";
    }
    return;
}

#######################################################################################
#Loop through the list of probes we are filtering on and create a list.
#######################################################################################
sub getProbeList {
    my $self = shift;
    return join( ',', keys %{ $self->{_ProbeHash} } );
}
#######################################################################################
#Loop through the list of experiments we are displaying and get the information on each.
# We need eid and stid for each.
#######################################################################################
sub getFullExperimentData {
    my $self = shift;

    my @eid_list;
    my @stid_list;

    foreach ( keys %{ $self->{_ExperimentStudyListHash} } ) {
        my ( $eid, $stid ) = split /\|/;
        push @eid_list,  $eid;
        push @stid_list, $stid;
    }

    my $eid_string  = join( ',', @eid_list );
    my $stid_string = join( ',', @stid_list );

    my $whereSQL;
    my $curr_proj = $self->{_WorkingProject};
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj = $self->{_dbh}->quote($curr_proj);
        $whereSQL  = <<"END_whereTitlesSQL";
INNER JOIN ProjectStudy USING(stid)
WHERE prid=$curr_proj AND eid IN ($eid_string) AND study.stid IN ($stid_string)
END_whereTitlesSQL
    }
    else {
        $whereSQL =
          "WHERE eid IN ($eid_string) AND study.stid IN ($stid_string)";
    }
    my $query_titles = <<"END_query_titles_element";
SELECT experiment.eid, 
    CONCAT(study.description, ': ', experiment.sample1, ' / ', experiment.sample2) AS title, 
    CONCAT(experiment.sample1, ' / ', experiment.sample2) AS experimentHeading,
    study.description,
    experiment.ExperimentDescription 
FROM experiment 
INNER JOIN StudyExperiment USING(eid)
INNER JOIN study USING(stid)
$whereSQL
END_query_titles_element

    my $sth = $self->{_dbh}->prepare($query_titles);
    my $rc  = $sth->execute();
    $self->{_FullExperimentData} = $sth->fetchall_hashref('eid');

    $sth->finish;
    return;
}

#===  FUNCTION  ================================================================
#         NAME:  getResultTableHTML
#      PURPOSE:  display results table for Find Probes
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getResultTableHTML {
    my $self = shift;

    my $q     = $self->{_cgi};
    my $type  = $q->param('type');
    my $match = $q->param('match');

    my @ret = (
        $q->h2( { -id => 'caption' }, '' ),
        $q->p(
            { -id => 'subcaption' },
            sprintf(
                'Searched %s (%s): %s',
                lc( $self->{_typeDesc}->{$type} ),
                lc( $self->{_matchDesc}->{$match} ),
                join( ', ', @{ $self->{_SearchItems} } )
            )
        ),
        $q->div(
            $q->a( { -id => 'probetable_astext' }, 'View as plain text' )
        ),
        $q->div( { -id => 'probetable' }, '' )
    );
    if ( $q->param('graph') ) {
        push @ret, $q->ul( { -id => 'graphs' }, '' );
    }
    return @ret;
}

#===  FUNCTION  ================================================================
#         NAME:  getFormHTML
#      PURPOSE:  display Find Probes form
#   PARAMETERS:  $q - CGI object
#                $action - name of the top-level action
#                $curr_proj - current working project
#      RETURNS:  List of strings representing HTML entities. The list can be
#      printed directly by calling `print @list'.
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getFormHTML {
    my ($self) = @_;

    my $q         = $self->{_cgi};
    my $curr_proj = $self->{_WorkingProject};

    # note: get $curr_proj from session

    my %opts_dropdown;
    my $opts_dropdown_t = tie(
        %opts_dropdown, 'Tie::IxHash',
        '1' => 'Basic (names and ids only)',
        '2' => 'Full annotation',
        '3' => 'Full annotation with experiment data (CSV)'
    );
    my %trans_dropdown;
    my $trans_dropdown_t = tie(
        %trans_dropdown, 'Tie::IxHash',
        'fold' => 'Fold Change +/- 1',
        'ln'   => 'Log2 Ratio'
    );

    return $q->start_form(
        -id      => 'main_form',
        -method  => 'POST',
        -action  => $q->url( absolute => 1 ) . '?a=findProbes',
        -enctype => 'application/x-www-form-urlencoded'
      ),
      $q->h2('Find Probes'),
      $q->p(<<"END_H2P_TEXT"),
You can enter here a list of probes, accession numbers, or gene names. 
The results will contain probes that are related to the search terms.
END_H2P_TEXT
      $q->dl(
        $q->dt( $q->label( { -for => 'terms' }, 'Search term(s):' ) ),
        $q->dd(
            $q->textarea(
                -name    => 'terms',
                -id      => 'terms',
                -rows    => 10,
                -columns => 50,
                -title   => <<"END_terms_title"
Enter list of terms to search. Multiple entries have to be separated by commas 
or be on separate lines.
END_terms_title
            )
        ),
        $q->dt( $q->label( { -for => 'type' }, 'Search type:' ) ),
        $q->dd(
            $q->popup_menu(
                -name    => 'type',
                -id      => 'type',
                -default => 'gene',
                -values  => [ keys %{ $self->{_typeDesc} } ],
                -labels  => $self->{_typeDesc},
                -title   => 'Choose which fields you would like to be searched.'
            )
        ),
        $q->dt('Pattern to match:'),
        $q->dd(
            $q->radio_group(
                -name      => 'match',
                -linebreak => 'true',
                -default   => 'full',
                -values    => [ keys %{ $self->{_matchDesc} } ],
                -labels    => $self->{_matchDesc},
                -title     => <<"END_match_title"
Example of a regular expression: entering ^cyp.b into the Search Terms box above 
and choosing "Gene Symbols" under Search Type would tell the database to 
retrieve all genes starting with cyp.b where the period represents any one 
character (either letter or digit).
END_match_title
            ),
            $q->p( { -style => 'color:#777' }, <<"END_EXAMPLE_TEXT")
* Example: "^cyp.b" (no quotation marks) would retrieve all genes starting with 
cyp.b where the period represents any one character (2, 3, 4, "a", etc.).  See 
<a href="http://dev.mysql.com/doc/refman/5.0/en/regexp.html">this page</a> for 
more examples.
END_EXAMPLE_TEXT
        ),
        $q->dt( $q->label( { -for => 'opts' }, 'Output options:' ) ),
        $q->dd(
            $q->popup_menu(
                -name    => 'opts',
                -id      => 'opts',
                -values  => [ keys %opts_dropdown ],
                -default => '2',
                -labels  => \%opts_dropdown,
                -title => 'Choose output format and how many fields to include'
            )
        ),
        $q->dt(
            { -id => 'graph_names' },
            $q->label( { -for => 'graph' }, 'Differential Expression Graphs:' )
        ),
        $q->dd(
            { -id => 'graph_values' },
            $q->checkbox(
                -id      => 'graph',
                -checked => 0,
                -name    => 'graph',
                -label   => '',
                -title   => <<"END_BROWSER_NOTICE"
Works best with Firefox or Safari. SVG support on Internet Explorer (IE) requires either 
IE 9 or Adobe SVG plugin.
END_BROWSER_NOTICE
            ),
        ),
        $q->dt( { -id => 'graph_option_names' }, "Response variable:" ),
        $q->dd(
            { -id => 'graph_option_values' },
            $q->radio_group(
                -name      => 'trans',
                -linebreak => 'true',
                -default   => 'fold',
                -values    => [ keys %trans_dropdown ],
                -labels    => \%trans_dropdown
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'proj', -value => $curr_proj ),
            $q->submit(
                -class => 'css3button',
                -name  => 'b',
                -value => 'Search',
                -title => 'Search the database'
            )
        ),
      ),
      $q->endform;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  build_InsideTableQuery
#   PARAMETERS:  $type - query type (probe|gene|accnum)
#                tmp_table => $tmpTable - uploaded table to join on
#      RETURNS:  true value
#  DESCRIPTION:  Fills _InsideTableQuery field
#       THROWS:  SGX::Abstract::Exception::User
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_InsideTableQuery {
    my ( $self, %optarg ) = @_;

    my $type = $self->{_cgi}->param('type');

    my $predicate = 'WHERE %s ' . $self->{_Predicate};

    my $probe_spec_fields =
      ( $type eq 'probe' )
      ? 'rid, reporter, probe_sequence, pid'
      : 'NULL AS rid, NULL AS reporter, NULL AS probe_sequence, NULL AS pid';

    my %translate_fields = (
        'probe'  => 'reporter',
        'gene'   => 'seqname',
        'accnum' => 'accnum'
    );

    $self->{_InsideTableQuery} = sprintf(
        <<"END_InsideTableQuery_probe",
select $probe_spec_fields,
g2.gid, 
g2.accnum,
g2.seqname, 
g2.description, 
g2.gene_note 

from gene g2 right join
(select probe.rid, probe.reporter, probe.probe_sequence, probe.pid,
    accnum from probe left join annotates on annotates.rid=probe.rid left join
gene on gene.gid=annotates.gid $predicate GROUP BY accnum) as g1
on g2.accnum=g1.accnum where rid is not NULL

union

select $probe_spec_fields,
g4.gid, 
g4.accnum,
g4.seqname, 
g4.description, 
g4.gene_note 

from gene g4 right join
(select probe.rid, probe.reporter, probe.probe_sequence, probe.pid,
    seqname from probe left join annotates on annotates.rid=probe.rid left join
    gene on gene.gid=annotates.gid $predicate GROUP BY seqname) as g3
on g4.seqname=g3.seqname where rid is not NULL

END_InsideTableQuery_probe
        $translate_fields{$type},
        $translate_fields{$type}
    );

    return 1;
}
#######################################################################################
sub build_SimpleProbeQuery {
    my ($self) = @_;

    my $InsideTableQuery = $self->{_InsideTableQuery};

    # only return results for platforms that belong to the current working
    # project (as determined through looking up studies linked to the current
    # project).
    my $curr_proj             = $self->{_WorkingProject};
    my $sql_subset_by_project = '';
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj             = $self->{_dbh}->quote($curr_proj);
        $sql_subset_by_project = <<"END_sql_subset_by_project"
INNER JOIN study ON study.pid=probe.pid
INNER JOIN ProjectStudy USING(stid) 
WHERE prid=$curr_proj 
END_sql_subset_by_project
    }

    $self->{_ProbeQuery} = <<"END_ProbeQuery";
SELECT DISTINCT probe.rid
FROM ( $InsideTableQuery ) as g0
LEFT JOIN annotates USING(gid)
INNER JOIN probe ON probe.rid=COALESCE(annotates.rid, g0.rid)
$sql_subset_by_project
END_ProbeQuery

    return 1;
}
#######################################################################################
sub build_ProbeQuery {
    my ( $self, %p ) = @_;
    my $sql_select_fields = '';

    assert( defined( $p{extra_fields} ) );

    if ( $p{extra_fields} == 1 ) {

        # basic output
        $sql_select_fields = <<"END_select_fields_basic";
probe.rid,
platform.pid,
probe.reporter                          AS 'Probe ID',
platform.pname                          AS 'Platform',
GROUP_CONCAT(
    DISTINCT COALESCE(g0.accnum, '')
    ORDER BY g0.seqname ASC SEPARATOR ' '
)                                       AS 'Accession No.', 
GROUP_CONCAT(
    DISTINCT COALESCE(g0.seqname, '')
    ORDER BY g0.seqname ASC SEPARATOR ' '
)                                       AS 'Gene Symb.',
platform.species                        AS 'Species' 
END_select_fields_basic
    }
    else {

        # extra fields in output
        $sql_select_fields = <<"END_select_fields_extras";
probe.rid,
platform.pid,
probe.reporter                          AS 'Probe ID', 
platform.pname                          AS 'Platform',
GROUP_CONCAT(
    DISTINCT COALESCE(g0.accnum, '')
    ORDER BY g0.seqname ASC SEPARATOR ' '
)                                       AS 'Accession No.', 
GROUP_CONCAT(
    DISTINCT COALESCE(g0.seqname, '')
    ORDER BY g0.seqname ASC SEPARATOR ' '
)                                       AS 'Gene Symb.', 
platform.species                        AS 'Species', 
probe.probe_sequence                    AS 'Probe Sequence',
GROUP_CONCAT(
    DISTINCT g0.description ORDER BY g0.seqname ASC SEPARATOR '; '
)                                       AS 'Offic. Gene Name',
GROUP_CONCAT(
    DISTINCT gene_note ORDER BY g0.seqname ASC SEPARATOR '; '
)                                       AS 'Gene Ontology'
END_select_fields_extras
    }

    # only return results for platforms that belong to the current working
    # project (as determined through looking up studies linked to the current
    # project).
    my $curr_proj             = $self->{_WorkingProject};
    my $sql_subset_by_project = '';
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj             = $self->{_dbh}->quote($curr_proj);
        $sql_subset_by_project = <<"END_sql_subset_by_project"
INNER JOIN study ON study.pid=platform.pid
INNER JOIN ProjectStudy USING(stid) 
WHERE prid=$curr_proj 
END_sql_subset_by_project
    }
    my $InsideTableQuery = $self->{_InsideTableQuery};
    $self->{_ProbeQuery} = <<"END_ProbeQuery";
SELECT
$sql_select_fields
FROM ( $InsideTableQuery ) AS g0
LEFT JOIN annotates USING(gid)
INNER JOIN probe ON probe.rid=COALESCE(annotates.rid, g0.rid)
INNER JOIN platform ON platform.pid=probe.pid
$sql_subset_by_project
GROUP BY probe.rid
END_ProbeQuery

    return 1;
}
#######################################################################################
sub findProbes_js {
    my $self = shift;

    # call to build_InsideTableQuery() followed by one to build_ProbeQuery()
    $self->build_InsideTableQuery();

    my $opts =
      ( defined( $self->{_cgi}->param('opts') ) )
      ? $self->{_cgi}->param('opts')
      : 1;
    $self->build_ProbeQuery( extra_fields => $opts );

    my $trans =
      ( defined( $self->{_cgi}->param('trans') ) )
      ? $self->{_cgi}->param('trans')
      : 'fold';

    if ( $opts == 3 ) {

    #---------------------------------------------------------------------------
    #  CSV output
    #---------------------------------------------------------------------------
        $self->{_UserSession}->commit();
        $self->loadProbeData();
        $self->loadExperimentData();
        $self->getFullExperimentData();
        $self->printFindProbeCSV();
        exit;
    }
    else {

    #---------------------------------------------------------------------------
    #  HTML output
    #---------------------------------------------------------------------------
        $self->loadProbeData();
        my $rowcount  = $self->{_ProbeCount};
        my $proj_name = $self->{_WorkingProjectName};
        my $caption   = sprintf(
            '%sFound %d probe%s',
            ( defined($proj_name) and $proj_name ne '' )
            ? "${proj_name}: "
            : '',
            $rowcount,
            ( $rowcount == 1 ) ? '' : 's',
        );

        my @json_records;
        foreach my $row ( values %{ $self->{_ProbeHash} } ) {

            # the below "trick" converts an array into a hash such that array
            # elements become hash values and array indexes become hash keys
            #
            # Skipping the first value in the array (it's platform ID)
            push @json_records,
              +{ map { ( $_ - 1 ) => $row->[$_] } 1 .. ( @$row - 1 ) };
        }

        my %type_to_column = (
            'probe'  => '0',
            'accnum' => '2',
            'gene'   => '3'
        );

        my %json_probelist = (
            caption => $caption,
            records => \@json_records,
            headers => $self->{_Names}
        );

        my $type         = $self->{_cgi}->param('type');
        my $match        = $self->{_cgi}->param('match');
        my $print_graphs = $self->{_cgi}->param('graph');
        my $out          = sprintf(
            <<"END_JSON_DATA",
var searchColumn = "%s";
var queriedItems = %s;
var probelist = %s;
var url_prefix = "%s";
var response_transform = "%s";
var show_graphs = %s;
var extra_fields = %s;
var project_id = "%s";
END_JSON_DATA
            $type_to_column{$type},
            encode_json(
                ( $match eq 'full' )
                ? +{ map { lc($_) => undef } @{ $self->{_SearchItems} } }
                : $self->{_SearchItems}
            ),
            encode_json( \%json_probelist ),
            $self->{_cgi}->url( -absolute => 1 ),
            $trans,
            ($print_graphs) ? 'true' : 'false',
            ( $opts > 1 )   ? 'true' : 'false',
            $self->{_WorkingProject}
        );

        return $out;
    }
}

1;

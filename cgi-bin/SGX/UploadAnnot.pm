
=head1 NAME

SGX::UploadAnnot

=head1 SYNOPSIS

=head1 DESCRIPTION
Upload platform annotations

=head1 AUTHORS
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::UploadAnnot;

use strict;
use warnings;
use Data::Dumper;
use Switch;
use JSON::XS;
use SGX::Model::PlatformStudyExperiment;
use Text::CSV;

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadAnnot
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

    ${$param{title}} = 'Upload Annotations';

    my $self = {
        _dbh         => $dbh,
        _cgi         => $q,
        _UserSession => $s,
        _js_src_yui  => $js_src_yui,
        _js_src_code => $js_src_code,
    };

    bless $self, $class;
    return $self;
}

#---------------------------------------------------------------------------
#  Controller methods
#---------------------------------------------------------------------------
#===  CLASS METHOD  ============================================================
#        CLASS:  UploadAnnot
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

    switch ($action) {
        case 'Upload' {
            return unless $s->is_authorized('user');
            my @eids = $self->{_cgi}->param('eids');
            $self->{_eidList} = \@eids;
            $self->loadReportData();
            push @$js_src_code, { -code => $self->runReport_js() };
        }
        else {
            return unless $s->is_authorized('user');
            push @$js_src_yui,
              (
                'yahoo-dom-event/yahoo-dom-event.js',
                'animation/animation-min.js',
                'dragdrop/dragdrop-min.js'
              );
            push @$js_src_code, { -src => 'UploadAnnot.js' };
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadAnnot
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
        case 'Upload' {
            return $self->LoadHTML();
        }
        else {

            # default action: show form
            return $self->form_uploadAnnot();
        }
    }
}

#---------------------------------------------------------------------------
#  Model methods
#---------------------------------------------------------------------------

#===  FUNCTION  ================================================================
#         NAME:  get_annot_fields
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_annot_fields {

# takes two arguments which are references to hashes that will store field names of two tables:
# probe and gene

# get fields from Probe table (except pid, rid)
#my $sth = $dbh->prepare(qq{show columns from probe where Field not regexp "^[a-z]id\$"});
#my $rowcount = $sth->execute();
#while (my @row = $sth->fetchrow_array) {
#    $probe_fields->{$row[0]} = 1;
#}
#$sth->finish;

    my %probe_fields;
    my $probe_fields_t = tie(
        %probe_fields, 'Tie::IxHash',
        'Probe ID'       => 'reporter',
        'Probe Sequence' => 'probe_sequence'
    );

# get fields from Gene table (except pid, gid)
#$sth = $dbh->prepare(qq{show columns from gene where Field not regexp "^[a-z]id\$"});
#$rowcount = $sth->execute();
#while (my @row = $sth->fetchrow_array) {
#    $gene_fields->{$row[0]} = 1;
#}
#$sth->finish;

    my %gene_fields;
    my $gene_fields_t = tie(
        %gene_fields, 'Tie::IxHash',
        'Gene Symbol'      => 'seqname',
        'Accession Number' => 'accnum',
        'Gene Name'        => 'description',
        'Source'           => 'source',
        'Gene Note'        => 'gene_note'
    );

    return ( \%probe_fields, \%gene_fields );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::UploadAnnot
#       METHOD:  uploadAnnot
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Upload annotation
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub uploadAnnot {
    my $self = shift;
    my $dbh  = $self->{_dbh};
    my $q    = $self->{_cgi};

    my @fields;
    my $regex_split_on_commas = qr/ *, */;

    #Fields is an array of the fields from the input box.
    @fields = split( $regex_split_on_commas, $q->param('fields') )
      if defined( $q->param('fields') );

    #If the user didn't select enough fields on the input screen, warn them.
    if ( @fields < 2 ) {

        # :TODO:07/12/2011 15:03:47:es: replace printing with exceptions here
        die 'Too few fields specified -- nothing to update.';
    }

    #Create two hashes that hold hash{Long Name} = DBName

    my ( $probe_fields_ref, $gene_fields_ref ) = get_annot_fields();
    my %probe_fields = %$probe_fields_ref;
    my %gene_fields  = %$gene_fields_ref;

    my $i = 0;

    #This hash will hold hash{DBName} = index
    my %col;

    #Create a hash mapping record names to columns in the file
    foreach (@fields) {

        # if the assertion below fails, the field specified by the user
        # either doesn't exist or is protected.
        die if !( $probe_fields{$_} || $gene_fields{$_} );

        if ( $probe_fields{$_} ) {
            $col{ $probe_fields{$_} } = $i;
        }

        if ( $gene_fields{$_} ) {
            $col{ $gene_fields{$_} } = $i;
        }

        $i++;
    }

    # delete core fields from field hash
    delete $probe_fields{'Probe ID'};
    delete @gene_fields{ ( 'Accession Number', 'Gene Symbol' ) };

    # create two slices of specified fields, one for each table
    my @slice_probe = grep { defined } @col{%probe_fields};
    my @slice_gene  = grep { defined } @col{%gene_fields};

    my $gene_titles =
      ',' . join( ',', map { $gene_fields{ $fields[$_] } } @slice_gene );
    my $probe_titles =
      ',' . join( ',', map { $probe_fields{ $fields[$_] } } @slice_gene );

    # probe table only is updated when $reporter_index is defined and its value
    # is valid

    my ( $reporter_index, $accnum_index, $seqname_index ) =
      @col{qw(reporter accnum seqname)};

    my $outside_have_reporter = defined($reporter_index);
    my $outside_have_gene = defined($accnum_index) || defined($seqname_index);
    my $pid_value         = $q->param('platform');
    my $replace_accnum =
         $outside_have_reporter
      && $outside_have_gene
      && !defined( $q->param('add') );

    if ( !$outside_have_reporter && !$outside_have_gene ) {
        die 'No core fields specified -- cannot proceed with update.';
    }

    my $update_gene;

    # Access uploaded file
    my $fh = $q->upload('uploaded_file');

    # "local $/" sets input record separator to undefined, allowing "slurp" mode
    # The "trick" below involving do{} block is from Modern Perl, p.150. After
    # the do{} block, the value of $/ reverts to the previous state.
    my @lines = split(
        /\r\n|\n|\r/,
        do { local $/ = <$fh> }
    );
    close($fh);

    # the line below attempts to split on (1) Windows-style line CRLF line
    # breaks, (2) Unix-style LF line breaks, (3) Mac-style CR line breaks in the
    # respective order:

    my $csv_in = Text::CSV->new( { sep_char => "\t" } );

    for ( my $line_num = 1 ; $csv_in->parse( shift @lines ) ; $line_num++ ) {

        # split on a tab surrounded by any number (including zero) of blanks
        my @row = $csv_in->fields();
        my @sql;

        my $have_reporter = 0;

        # probe fields -- updated only when reporter (core field for probe
        # table) is specified
        if ($outside_have_reporter) {
            my $probe_values     = '';
            my $probe_duplicates = '';
            foreach (@slice_probe) {
                my $value = $row[$_];
                $value =
                  ( $value ne '' and $value ne '#N/A' )
                  ? $dbh->quote($value)
                  : 'NULL';

                #$row[$_] = $value;
                $probe_values .= ',' . $value;
                $probe_duplicates .=
                  ',' . $probe_fields{ $fields[$_] } . '=' . $value;
            }
            my $reporter_value = '';
            if ( defined($reporter_index) ) {
                $reporter_value = $row[$reporter_index];
                $reporter_value =
                  ( $reporter_value ne '' and $reporter_value ne '#N/A' )
                  ? $dbh->quote($reporter_value)
                  : 'NULL';
                $have_reporter++ if $reporter_value ne 'NULL';
            }
            if ($have_reporter) {

                # TODO: ensure new rows are not inserted into the Probe table
                # unless we are explicitly setting up a new platform.
                #
                # If reporter was not specified, will not be able to obtain rid
                # and update the "annotates" table.
                push @sql,
qq{insert into probe (pid, reporter $probe_titles) values ($pid_value, $reporter_value $probe_values) on duplicate key update rid=LAST_INSERT_ID(rid) $probe_duplicates};
                push @sql, qq{set \@rid:=LAST_INSERT_ID()};

                # Only delete "annotates" content, not the "gene" content.
                # Then, when everything is done, can go over the entire "gene"
                # table and try to delete records.  Successful delete means the
                # records were orphaned (not pointed to from the "annotates"
                # table).
                push( @sql,
                    qq{delete quick ignore from annotates where rid=\@rid} )
                  if $replace_accnum;
            }
        }

        # gene fields -- updated when any of the core fields are specified
        foreach (@slice_gene) {
            my $value = $row[$_];
            $value =
              ( $value ne '' and $value ne '#N/A' )
              ? $dbh->quote($value)
              : 'NULL';
            $row[$_] = $value;
        }
        my $seqname_value;
        my @accnum_array;
        my $have_seqname = 0;
        if ($outside_have_gene) {
            $update_gene = join( ',',
                map { $gene_fields{ $fields[$_] } . '=' . $row[$_] }
                  @slice_gene );
            my $gene_values = join( ',', map { $row[$_] } @slice_gene );
            $gene_values = ',' . $gene_values if $gene_values ne '';

            if ( defined($seqname_index) ) {
                $seqname_value = $row[$seqname_index];
                $seqname_value =
                  (       $seqname_value ne ''
                      and $seqname_value ne '#N/A'
                      and $seqname_value ne 'Data not found' )
                  ? $dbh->quote($seqname_value)
                  : 'NULL';
                $have_seqname++ if $seqname_value ne 'NULL';
            }
            if ( defined($accnum_index) ) {

                # The two lines below split the value on a comma surrounded by
                # any number (including zero) of blanks, delete invalid members
                # from the resulting array, quote each member with DBI::quote,
                # and assign the array to @accnum_array.
                @accnum_array =
                  map { $dbh->quote($_) }
                  grep { $_ && $_ ne '#N/A' }
                  split( $regex_split_on_commas, $row[$accnum_index] );

                # Iterate over the resulting array
                if ( $have_reporter && @accnum_array ) {
                    push @sql,
qq{update gene natural join annotates set seqname=$seqname_value where rid=\@rid};
                    foreach (@accnum_array) {
                        push @sql,
qq{insert into gene (accnum, seqname $gene_titles) values ($_, $seqname_value $gene_values) on duplicate key update gid=LAST_INSERT_ID(gid) $update_gene};
                        push @sql,
qq{insert ignore into annotates (rid, gid) values (\@rid, LAST_INSERT_ID())};
                    }
                }
            }
            if ( $have_reporter && !@accnum_array && $have_seqname ) {

                # have gene symbol but not accession number
                push @sql,
qq{update gene natural join annotates set seqname=$seqname_value where rid=\@rid};
                push @sql,
qq{insert into gene (seqname $gene_titles) values ($seqname_value $gene_values) on duplicate key update gid=LAST_INSERT_ID(gid) $update_gene};
                push @sql,
qq{insert ignore into annotates (rid, gid) values (\@rid, LAST_INSERT_ID())};
            }
        }
        if (@slice_gene) {
            if ( !$outside_have_gene ) {

                # If $outside_have_gene is true, $update_gene string has been
                # formed already.
                #
                # title1 = value1, title2 = value2, ...
                $update_gene = join( ',',
                    map { $gene_fields{ $fields[$_] } . '=' . $row[$_] }
                      @slice_gene );
            }
            if ($have_reporter) {
                if ( !@accnum_array && !$have_seqname && !$replace_accnum ) {

# if $replace_accnum was specified, all rows from annotates table where rid=@rid
# have already been deleted, so no genes would be updated anyway
                    push @sql,
qq{update gene natural join annotates set $update_gene where rid=\@rid};
                }
            }
            elsif ( !@accnum_array && $have_seqname ) {
                my $eq_seqname =
                  ( $seqname_value eq 'NULL' )
                  ? 'is NULL'
                  : "=$seqname_value";
                push @sql,
qq{update gene set $update_gene where seqname $eq_seqname and pid=$pid_value};
            }
            elsif ( @accnum_array && !$have_seqname ) {
                foreach (@accnum_array) {
                    my $eq_accnum = ( $_ eq 'NULL' ) ? 'is NULL' : "=$_";
                    push @sql,
qq{update gene set $update_gene where accnum $eq_accnum and pid=$pid_value};
                }
            }
            elsif ( @accnum_array && $have_seqname ) {
                my $eq_seqname =
                  ( $seqname_value eq 'NULL' )
                  ? 'is NULL'
                  : "=$seqname_value";
                foreach (@accnum_array) {
                    my $eq_accnum = ( $_ eq 'NULL' ) ? 'is NULL' : "=$_";
                    push @sql,
qq{update gene set $update_gene where accnum $eq_accnum and seqname $eq_seqname and pid=$pid_value};
                }
            }
        }

        # execute the SQL statements
        foreach (@sql) { $dbh->do($_); }
    }

    if ( $outside_have_reporter && $replace_accnum ) {

        # have to "optimize" because some of the deletes above were performed
        # with "ignore" option
        $dbh->do('optimize table annotates');

        # in case any gene records have been orphaned, delete them
        $dbh->do(
'delete gene from gene left join annotates on gene.gid=annotates.gid where annotates.gid is NULL'
        );

    }
    my $count_lines = @lines;

    warn sprintf( "%d lines processed.", $count_lines );

    #Flag the platform as being annotated.
    return $dbh->do( 'UPDATE platform SET isAnnotated=1 WHERE pid=?',
        undef, $pid_value );
}

#---------------------------------------------------------------------------
#  View methods
#---------------------------------------------------------------------------

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::UploadAnnot
#       METHOD:  form_uploadAnnot
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Show form for data upload
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_uploadAnnot {

    my $self = shift;
    my $dbh  = $self->{_dbh};
    my $q    = $self->{_cgi};

    #If we have a newpid in the querystring, default the dropdown list.
    my $newpid =
      defined( $q->param('newpid') )
      ? $q->param('newpid')
      : ( ( defined $q->url_param('newpid') ) ? $q->url_param('newpid') : '' );

    my %core_fields;
    my $core_fields_t = tie(
        %core_fields, 'Tie::IxHash',
        'Probe ID'         => 1,
        'Accession Number' => 1,
        'Gene Symbol'      => 1
    );

   # :TODO:07/12/2011 14:12:49:es: Move out code that queries the platform table
   # from this view method
   #
   # get a list of platforms and cutoff values
    my $sth =
      $dbh->prepare(qq{SELECT pid, pname FROM platform ORDER BY pname ASC});
    my $rowcount = $sth->execute();
    my %platforms;
    my $platforms_t = tie( %platforms, 'Tie::IxHash' );
    while ( my @row = $sth->fetchrow_array ) {
        $platforms{ $row[0] } = $row[1];
    }
    $sth->finish;

    my ( $probe_fields_ref, $gene_fields_ref ) = get_annot_fields();
    my %probe_fields = %$probe_fields_ref;
    my %gene_fields  = %$gene_fields_ref;

    my @fieldlist =
      map {
        $q->li(
            { -class => ( $core_fields{$_} ) ? 'core' : 'list1', -id => $_ },
            $_ )
      } ( keys %probe_fields, keys %gene_fields );

    return
      $q->h2('Upload Annotation'),
      $q->p(
'Only the fields specified below will be updated. You can specify fields by dragging field tags into the target area on the right and reordering them to match the column order in the tab-delimited file. When reporter (manufacturer-provided id) is among the fields uploaded, the existing annotation for the uploaded probes will be lost and replaced with the annotation present in the uploaded file. The "Add accession numbers to existing probes" option will prevent the update program from deleting existing accession numbers from probes.'
      ),
      $q->p(
'The default policy for updating probe-specific fields is to insert new records whenever existing records could not be matched on the probe core field (reporter id). The default policy for updating gene-specific fields is update-only, without insertion of new records. However, new gene records <em>are</em> inserted when both reporter id and either of the gene core fields (accnum, seqname) are specified.'
      ),
      $q->div(
        { -class => 'workarea' },
        $q->h3('Available Fields:'),
        $q->ul( { -id => 'ul1', -class => 'draglist' }, @fieldlist )
      ),
      $q->div(
        { -class => 'workarea' },
        $q->h3('Fields in the Uploaded File:'),
        $q->ul( { -id => 'ul2', -class => 'draglist' } )
      ),
      $q->startform(
        -method  => 'POST',
        -action  => $q->url( -absolute => 1 ) . '?a=uploadAnnot',
        -enctype => 'multipart/form-data'
      ),
      $q->dl(
        $q->dt('Platform:'),
        $q->dd(
            $q->popup_menu(
                -name    => 'platform',
                -values  => [ keys %platforms ],
                -labels  => \%platforms,
                -default => $newpid
            )
        ),
        $q->dt('File to upload (tab-delimited):'),
        $q->dd( $q->filefield( -name => 'uploaded_file' ) ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -id => 'fields', -name => 'fields' ),
            $q->submit( -class => 'button black bigrounded', -value => 'Upload' )
        )
      ),
      $q->end_form;
}

1;

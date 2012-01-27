package SGX::ManageSpecies;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Abstract::Exception ();
use Digest::SHA1 qw/sha1_hex/;
use SGX::Util qw/car file_opts_html file_opts_columns/;
use SGX::Config qw/$YUI_BUILD_ROOT/;

#---------------------------------------------------------------------------
#  process row in go link input file
#---------------------------------------------------------------------------
my $process_go = sub {
    my $printfun = shift;
    my $line_num = shift;
    my $fields   = shift;

    # check total number of fields present
    if ( @$fields < 2 ) {
        SGX::Exception::User->throw(
            error => sprintf(
                "Only %d field(s) found (2 required) on line %d\n",
                scalar(@$fields), $line_num
            )
        );
    }

    # perform validation on each column
    my $probe_id;
    if ( $fields->[0] =~ m/^([^\s,\/\\=#()"]{1,18})$/ ) {
        $probe_id = $1;
    }
    else {
        SGX::Exception::User->throw(
            error => "Cannot parse probe ID on line $line_num" );
    }
    my $go = $fields->[1];
    my @gos;
    while ( $go =~ /\bGO:(\d{7})\b/gi ) {
        push @gos, $1 + 0;
    }

    #return [ map { [ $probe_id, $_ ] } @gos ];
    if ( @gos > 0 ) {
        $printfun->( $probe_id, $_ ) for @gos;
    }
    else {
        $printfun->( $probe_id, undef );
    }
    return 1;
};

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageUsers
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Override parent constructor; add attributes to object instance
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, @param ) = @_;
    my $self = $class->SUPER::new(@param);

    $self->set_attributes(
        _table_defs => {
            species => {
                item_name => 'species',
                key       => [qw/sid/],
                base      => [qw/sname/],
                view      => [qw/sname/],
                resource  => 'species',
                names     => [qw/sname/],
                meta      => {
                    sname => {
                        label => 'Species',
                        -size => 30
                    }
                },
                lookup => [ gene_counts => [ sid => 'sid' ] ]
            },
            gene_counts => {
                table => 'gene',
                key   => [qw/sid/],
                view  => [qw/id_count gtype_count/],
                meta  => {
                    id_count => {
                        __sql__ => 'COUNT(gid)',
                        label   => 'Annotation Records',
                        parser  => 'number'
                    },
                    gtype_count => {

                        # __sql__ => 'SUM(IF(gtype=1, 1, 0))',
                        __sql__ => 'SUM(gtype)',
                        label   => 'Genes',
                        parser  => 'number'
                    }
                },
                group_by => [qw/sid/]
            },
            'platform' => {
                key      => [qw/pid/],
                view     => [qw/pname def_p_cutoff def_f_cutoff/],
                resource => 'platforms',
                selectors => {}, # table key to the left, URI param to the right
                names => [qw/pname/],
                meta  => {
                    pname => { label => 'Name' },
                    def_p_cutoff =>
                      { label => 'P-value Cutoff', parser => 'number' },
                    def_f_cutoff =>
                      { label => 'Fold-change Cutoff', parser => 'number' }
                },
                constraint => [ sid => sub { shift->{_id} } ]
            },
        },
        _default_table => 'species',
        _readrow_tables =>
          [ 'platform' => { heading => 'Platforms for this Species' } ],
    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageSpecies
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    $self->SUPER::init();

    $self->register_actions(
        clearAnnot => { redirect => 'ajax_clear_annot' },
        uploadAnnot => { head => 'UploadAnnot_head', body => 'readrow_body' }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageSpecies
#       METHOD:  ajax_clear_annot
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub ajax_clear_annot {
    my $self = shift;
    return $self->_ajax_process_request(
        sub {
            my $self = shift;
            my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};

            # prepare request only
            my @sth;
            my @param;

            push @sth, $dbh->prepare(<<"END_delete");
DELETE GeneGO FROM GeneGO INNER JOIN gene ON gene.sid=? AND GeneGO.gid=gene.gid
END_delete
            push @param, [ $self->{_id} ];

            push @sth, $dbh->prepare('DELETE FROM gene WHERE sid=?');
            push @param, [ $self->{_id} ];

            return sub {
                my @return_codes = map {
                    my $p = shift @param;
                    $_->execute(@$p)
                } @sth;
                $_->finish() for @sth;
                return 1;
            };
        }
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageSpecies
#       METHOD:  UploadAnnot_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub UploadAnnot_head {
    my $self = shift;

    my $ret        = $self->readrow_head();
    my $species_id = $self->{_id};

    my $q            = $self->{_cgi};
    my $upload_gname = defined( $q->param('gene_name') );
    my $upload_gdesc = defined( $q->param('gene_desc') );
    my $upload_terms = defined( $q->param('go_terms') );
    my $update_genes = $upload_gname || $upload_gdesc;

    my $process_genes = sub {
        my $printfun = shift;
        my $line_num = shift;
        my $fields   = shift;

        my ( $print_genes, $print_terms ) = @$printfun;

        #----------------------------------------------------------------------
        #  get gene symbol
        #----------------------------------------------------------------------
        my $gsymbol;
        if ( $fields->[0] =~ /^([^\+\s]+)$/ ) {
            $gsymbol = $1;
        }
        else {
            SGX::Exception::User->throw(
                error => "Invalid gene symbol format on line $line_num" );
        }
        my $i = 1;

        #----------------------------------------------------------------------
        #  get gene name and gene description (second and third column)
        #----------------------------------------------------------------------
        my @gname_gdesc;
        if ($upload_gname) {
            my ($gname) = $fields->[$i] =~ /(.*)/;
            push @gname_gdesc, $gname;
            $i++;
        }
        if ($upload_gdesc) {
            my ($gdesc) = $fields->[$i] =~ /(.*)/;
            push @gname_gdesc, $gdesc;
            $i++;
        }
        $print_genes->( $gsymbol, @gname_gdesc ) if @gname_gdesc > 0;

        #----------------------------------------------------------------------
        # get GO terms
        #----------------------------------------------------------------------
        if ($upload_terms) {
            my @gos;
            my $go = $fields->[$i];
            while ( $go =~ /\bGO:(\d{7})\b/gi ) {
                push @gos, $1 + 0;
            }
            $print_terms->( $gsymbol, $_ ) for @gos;
        }

        return 1;
    };

    require SGX::CSV;
    my ( $outputFileNames, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, 'file',
        csv_in_opts => { quote_char => undef },
        rewrite     => 2,
        process     => $process_genes
      );

    my ( $filename_genes, $filename_terms ) = @$outputFileNames;

    my $ug = Data::UUID->new();

    #---------------------------------------------------------------------------
    #  add gene info
    #---------------------------------------------------------------------------
    if ($update_genes) {
        $self->add_message('Loading gene info:');
        my $genes_table = $ug->to_string( $ug->create() );
        $genes_table =~ s/-/_/g;
        $genes_table = "tmp$genes_table";
        my @sth_genes;
        my @param_genes;

        push @sth_genes,
          sprintf(
            "CREATE TEMPORARY TABLE $genes_table (%s) ENGINE=MEMORY",
            join( ',',
                'gsymbol char(32) NOT NULL',
                ( $upload_gname ? 'gname varchar(1022) DEFAULT NULL' : () ),
                ( $upload_gdesc ? 'gdesc varchar(2044) DEFAULT NULL' : () ) )
          );
        push @param_genes, [];

        push @sth_genes, sprintf(
            <<"END_loadTermDefs",
LOAD DATA LOCAL INFILE ?
INTO TABLE $genes_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (%s)
END_loadTermDefs
            join( ',',
                'gsymbol',
                ( $upload_gname ? 'gname' : () ),
                ( $upload_gdesc ? 'gdesc' : () ) )
        );
        push @param_genes, [$filename_genes];

        push @sth_genes, sprintf(
            <<"END_update",
UPDATE gene INNER JOIN $genes_table AS temptable
ON gene.gsymbol=temptable.gsymbol AND gene.sid=?
%s
END_update
            join(
                ',',
                (
                    $upload_gname ? 'SET gene.gname=temptable.gname'
                    : ()
                ),
                (
                    $upload_gdesc ? 'SET gene.gdesc=temptable.gdesc'
                    : ()
                )
            )
        );
        my $exec_command = $self->_update_command();
        push @param_genes,
          [
            $update_genes
            ? sub { $exec_command->(); return $self->{_id}; }
            : ()
          ];

        SGX::CSV::delegate_fileUpload(
            delegate   => $self,
            statements => \@sth_genes,
            parameters => \@param_genes,
            filename   => $filename_genes
        );
    }

    #---------------------------------------------------------------------------
    #  add GO terms
    #---------------------------------------------------------------------------
    if ($upload_terms) {
        $self->add_message('Loading GO terms:');
        my $terms_table = $ug->to_string( $ug->create() );
        $terms_table =~ s/-/_/g;
        $terms_table = "tmp$terms_table";
        my @sth_terms;
        my @param_terms;

        push @sth_terms, <<"END_loadTermDefs_createTemp";
CREATE TEMPORARY TABLE $terms_table (
    gsymbol char(32) NOT NULL,
    go_acc int(10) unsigned NOT NULL
) ENGINE=MEMORY
END_loadTermDefs_createTemp
        push @param_terms, [];

        push @sth_terms, <<"END_loadTermDefs";
LOAD DATA LOCAL INFILE ?
INTO TABLE $terms_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    gsymbol,
    go_acc
)
END_loadTermDefs
        push @param_terms, [$filename_terms];

        push @sth_terms, <<"END_delete";
DELETE GeneGO 
FROM GeneGO
    INNER JOIN gene ON gene.sid=? AND gene.rid=GeneGO.rid
    INNER JOIN $terms_table USING(gsymbol)
END_delete
        push @param_terms, [$species_id];

        push @sth_terms, <<"END_insert_gene";
INSERT IGNORE INTO GeneGO (gid, go_acc)
SELECT
    gene.gid AS gid,
    temptable.go_acc AS go_acc,
FROM $terms_table AS temptable
    INNER JOIN gene
        ON gene.sid=?
        AND temptable.gsymbol=gene.gsymbol
END_insert_gene
        push @param_terms, [$species_id];

        SGX::CSV::delegate_fileUpload(
            delegate   => $self,
            statements => \@sth_terms,
            parameters => \@param_terms,
            filename   => $filename_terms
        );
    }

    return $ret;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageSpecies
#       METHOD:  readrow_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD::readrow_head
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readrow_head {
    my $self = shift;
    my ( $js_src_yui, $js_src_code, $css_src_yui ) =
      @$self{qw{_js_src_yui _js_src_code _css_src_yui}};

    my $clearAnnotURI = $self->get_resource_uri( b => 'clearAnnot' );
    push @$css_src_yui, 'button/assets/skins/sam/button.css';
    push @$js_src_yui,  'button/button-min.js';
    push @$js_src_code,
      ( { -src => 'collapsible.js' }, { -code => <<"END_SETUPTOGGLES" } );
var wait_indicator;
YAHOO.util.Event.addListener('clearAnnot', 'click', function(){
        if (!confirm("Are you sure you want to clear annotation for this species?\\n\\nWarning: all related platforms will lose their accession numbers and gene annotation.")) {
            return false;
        }
        wait_indicator = createWaitIndicator(wait_indicator, '$YUI_BUILD_ROOT/assets/skins/sam/ajax-loader.gif');
        var callbackObject = {
            success:function(o) {
                wait_indicator.hide();
            },
            failure:function(o) { 
                wait_indicator.hide();
                alert("Clear request failed");
            },
            scope:this
        };
        YAHOO.util.Connect.asyncRequest(
            "POST", 
            "$clearAnnotURI",
            callbackObject,
            null
        );
        return true;
});

YAHOO.util.Event.addListener(window,'load',function(){

    setupCheckboxes({
        idPrefix: 'geneannot_accnum',
        keyName:  'Gene Symbol'
    });

});
END_SETUPTOGGLES
    return $self->SUPER::readrow_head();
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageSpecies
#       METHOD:  readrow_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD::readrow_body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readrow_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    my %param = (
        $q->a( { -href => '#annotation' }, $q->em('Genomic Annotation') ) =>
          $q->div(
            { -id => '#annotation' },

    #---------------------------------------------------------------------------
    #  gene annotation
    #---------------------------------------------------------------------------
            $q->h3(
                'Upload/Replace Gene Annotation',
                $q->button(
                    {
                        -id    => 'clearAnnot',
                        -class => 'plaintext',
                        -value => '(clear)'
                    }
                )
            ),
            $q->p(<<"END_info"),
Note: You should first upload gene symbols / accession numbers to corresponding
platform before using this form to update annotation (gene symbols not that were
not already uploaded will be ignored).
END_info
            $q->start_form(
                -method   => 'POST',
                -enctype  => 'multipart/form-data',
                -onsubmit => 'return validate_fields(this, ["fileGene"]);',
                -action   => $self->get_resource_uri(
                    b   => 'uploadAnnot',
                    '#' => 'annotation'
                )
            ),
            $q->dl(
                $q->dt('Path to file:'),
                $q->dd(
                    $q->filefield(
                        -id   => 'fileGene',
                        -name => 'file',
                        -title =>
                          'File containing gene symbols and/or gene names'
                    ),
                    file_opts_html( $q, 'geneOpts' ),
                    file_opts_columns(
                        $q,
                        id    => 'geneannot_accnum',
                        items => [
                            gene_name => {
                                -checked => 'checked',
                                -value   => 'Gene Name'
                            },
                            gene_desc => {
                                -checked => 'checked',
                                -value   => 'Gene Description'
                            },
                            go_terms => { -value => 'GO Terms' }
                        ]
                    )
                ),

                $q->dt('&nbsp;'),
                $q->dd(
                    $q->submit(
                        -name  => 'b',
                        -value => 'Upload',
                        -title => 'Upload gene annotation',
                        -class => 'button black bigrounded'
                    )
                )
            ),
            $q->end_form
          )
    );

    return $self->SUPER::readrow_body( \%param );
}

1;

__END__


=head1 NAME

SGX::ManageSpecies

=head1 SYNOPSIS

=head1 DESCRIPTION
Moduel for managing species table.

=head1 AUTHORS
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut



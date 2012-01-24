package SGX::ManageSpecies;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Abstract::Exception ();
use Digest::SHA1 qw/sha1_hex/;
use SGX::Util qw/car file_opts_html file_opts_columns/;

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
        clearAnnot => { redirect => 'ajax_clear_annot' }
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
            warn "preparing request";
            return sub {
                warn "executing request";
            };
        }
    );
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
YAHOO.util.Event.addListener('clearAnnot', 'click', function(){
        if (!confirm("Are you sure you want to clear annotation for this species?\\n\\nWarning: all related platforms will lose their accession numbers and gene annotation.")) {
            return false;
        }
        YAHOO.util.Connect.asyncRequest(
            "POST", 
            "$clearAnnotURI",
            {
                success:function(o) {
                    console.log("ok");
                },
                failure:function(o) { 
                    alert("request failed");
                },
                scope:this
            },
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
                    b   => 'uploadGene',
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



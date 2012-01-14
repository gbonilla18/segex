package SGX::ManageSpecies;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Abstract::Exception ();
use Digest::SHA1 qw/sha1_hex/;
use SGX::Util qw/car file_opts_html/;

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
    push @$js_src_yui, ( 'yahoo/yahoo-min.js', 'button/button-min.js' );
    push @$js_src_code,
      ( { -src => 'collapsible.js' }, { -code => <<"END_SETUPTOGGLES" } );
YAHOO.util.Event.addListener('clearAnnot', 'click', function(){
        if (!confirm("Are you sure you want to clear annotation for this species?")) {
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
        checkboxIds: ['check_gene_name', 'check_gene_desc', 'check_gene_go'],
        bannerId:    'geneannot_accnum_hint',
        keyName:     'Gene Symbols'
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
                    $q->p('File contains columns:'),
                    $q->div(
                        { -class => 'input_container' },
                        $q->input(
                            {
                                -type    => 'checkbox',
                                -checked => 'checked',
                                -name    => 'gene_name',
                                -id      => 'check_gene_name',
                                -value   => 'Gene Names',
                                -title   => 'Upload gene names'
                            }
                        ),
                        $q->input(
                            {
                                -type    => 'checkbox',
                                -checked => 'checked',
                                -name    => 'gene_desc',
                                -id      => 'check_gene_desc',
                                -value   => 'Gene Descriptions',
                                -title   => 'Upload gene descriptions'
                            }
                        ),
                        $q->input(
                            {
                                -type  => 'checkbox',
                                -name  => 'go_terms',
                                -id    => 'check_gene_go',
                                -value => 'GO Terms',
                                -title => 'Upload GO terms'
                            }
                        )
                    ),
                    $q->div(
                        {
                            -class => 'hint visible',
                            -id    => 'geneannot_accnum_hint'
                        },
                        ''
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



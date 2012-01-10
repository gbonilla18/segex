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

    push @$css_src_yui, 'button/assets/skins/sam/button.css';
    push @$js_src_yui, ( 'element/element-min.js', 'button/button-min.js' );
    push @$js_src_code,
      ( { -src => 'collapsible.js' }, { -code => <<"END_SETUPTOGGLES" } );
YAHOO.util.Event.addListener(window,'load',function(){
    // Gene annotation: first column
    var geneannot_state = document.getElementById("geneannot_state");
    var geneannot_div1 = document.getElementById('geneannot_gsymbol_hint');
    var geneannot_div2 = document.getElementById('geneannot_accnum_hint');
    var geneannot = new YAHOO.widget.ButtonGroup("geneannot_container");
    geneannot.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        geneannot_state.value = selectedIndex;
        if (selectedIndex === 0 ) {
            geneannot_div1.style.display = 'block';
            geneannot_div2.style.display = 'none';
        } else {
            geneannot_div1.style.display = 'none';
            geneannot_div2.style.display = 'block';
        }
    });
    if (geneannot_state.value !== '') {
        geneannot.check(geneannot_state.value);
    } else {
        var selectedIndex = geneannot.get('checkedButton').index;
        if (selectedIndex === 0 ) {
            geneannot_div1.style.display = 'block';
            geneannot_div2.style.display = 'none';
        } else {
            geneannot_div1.style.display = 'none';
            geneannot_div2.style.display = 'block';
        }
    }
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
            $q->h3('Upload/Replace Gene Annotation'),
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
                    $q->div(
                        {
                            -class => 'hint visible',
                            -id    => 'geneannot_accnum_hint'
                        },
                        $q->p(
'The file should contain up to four columns (last two columns are optional):'
                        ),
                        $q->ol(
                            $q->li('Gene Symbol / Accession Number'),
                            $q->li('Official Gene Name'),
                            $q->li('Gene Description / Comment'),
                            $q->li('GO Terms')
                        )
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



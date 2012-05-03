package SGX::Static;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;
use SGX::Config qw/$IMAGES_DIR/;

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Static
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

    $self->set_attributes( _permission_level => 'anonym' );
    $self->register_actions(
        about  => { body => 'about_body' },
        schema => { body => 'schema_body' }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Static
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->h2('Help'),
      $q->p('Help pages will be written in parallel with the publication...'),
      $q->p(
        'For detailed installation instructions, see README file in the
          Segex directory (you can also view it ',
        $q->a(
            {
                -title => 'Segex README on Github',
                -href  => 'https://github.com/escherba/segex/blob/master/README'
            },
            'on Github'
        ),
        ')'
      );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Static
#       METHOD:  schema_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub schema_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->img(
        {
            src    => "$IMAGES_DIR/schema.png",
            width  => 720,
            height => 720,
            usemap => '#schema_Map',
            id     => 'schema'
        }
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Static
#       METHOD:  about_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub about_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->h2('About'),

      # ==== ABOUT SEGEX =====
      $q->h3('About Segex'), $q->p(<<"END_paragraph1"),
Segex was designed to help your lab store, view, and retrieve gene expression
data in one centralized location via the web. 
END_paragraph1
      $q->p(<<"END_paragraph2"),
You can use Segex to visualize
responses of your microarray probes via basic graphs, enter and search probe-
and gene-specific annotation, or you can perform sophisticated comparisons of
probe sets under different experimental conditions.
END_paragraph2
      $q->p(<<"END_paragraph3"),
Segex was conceived by David J. Waxman (Boston University) and developed
primarily by Eugene Scherba and Michael McDuffie. Initial work on the database
was done by Eugene Scherba and Katrina Steiling.  Some visualization code was
contributed by Niraj Trivedi.
END_paragraph3

      # ====== MORE =======
      $q->h3('More'),
      $q->p(
        $q->a(
            {
                -href  => "$IMAGES_DIR/segex_schema.pdf",
                -title => 'Download a PDF of the Segex database schema'
            },
            'Click here'
        ),
        'to download a PDF of Segex database schema.'
      ),
      $q->p(
        'Visit Segex on',
        $q->a(
            {
                -href  => 'http://github.com/escherba/segex',
                -title => 'Segex on Github'
            },
            'Github'
        ),
        '.'
      );
}

1;

__END__


=head1 NAME

SGX::Static

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut



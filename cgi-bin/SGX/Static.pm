package SGX::Static;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;
use SGX::Config;

#===  CLASS METHOD  ============================================================
#        CLASS:  Profile
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, @param ) = @_;
    my $self = $class->SUPER::new(@param);

    $self->set_attributes(
        _title => '',

        # model
        _curr_proj   => '',
        _projectList => {}
    );

    bless $self, $class;
    return $self;
}

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

    return $q->p(
'The SEGEX database will provide public access to previously released datasets from the Waxman laboratory, and data mining and visualization modules to query gene expression across several studies and experimental conditions.'
      ),
      $q->p(
'This database was developed at Boston University as part of the BE768 Biological Databases course, Spring 2009, G. Benson instructor. Student developers: Anna Badiee, Eugene Scherba, Katrina Steiling and Niraj Trivedi. Faculty advisor: David J. Waxman.'
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
            src    => IMAGES_DIR . '/schema.png',
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
      $q->p(
'The mammalian liver functions in the stress response, immune response, drug metabolism and protein synthesis. Sex-dependent responses to hepatic stress are mediated by pituitary secretion of growth hormone (GH) and the GH-responsive nuclear factors STAT5a, STAT5b and HNF4-alpha. Whole-genome expression arrays were used to examine sexually dimorphic gene expression in mouse livers.'
      ),
      $q->p(
'This SEGEX database provides public access to previously released datasets from the Waxman laboratory, and provides data mining tools and data visualization to query gene expression across several studies and experimental conditions.'
      ),
      $q->p(
'Developed at Boston University as part of the BE768 Biologic Databases course, Spring 2009, G. Benson instructor. Student developers: Anna Badiee, Eugene Scherba, Katrina Steiling and Niraj Trivedi. Faculty advisor: David J. Waxman.'
      );
    $q->p(
        $q->a(
            { -href => $q->url( -absolute => 1 ) . '?b=schema' },
            'View database schema'
        )
    );
}

1;

__END__


=head1 NAME

SGX::Profile

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



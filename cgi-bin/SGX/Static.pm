package SGX::Static;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;
use SGX::Config;

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
      $q->p('Help pages will be written in parallel with the publication...');
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
      $q->p(
'Segex is a data management and visualization system for storage, basic analysis, and retrieval of gene expression data.'
      ),
      $q->p(
'Segex was conceived by David J. Waxman (Boston University) and developed primarily by Eugene Scherba and Michael McDuffie.'
      ),
      $q->p(
'Initial work on the database was done by Katrina Steiling. Niraj Trivedi contributed some visualization code.'
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



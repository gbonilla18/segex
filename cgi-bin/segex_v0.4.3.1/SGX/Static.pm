package SGX::Static;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;
use SGX::Config qw/$IMAGES_DIR %SEGEX_CONFIG/;

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
        error  => { head => 'error_head' },
        help   => { body => 'help_body' },
        about  => { body => 'default_body' },
        schema => { body => 'schema_body' }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Static
#       METHOD:  error_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Shown on error code 404
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub error_head {
    my $self = shift;
    my $msg;
    if ( my $exception = $self->{_Exception} ) {
        if ( $exception->isa('SGX::Exception::HTTP') ) {
            my $status = int( $exception->status );
            $self->{_prepared_header}->{-status} = $status;
            $msg = sprintf( 'HTTP Error %d: %s', $status, $exception->error );
        }
        elsif ( $exception->isa('SGX::Exception::User') ) {
            $msg = $exception->error;
        }
        else {

            # Behave as if it was Error 500 (Internal Server Error)
            $self->{_prepared_header}->{-status} = 500;
            my $error =
              eval { $exception->error } || "$exception" || 'Unknown error';
            my $propagated_by = $self->{_ExceptionSource} || 'Unknown module';
            my $full_error = "$error (propagated by: $propagated_by)";
            warn $full_error;    ## no critic
            if ( $SEGEX_CONFIG{debug_errors_to_browser} ) {
                $msg = "Internal error: $full_error";
            }
            else {
                $msg = 'Internal error (see log for details)';
            }
        }
    }
    else {
        $msg = 'Unknown error';
    }
    warn $msg;                   # May want to disable this for production
    $self->add_message( { -class => 'error' }, $msg );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Static
#       METHOD:  help_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub help_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->h2('Help'),
      $q->h3('Help Pages'),
      $q->p('Help pages will be written in parallel with the publication...'),
      $q->h3('Installation'),
      $q->p(
        'For detailed installation instructions, see',
        $q->a(
            {
                -title => 'Installation instructions',
                -href =>
                  'https://github.com/escherba/segex/blob/master/INSTALL.md'
            },
            'INSTALL.md'
        ),
        'file on GitHub (you can also find it in the source directory).',
      ),

      # ====== MORE =======
      $q->h3('Links and Source Code'),
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
        'You can download Segex source code from',
        $q->a(
            {
                -href  => 'http://github.com/escherba/segex',
                -title => 'Segex on GitHub'
            },
            'GitHub'
        )
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

    return $q->h2('About'),

      # ==== ABOUT SEGEX =====
      $q->h3('What is Segex?'), $q->p(<<"END_paragraph1"),
Segex is an online data management system designed to help your lab store, view,
and retrieve gene expression data in one centralized location via the web.
END_paragraph1
      $q->p(<<"END_paragraph2"),
You can use Segex to visualize
responses of your microarray probes via basic graphs, enter and search probe-
and gene-specific annotation, or you can perform sophisticated comparisons of
probe sets under different experimental conditions.
END_paragraph2

      # ===== Authors ======
      $q->h3('Authors'), $q->p(<<"END_paragraph3"),
Segex was conceived by David J. Waxman (Boston University) and developed
primarily by Eugene Scherba and Michael McDuffie. Initial work on the database
was done by Eugene Scherba and Katrina Steiling.  Some visualization code was
contributed by Niraj Trivedi.
END_paragraph3

      # ====== Copyright & License =======
      $q->h3('License'),
      $q->p(
'Copyright (c) 2009-2012, Eugene Scherba. This is free software, licensed under:',
        $q->a(
            {
                -href =>
                  'http://www.opensource.org/licenses/artistic-license-2.0.php'
            },
            'The Artistic License 2.0'
        )
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



package SGX::UploadGO;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;
use SGX::Config qw/%SEGEX_CONFIG/;

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

    $self->set_attributes( _permission_level => 'admin' );

    $self->register_actions(
        'Upload Terms' => {
            head => 'UploadTerms_head',
            body => 'UploadTerms_body'
        }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::UploadGO
#       METHOD:  UploadTerms_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub UploadTerms_head {
    my $self = shift;

    # perform actual upload of GO terms
    $self->add_message('Congratulations, the GO terms have been uploaded');
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::UploadGO
#       METHOD:  UploadTerms_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub UploadTerms_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    # show form to upload term definitions
    return $q->h2('Upload / Update GO Terms'),
      $q->start_form(
        -method  => 'POST',
        -enctype => 'multipart/form-data',
        -action  => $q->url( absolute => 1 ) . '?a=uploadGO'
      ),
      $q->dl(
        $q->dt('Path to term_definition.txt:'),
        $q->dd(
            $q->filefield(
                -name => 'file',
                -title =>
                  'File path to term.txt file containing GO term definitions'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -value => 'Upload Term Definitions',
                -class => 'button black bigrounded'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::UploadGO
#       METHOD:  default_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_head {
    my $self = shift;

    my $dbh = $self->{_dbh};
    my $sth = $dbh->prepare(
'select UPDATE_TIME from information_schema.tables where TABLE_SCHEMA=? and TABLE_NAME=?'
    );
    my $rc = $sth->execute( $SEGEX_CONFIG{dbname}, 'go_terms' );
    my ($time) = $sth->fetchrow_array;
    $sth->finish;
    $self->add_message("Last updated on: $time $SEGEX_CONFIG{timezone}");
    return 1;
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

    # here we will show form for updating GO term names and definitions
    return $q->h2('Upload / Update GO Terms'),
      $q->p(
        'To update the gene ontology (GO) terms, follow these simple steps:',
        $q->ol(
            $q->li(
                'Download MySQL version of "termdb" database from '
                  . $q->a(
                    {
                        -target => '_blank',
                        -href =>
'http://www.geneontology.org/GO.downloads.database.shtml',
                        -title => 'Download termdb'
                    },
                    'GO Database Downloads'
                  )
                  . ' page.'
            ),
            $q->li(
'Unzip the .tar.gz file and locate two files: <strong>term.txt</strong> and <strong>term_definition.txt</strong>.'
            ),
            $q->li(
'Upload these files to Segex, starting with <strong>term.txt</strong>.'
            )
        )
      ),
      $q->start_form(
        -method  => 'POST',
        -enctype => 'multipart/form-data',
        -action  => $q->url( absolute => 1 ) . '?a=uploadGO'
      ),
      $q->dl(
        $q->dt('Path to term.txt:'),
        $q->dd(
            $q->filefield(
                -name  => 'file',
                -title => 'File path to term.txt file containing GO terms'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -value => 'Upload Terms',
                -class => 'button black bigrounded'
            )
        )
      ),
      $q->end_form();
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



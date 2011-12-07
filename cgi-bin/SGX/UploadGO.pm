package SGX::UploadGO;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;
use SGX::Abstract::Exception ();
use SGX::Config qw/%SEGEX_CONFIG/;
use Scalar::Util qw/looks_like_number/;

#---------------------------------------------------------------------------
#  Parse term.txt. GO schema:
#
#  CREATE TABLE `term` (
#    `id` int(11) NOT NULL AUTO_INCREMENT,
#    `name` varchar(255) NOT NULL DEFAULT '',
#    `term_type` varchar(55) NOT NULL,
#    `acc` varchar(255) NOT NULL,
#    `is_obsolete` int(11) NOT NULL DEFAULT '0',
#    `is_root` int(11) NOT NULL DEFAULT '0',
#    `is_relation` int(11) NOT NULL DEFAULT '0',
#    PRIMARY KEY (`id`),
#    UNIQUE KEY `acc` (`acc`),
#    UNIQUE KEY `t0` (`id`),
#    KEY `t1` (`name`),
#    KEY `t2` (`term_type`),
#    KEY `t3` (`acc`),
#    KEY `t4` (`id`,`acc`),
#    KEY `t5` (`id`,`name`),
#    KEY `t6` (`id`,`term_type`),
#    KEY `t7` (`id`,`acc`,`name`,`term_type`)
#  ) TYPE=MyISAM AUTO_INCREMENT=35385;
#---------------------------------------------------------------------------
my @term_parser = (

    # term id
    sub {
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) ) {
            return $x;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Second column not numeric at line ' . shift );
        }
    },

    # term name
    sub { my ($x) = shift =~ /(.*)/; return $x },

    # term type
    sub { my ($x) = shift =~ /(.*)/; return $x },

    # GO accession number
    sub {
        if ( shift =~ /^GO:(\d{7})$/ ) {
            my $num = $1 + 0;
            return $num;
        }
        else {
            SGX::Exception::Skip->throw(
                error => 'Cannot parse GO term at line ' . shift );
        }
    }
);

#---------------------------------------------------------------------------
#  Parse term_definition.txt. GO schema:
#
#  CREATE TABLE `term_definition` (
#    `term_id` int(11) NOT NULL,
#    `term_definition` text NOT NULL,
#    `dbxref_id` int(11) DEFAULT NULL,
#    `term_comment` mediumtext,
#    `reference` varchar(255) DEFAULT NULL,
#    UNIQUE KEY `term_id` (`term_id`),
#    KEY `dbxref_id` (`dbxref_id`),
#    KEY `td1` (`term_id`)
#  ) TYPE=MyISAM;
#---------------------------------------------------------------------------
my @term_definition_parser = (

    # term id
    sub {
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) ) {
            return $x;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Second column not numeric at line ' . shift );
        }
    },

    # term definition
    sub { my ($x) = shift =~ /(.*)/; return $x }
);

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
        },
        'Upload Term Definitions' => { head => 'UploadTermDefs_head' }
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

    require SGX::CSV;

    my $outputFileName =
      SGX::CSV::sanitizeUploadWithMessages( $self, 'file', \@term_parser,
        { quote_char => undef } );

    # perform actual upload of GO terms
    $self->add_message( 'Congratulations, the GO terms have been uploaded to '
          . $outputFileName );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::UploadGO
#       METHOD:  UploadTermDefs_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub UploadTermDefs_head {
    my $self = shift;

    require SGX::CSV;
    my $outputFileName = SGX::CSV::sanitizeUploadWithMessages( $self, 'file',
        \@term_definition_parser, { quote_char => undef } );

    $self->add_message(
        'Congratulations, the GO term definitions have been uploaded to '
          . $outputFileName );
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

SGX::UploadGO

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



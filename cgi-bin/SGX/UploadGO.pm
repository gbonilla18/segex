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
#        CLASS:  SGX::UploadGO
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

    $self->set_attributes(
        _permission_level => 'admin',
        _title            => 'Upload GO Terms'
    );

    $self->register_actions(
        'Upload Terms' => {
            head => 'UploadTerms_head',
            body => 'UploadTerms_body'
        },
        'Upload Term Definitions' => {
            head => 'UploadTermDefs_head',
            body => 'UploadTermDefs_body'
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

    require SGX::CSV;
    my ( $outputFileName, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, 'file',
        parser      => \@term_parser,
        csv_in_opts => { quote_char => undef },
        header      => 0
      );

    my $dbh = $self->{_dbh};
    my $sth = $dbh->prepare(<<"END_loadTerms");
LOAD DATA LOCAL INFILE ?
REPLACE
INTO TABLE go_term
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    go_term_id,
    go_name,
    go_term_type,
    go_acc
)
END_loadTerms
    my $recordsUpdated = $sth->execute($outputFileName);
    unlink $outputFileName;

    $self->add_message(
"Success! Found $recordsValid valid entries; affected $recordsUpdated rows in the GO terms table."
    );
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
    my ( $outputFileName, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, 'file',
        parser      => \@term_definition_parser,
        csv_in_opts => { quote_char => undef },
        header      => 0
      );

    my $dbh = $self->{_dbh};

    my $temp_table      = time() . '_' . getppid();
    my $sth_create_temp = $dbh->prepare(<<"END_loadTermDefs_createTemp");
CREATE TEMPORARY TABLE $temp_table (
    go_term_id int(10) unsigned NOT NULL,
    go_term_definition text
) ENGINE=MyISAM
END_loadTermDefs_createTemp

    my $sth = $dbh->prepare(<<"END_loadTermDefs");
LOAD DATA LOCAL INFILE ?
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    go_term_id,
    go_term_definition
)
END_loadTermDefs

    my $sth_update = $dbh->prepare(<<"END_update");
UPDATE go_term INNER JOIN $temp_table USING(go_term_id) 
SET go_term.go_term_definition=$temp_table.go_term_definition
END_update

    $sth_create_temp->execute();
    my $recordsLoaded  = $sth->execute($outputFileName);
    my $recordsUpdated = $sth_update->execute();
    unlink $outputFileName;

    if ( $recordsLoaded != $recordsUpdated ) {
        $self->add_message(
"Warning: Loaded $recordsLoaded records into temporary table but only $recordsUpdated records were updated"
        );
    }
    $self->add_message(
"Success! Found $recordsValid valid entries, updated $recordsUpdated GO term definitions."
    );
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
    return $q->h2('Gene Ontology: Upload Term Definitions (File 2)'),
      $q->p(<<"END_info"),
Now upload the file called <strong>term_definition.txt</strong> from the
archive you downloaded and extracted from the GO webpage. If you skip this step,
you can still use GO annotation, but your text searches will be limited to GO
names.
END_info
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
#       METHOD:  UploadTermDefs_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub UploadTermDefs_body {
    my $self = shift;
    my $q    = $self->{_cgi};
    return $q->p('You have successfully updated GO terms and definitions.');
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
    my $rc = $sth->execute( $SEGEX_CONFIG{dbname}, 'go_term' );
    my ($time) = $sth->fetchrow_array;
    $sth->finish;

    if ( defined $time ) {
        $self->add_message(
"Segex GO term table was last updated on: $time $SEGEX_CONFIG{timezone}"
        );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::UploadGO
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
    return $q->h2('Gene Ontology: Upload Terms (File 1)'),
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



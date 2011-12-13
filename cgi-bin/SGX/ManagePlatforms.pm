package SGX::ManagePlatforms;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use Benchmark qw/timediff timestr/;
use Scalar::Util qw/looks_like_number/;
use SGX::Abstract::Exception ();
require SGX::Model::ProjectStudyExperiment;

my $process = sub {
    my $line_num = shift;
    my $fields   = shift;

    # check total number of fields present
    if ( @$fields < 2 ) {
        SGX::Exception::User->throw(
            error => sprintf(
                "Only %d field(s) found (2 required) at line %d\n",
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
            error => "Cannot parse probe ID at line $line_num" );
    }
    my $go = $fields->[1];
    my @gos;
    while ( $go =~ /\bGO:(\d{7})\b/gi ) {
        push @gos, $1 + 0;
    }

    return [ map { [ $probe_id, $_ ] } @gos ];
};

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
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

# _table_defs: hash with keys corresponding to the names of tables handled by this module.
#
# key:        Fields that uniquely identify rows
# names:      Fields which identify rows in user-readable manner (row name will be
#             formed by concatenating values with a slash)
# fields:      Fields that are filled out on insert/creation of new records.
# view:       Fields to display.
# selectors:  Fields which, when present in CGI::param list, can narrow down
#             output. Format: { URI => SQL }.
# meta:       Additional field info.
        _table_defs => {
            'platform' => {
                item_name => 'platform',
                key       => [qw/pid/],
                resource  => 'platforms',
                base      => [qw/pname def_p_cutoff def_f_cutoff sid file/],
                view      => [qw/pname def_p_cutoff def_f_cutoff/],

                # table key to the left, URI param to the right
                selectors => { sid => 'sid' },
                names     => [qw/pname/],
                meta      => {
                    sid => {
                        label        => 'Species',
                        __type__     => 'popup_menu',
                        __readonly__ => 1,
                        __tie__      => [ species => 'sid' ]
                    },
                    file => {
                        __type__     => 'filefield',
                        __special__  => 1,
                        __optional__ => 1,
                        label        => 'Upload Probes/Annotations'
                    },
                    pid   => { label => 'No.', parser => 'number' },
                    pname => {
                        label      => 'Platform Name',
                        -maxlength => 255,
                        -size      => 55
                    },

                    # def_p_cutoff
                    def_p_cutoff => {
                        label      => 'P-value Cutoff',
                        parser     => 'number',
                        -maxlength => 20,

                        # validate def_p_cutoff
                        __encode__ => sub {
                            my $val = shift;
                            (        looks_like_number($val)
                                  && $val >= 0
                                  && $val <= 1 )
                              or SGX::Exception::User->throw( error =>
                                  'P-value must be a number from 0.0 to 1.0' );
                            return $val;
                        },
                    },

                    # def_f_cutoff
                    def_f_cutoff => {
                        label      => 'Fold-change Cutoff',
                        parser     => 'number',
                        -maxlength => 20,

                        # validate def_f_cutoff
                        __encode__ => sub {
                            my $val = shift;
                            ( looks_like_number($val) && abs($val) >= 1 )
                              or SGX::Exception::User->throw( error =>
'Fold change must be a number <= -1.0 or >= 1.0'
                              );
                            return $val;
                        },
                    },
                },
                lookup => [
                    species      => [ sid => 'sid', { join_type => 'LEFT' } ],
                    probe_counts => [ pid => 'pid', { join_type => 'LEFT' } ],
                    locus_counts => [ pid => 'pid', { join_type => 'LEFT' } ]
                ]
            },
            species => {
                key       => [qw/sid/],
                view      => [qw/sname/],
                names     => [qw/sname/],
                resource  => 'species',
                item_name => 'species',
                meta      => {
                    sname => {
                        __createonly__ => 1,
                        label          => 'Species',
                        -size          => 35,
                        -maxlength     => 255,
                    }
                }
            },
            probe_counts => {
                table => 'probe',
                key   => [qw/pid/],
                view  => [qw/id_count sequence_count/],
                meta  => {
                    id_count => {
                        __sql__ => 'COUNT(rid)',
                        label   => 'Probe Count',
                        parser  => 'number'
                    },
                    sequence_count => {
                        __sql__ => 'COUNT(probe_sequence)',
                        label   => 'Probe Sequences',
                        parser  => 'number'
                    },
                },
                group_by => [qw/pid/]
            },
            locus_counts => {
                table => 'probe',
                key   => [qw/pid/],
                view  => [qw/locus_count/],
                meta  => {
                    locus_count => {
                        __sql__ => 'COUNT(location.rid)',
                        label   => 'Chr. Locations',
                        parser  => 'number'
                    },
                },
                group_by => [qw/pid/],
                join =>
                  [ location => [ rid => 'rid', { join_type => 'LEFT' } ] ]
            },
            'study' => {
                key      => [qw/stid/],
                view     => [qw/description pubmed/],
                base     => [qw/description pubmed/],
                resource => 'studies',
                selectors => {}, # table key to the left, URI param to the right
                names => [qw/description/],
                meta  => {
                    stid => {
                        label      => 'No.',
                        parser     => 'number',
                        __hidden__ => 1
                    },
                    description => { label => 'Description' },
                    pubmed      => {
                        label     => 'PubMed ID',
                        formatter => sub { 'formatPubMed' }
                    }
                },
                lookup     => [ proj_brief => [ stid => 'stid' ] ],
                constraint => [ pid        => sub    { shift->{_id} } ]
            },
            proj_brief => {
                table => 'ProjectStudy',
                key   => [qw/stid prid/],
                view  => [qw/prname/],
                meta  => {
                    prname => {
                        __sql__ => 'project.prname',
                        label   => 'Project(s)'
                    }
                },
                join =>
                  [ project => [ prid => 'prid', { join_type => 'INNER' } ] ]
            },
            'experiment' => {
                key  => [qw/eid/],
                view => [qw/sample1 sample2/],
                base => [],
                selectors => {}, # table key to the left, URI param to the right
                names => [qw/sample1 sample2/]
            },
        },
        _default_table => 'platform',
        _readrow_tables =>
          [ 'study' => { heading => 'Studies on this Platform' } ],

        _ProjectStudyExperiment =>
          SGX::Model::ProjectStudyExperiment->new( dbh => $self->{_dbh} ),

    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
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
        form_assign =>
          { head => 'form_assign_head', body => 'form_assign_body' },
        uploadGO => { head => 'UploadGO_head', body => 'form_assign_body' }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  form_create_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  overrides CRUD::form_create_body
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    return

      # container stuff
      $q->h2(
        $self->format_title(
            'manage ' . $self->pluralize_noun( $self->get_item_name() )
        )
      ),
      $self->body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),
      $q->h3( $self->format_title( 'create new ' . $self->get_item_name() ) ),

      # form
      $self->body_create_update_form(
        mode       => 'create',
        cgi_extras => { -enctype => 'multipart/form-data' }
      );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  UploadGO_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub UploadGO_head {
    my $self = shift;
    require SGX::CSV;
    my ( $outputFileName, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, 'file',
        csv_in_opts => { quote_char => undef },
        header      => 0,
        process     => $process
      );

    my $dbh        = $self->{_dbh};
    my $temp_table = time() . '_' . getppid();

    my $old_AutoCommit = $dbh->{AutoCommit};
    $dbh->{AutoCommit} = 0;

    my $t0 = Benchmark->new();

    my $sth_delete = $dbh->prepare(<<"END_delete");
DELETE go_link FROM go_link 
INNER JOIN probe USING(rid) 
WHERE probe.pid=?
END_delete

    my $sth_create_temp = $dbh->prepare(<<"END_loadTermDefs_createTemp");
CREATE TEMPORARY TABLE $temp_table (
    reporter char(18) NOT NULL,
    go_acc int(10) UNSIGNED NOT NULL
) ENGINE=MEMORY
END_loadTermDefs_createTemp

    my $sth_load = $dbh->prepare(<<"END_loadTermDefs");
LOAD DATA LOCAL INFILE ?
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    reporter,
    go_acc
)
END_loadTermDefs

    my $sth_insert = $dbh->prepare(<<"END_update");
INSERT INTO go_link (rid, go_acc)
SELECT
    probe.rid,
    temptable.go_acc
FROM probe
INNER JOIN $temp_table AS temptable USING(reporter) 
WHERE probe.pid=?
ON DUPLICATE KEY UPDATE go_link.rid=probe.rid, go_link.go_acc=temptable.go_acc
END_update

    my ( $recordsLoaded, $recordsUpdated );
    my $pid = $self->{_id};
    eval {
        $sth_delete->execute($pid);
        $sth_create_temp->execute();
        $recordsLoaded  = $sth_load->execute($outputFileName);
        $recordsUpdated = $sth_insert->execute($pid);
    } or do {
        my $exception = $@;
        $dbh->rollback;
        unlink $outputFileName;

        $sth_create_temp->finish;
        $sth_load->finish;
        $sth_insert->finish;

        if ( $exception and $exception->isa('Exception::Class::DBI::STH') ) {

            # catch dbi::sth exceptions. note: this block catches duplicate
            # key record exceptions.
            $self->add_message(
                { -class => 'error' },
                sprintf(
                    <<"end_dbi_sth_exception",
Error loading data into the database. The database response was:\n\n%s.\n
No changes to the database were stored.
end_dbi_sth_exception
                    $exception->error
                )
            );
        }
        else {
            $self->add_message(
                { -class => 'error' },
'Error loading data into the database. No changes to the database were stored.'
            );
        }
        $dbh->{AutoCommit} = $old_AutoCommit;
        $self->SUPER::readrow_head();
        return 1;
    };
    $dbh->commit;
    $dbh->{AutoCommit} = $old_AutoCommit;
    my $t1 = Benchmark->new();
    unlink $outputFileName;

    $self->add_message(sprintf(<<END_success, timestr(timediff($t1, $t0))));
Success! Found $recordsValid valid entries; created $recordsUpdated links
between probe IDs and GO terms. The operation took %s.
END_success

    $self->SUPER::readrow_head();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
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
        $q->a( { -href => '#uploadGO' }, $q->em('GO Annotation') ) => $q->div(
            { -id => '#uploadGO' },
            $q->h3('Upload/Replace GO Annotation for this Platform'),
            $q->p(<<"END_info"),
Upload a tab-delimited file consisting of probe ids (first column) and GO
annotation (second column) consisting of one or more GO terms (GO:0028371, 
GO:0043901...). Note: this will remove existing GO annotations from this platform
before adding new annotations.
END_info
            $q->pre(<<END_pre),
Probe_ID    GO_term(s)
END_pre
            $q->start_form(
                -method  => 'POST',
                -enctype => 'multipart/form-data',
                -action  => $self->get_resource_uri(
                    b   => 'uploadGO',
                    '#' => 'uploadGO'
                )
            ),
            $q->dl(
                $q->dt('Path to file:'),
                $q->dd(
                    $q->filefield(
                        -name  => 'file',
                        -title => 'File containing probe-GO term annotation'
                    )
                ),
                $q->dt('&nbsp;'),
                $q->dd(
                    $q->submit(
                        -name  => 'b',
                        -value => 'Upload',
                        -title => 'Upload GO annotation',
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

SGX::ManageProjects

=head1 SYNOPSIS

=head1 DESCRIPTION
Module for managing platform table.

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut



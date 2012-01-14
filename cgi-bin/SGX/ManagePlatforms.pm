package SGX::ManagePlatforms;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

require Tie::CPHash;
use Storable qw/freeze thaw/;
use Benchmark qw/timediff timestr/;

use Scalar::Util qw/looks_like_number/;
use SGX::Util qw/car file_opts_html/;
use SGX::Abstract::Exception ();
require SGX::Model::ProjectStudyExperiment;

#---------------------------------------------------------------------------
#  process row in accession number input file
#---------------------------------------------------------------------------
my $process_accnum = sub {
    my $printfun = shift;
    my $line_num = shift;
    my $fields   = shift;

    # check total number of fields present
    if ( @$fields < 2 ) {
        SGX::Exception::User->throw(
            error => sprintf(
                "Only %d field(s) found (2 required) on line %d\n",
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
            error => "Cannot parse probe ID on line $line_num" );
    }
    my @accnums = map { $_ =~ /^(\S+)$/ } split /[,;\s]+/, $fields->[1];

    #return [ map { [ $probe_id, $_ ] } @accnums ];
    if ( @accnums > 0 ) {
        $printfun->( $probe_id, $_ ) for @accnums;
    }
    else {
        $printfun->( $probe_id, undef );
    }
    return 1;
};

#---------------------------------------------------------------------------
#  process row in go link input file
#---------------------------------------------------------------------------
my $process_go = sub {
    my $printfun = shift;
    my $line_num = shift;
    my $fields   = shift;

    # check total number of fields present
    if ( @$fields < 2 ) {
        SGX::Exception::User->throw(
            error => sprintf(
                "Only %d field(s) found (2 required) on line %d\n",
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
            error => "Cannot parse probe ID on line $line_num" );
    }
    my $go = $fields->[1];
    my @gos;
    while ( $go =~ /\bGO:(\d{7})\b/gi ) {
        push @gos, $1 + 0;
    }

    #return [ map { [ $probe_id, $_ ] } @gos ];
    if ( @gos > 0 ) {
        $printfun->( $probe_id, $_ ) for @gos;
    }
    else {
        $printfun->( $probe_id, undef );
    }
    return 1;
};

#---------------------------------------------------------------------------
#  probe parser
#---------------------------------------------------------------------------
my @probe_parser = (

    # Probe ID
    sub {

        # Regular expression for the first column (probe/reporter id) reads as
        # follows: from beginning to end, match any character other than [space,
        # forward/back slash, comma, equal or pound sign, opening or closing
        # parentheses, double quotation mark] from 1 to 18 times.
        if ( shift =~ m/^([^\s,\/\\=#()"]{1,18})$/ ) {
            return $1;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Cannot parse probe ID on line ' . shift );
        }
    },

    sub {

        # Probe Sequence: bring to uppercase
        my $val = shift;
        if ( not defined $val ) {
            return $val;
        }
        elsif ( $val =~ /^([ACGT]*)$/i ) {
            $val = $1;
            if ( length($val) > 100 ) {
                SGX::Exception::User->throw( error =>
                      'Probe sequence length exceeds preset limit on line '
                      . shift );
            }
            else {
                return ( $val ne '' ) ? uc($val) : undef;
            }
        }
        else {
            SGX::Exception::User->throw( error =>
'Probe sequence contains letters not in the alphabet {A, C, G, T} on line '
                  . shift );
        }
    },

    sub {

        # Probe Comment: untaint input value
        my ($x) = shift =~ /(.*)/;
        if ( length($x) > 2047 ) {
            SGX::Exception::User->throw(
                error => 'Probe comment length exceeds preset limit on line '
                  . shift );
        }
        else {
            return $x;
        }
    }
);

#---------------------------------------------------------------------------
#  gene parser
#---------------------------------------------------------------------------
my @gene_parser = (

    # Probe ID
    sub {

        # Regular expression for the first column (probe/reporter id) reads as
        # follows: from beginning to end, match any character other than [space,
        # forward/back slash, comma, equal or pound sign, opening or closing
        # parentheses, double quotation mark] from 1 to 18 times.
        if ( shift =~ m/^([^\s,\/\\=#()"]{1,18})$/ ) {
            return $1;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Cannot parse probe ID on line ' . shift );
        }
    },

    # Gene symbol -- disallow spaces and plus signs
    sub {
        my $x = shift;
        if ( $x =~ /^\s*([^\+\s]*)\s*$/ ) {
            $x = $1;
            return ( $x ne '' ) ? $x : undef;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Invalid gene symbol on line ' . shift );
        }
    },

    # Gene name -- anything allowed
    sub {
        my ($x) = shift =~ /(.*)/;
        return ( $x ne '' ) ? $x : undef;
    }
);

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
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    my $q     = $self->{_cgi};

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
                        label => 'Probes',
                        -title =>
'Upload a file containing a list of probes (with an optional sequence column to the right)',
                        __type__       => 'filefield',
                        __special__    => 1,
                        __optional__   => 1,
                        __extra_html__ => file_opts_html( $q, 'probeseqOpts' )
                          . $q->div(
                            { -class => 'input_container' },
                            $q->input(
                                {
                                    -type    => 'checkbox',
                                    -checked => 'checked',
                                    -name    => 'probe_seq',
                                    -id      => 'check_probe_seq',
                                    -value   => 'Probe Sequence',
                                    -title   => 'Upload probe sequences'
                                }
                            ),
                            $q->input(
                                {
                                    -type  => 'checkbox',
                                    -name  => 'probe_note',
                                    -id    => 'check_probe_note',
                                    -value => 'Probe Note',
                                    -title => 'Upload probe notes'
                                }
                            )
                          )
                          . $q->div(
                            {
                                -class => 'hint visible',
                                -id    => 'annot_probe_hint'
                            },
                            ''
                          )
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
                        __sql__ => 'COUNT(locus.rid)',
                        label   => 'Chr. Locations',
                        parser  => 'number'
                    },
                },
                group_by => [qw/pid/],
                join => [ locus => [ rid => 'rid', { join_type => 'LEFT' } ] ]
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
        uploadGene   => { head => 'UploadGene_head',   body => 'readrow_body' },
        uploadGO     => { head => 'UploadGO_head',     body => 'readrow_body' },
        uploadAccNum => { head => 'UploadAccNum_head', body => 'readrow_body' }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  form_create_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD::form_create_head
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_head {
    my $self = shift;
    push @{ $self->{_js_src_code} }, { -src => 'collapsible.js' };
    return $self->SUPER::form_create_head();
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

    setupCheckboxes({
        checkboxIds: ['check_map_loci', 'check_accnum', 'check_gene_symbols'],
        bannerId:    'annot_genome_hint',
        keyName:     'Probe IDs'
    });

    setupCheckboxes({
        checkboxIds: ['check_probe_seq', 'check_probe_note'],
        bannerId:    'annot_probe_hint',
        keyName:     'Probe IDs'
    });
});
END_SETUPTOGGLES

    return $self->SUPER::readrow_head();
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  UploadAccNum_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub UploadAccNum_head {
    my $self = shift;
    my $q    = $self->{_cgi};

    require SGX::CSV;
    my ( $outputFileName, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, 'file',
        csv_in_opts => { quote_char => undef },
        process     => $process_accnum
      );

    my $dbh            = $self->{_dbh};
    my $temp_table     = time() . '_' . getppid();
    my $old_AutoCommit = $dbh->{AutoCommit};
    $dbh->{AutoCommit} = 0;

    my $t0 = Benchmark->new();

    my $sth_create_temp = $dbh->prepare(<<"END_loadTermDefs_createTemp");
CREATE TEMPORARY TABLE $temp_table (
    reporter char(18) NOT NULL,
    accnum char(20) DEFAULT NULL,
    KEY reporter (reporter),
) ENGINE=MEMORY
END_loadTermDefs_createTemp

    my $sth_load = $dbh->prepare(<<"END_loadTermDefs");
LOAD DATA LOCAL INFILE ?
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    reporter,
    accnum
)
END_loadTermDefs

    my $sth_delete = $dbh->prepare(<<"END_delete");
DELETE accnum 
FROM accnum 
    INNER JOIN probe ON accnum.rid=probe.rid AND probe.pid=?
    INNER JOIN $temp_table USING(reporter)
END_delete

    my $sth_insert = $dbh->prepare(<<"END_insert_accnum");
INSERT INTO accnum (rid, accnum)
SELECT
    probe.rid,
    temptable.accnum
FROM probe
    INNER JOIN $temp_table AS temptable
        ON temptable.reporter=probe.reporter 
        AND NOT ISNULL(temptable.accnum)
        AND probe.pid=?
END_insert_accnum

    my ( $recordsLoaded, $recordsUpdated );
    my $pid = $self->{_id};
    eval {
        $sth_create_temp->execute();
        $recordsLoaded = $sth_load->execute($outputFileName);
        $sth_delete->execute($pid);
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
        $self->readrow_head();
        return 1;
    };
    $dbh->commit;
    $dbh->{AutoCommit} = $old_AutoCommit;
    my $t1 = Benchmark->new();
    unlink $outputFileName;

    $self->add_message(
        sprintf(
            <<END_success,
Success! Found %d valid entries; created %d links between probe IDs and
accession numbers. The operation took %s.
END_success
            $recordsValid, $recordsUpdated, timestr( timediff( $t1, $t0 ) )
        )
    );

    $self->readrow_head();
    return 1;
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
    my $q    = $self->{_cgi};

    require SGX::CSV;
    my ( $outputFileName, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, 'file',
        csv_in_opts => { quote_char => undef },
        process     => $process_go
      );

    my $dbh        = $self->{_dbh};
    my $temp_table = time() . '_' . getppid();

    my $old_AutoCommit = $dbh->{AutoCommit};
    $dbh->{AutoCommit} = 0;

    my $t0 = Benchmark->new();

    my $sth_create_temp = $dbh->prepare(<<"END_loadTermDefs_createTemp");
CREATE TEMPORARY TABLE $temp_table (
    reporter char(18) NOT NULL,
    go_acc int(10) unsigned DEFAULT NULL,
    KEY reporter (reporter)
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

    my $sth_delete = $dbh->prepare(<<"END_delete");
DELETE go_link
FROM go_link 
    INNER JOIN probe ON go_link.rid=probe.rid AND probe.pid=?
    INNER JOIN $temp_table USING(reporter)
END_delete

    my $sth_insert = $dbh->prepare(<<"END_insert_go_link");
INSERT INTO go_link (rid, go_acc)
SELECT
    probe.rid,
    temptable.go_acc
FROM probe
    INNER JOIN $temp_table AS temptable 
        ON temptable.reporter=probe.reporter
        AND NOT ISNULL(temptable.go_acc)
        AND probe.pid=?
END_insert_go_link

    my ( $recordsLoaded, $recordsUpdated );
    my $pid = $self->{_id};
    eval {
        $sth_create_temp->execute();
        $recordsLoaded = $sth_load->execute($outputFileName);
        $sth_delete->execute($pid);
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
        $self->readrow_head();
        return 1;
    };
    $dbh->commit;
    $dbh->{AutoCommit} = $old_AutoCommit;
    my $t1 = Benchmark->new();
    unlink $outputFileName;

    $self->add_message(
        sprintf(
            <<END_success,
Success! Found %d valid entries; created %d links
between probe IDs and GO terms. The operation took %s.
END_success
            $recordsValid, $recordsUpdated, timestr( timediff( $t1, $t0 ) )
        )
    );

    $self->readrow_head();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  UploadGene_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub UploadGene_head {
    my $self = shift;
    my $q    = $self->{_cgi};

    my %gene2reporter;
    tie %gene2reporter, 'Tie::CPHash';
    my $gene_process = sub {
        my $printfun = shift;
        my $line_num = shift;
        my $fields   = shift;

        # check total number of fields present
        if ( @$fields < 2 ) {
            SGX::Exception::User->throw(
                error => sprintf(
                    "Only %d field(s) found (2 required) on line %d\n",
                    scalar(@$fields), $line_num
                )
            );
        }

        # get probe id
        my $probe_id;
        if ( $fields->[0] =~ m/^([^\s,\/\\=#()"]{1,18})$/ ) {
            $probe_id = $1;
        }
        else {
            SGX::Exception::User->throw(
                error => "Cannot parse probe ID on line $line_num" );
        }

        # get gene symbol
        my ($gsymbol) = $fields->[1] =~ /^\s*(.*)\s*$/;
        if ( $gsymbol =~ m/\s/ ) {
            SGX::Exception::User->throw(
                error => 'Gene symbol contains spaces on line ' . shift );
        }

        # get gene name
        my ($gname) = ( $fields->[2] =~ /(.*)/ );

        # at this point, we have $probe_id, $gsymbol, and $gname
        $gsymbol = '' if $gsymbol eq '\N';
        $gname   = '' if $gname   eq '\N';

        my $gene_key = freeze( [ $gsymbol, $gname ] );
        if ( my $val = $gene2reporter{$gene_key} ) {
            push @$val, $probe_id;
        }
        else {
            $gene2reporter{$gene_key} = [$probe_id];
        }
        return 1;
    };

    #---------------------------------------------------------------------------
    # etc
    #---------------------------------------------------------------------------
    require SGX::CSV;
    my ( $outputFileName, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, 'file',
        csv_in_opts => { quote_char => undef },
        process     => $gene_process,
        rewrite     => 0
      );

    my $dbh            = $self->{_dbh};
    my $temp_table     = time() . '_' . getppid();
    my $old_AutoCommit = $dbh->{AutoCommit};
    $dbh->{AutoCommit} = 0;

    my $t0 = Benchmark->new();

    my $sth_create_temp = $dbh->prepare(<<"END_loadTermDefs_createTemp");
CREATE TEMPORARY TABLE $temp_table (
    reporter char(18) NOT NULL,
    accnum char(20) DEFAULT NULL,
    KEY reporter (reporter),
) ENGINE=MEMORY
END_loadTermDefs_createTemp

    my $sth_load = $dbh->prepare(<<"END_loadTermDefs");
LOAD DATA LOCAL INFILE ?
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    reporter,
    accnum
)
END_loadTermDefs

    my $sth_delete = $dbh->prepare(<<"END_delete");
DELETE accnum 
FROM accnum 
    INNER JOIN probe ON accnum.rid=probe.rid AND probe.pid=?
    INNER JOIN $temp_table USING(reporter)
END_delete

    my $sth_insert = $dbh->prepare(<<"END_update");
INSERT INTO accnum (rid, accnum)
SELECT
    probe.rid,
    temptable.accnum
FROM probe
    INNER JOIN $temp_table AS temptable USING(reporter) 
WHERE probe.pid=?
ON DUPLICATE KEY UPDATE accnum.rid=probe.rid, accnum.accnum=temptable.accnum
END_update

    my ( $recordsLoaded, $recordsUpdated );
    my $pid = $self->{_id};
    eval {
        $sth_create_temp->execute();
        $recordsLoaded = $sth_load->execute($outputFileName);
        $sth_delete->execute($pid);
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
        $self->readrow_head();
        return 1;
    };
    $dbh->commit;
    $dbh->{AutoCommit} = $old_AutoCommit;
    my $t1 = Benchmark->new();
    unlink $outputFileName;

    $self->add_message(
        sprintf(
            <<END_success,
Success! Found %d valid entries; created %d links between probe IDs and
accession numbers. The operation took %s.
END_success
            $recordsValid, $recordsUpdated, timestr( timediff( $t1, $t0 ) )
        )
    );

    $self->readrow_head();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  countProbes
#   PARAMETERS:  $pid - [optional] - platform id; if absent, will use
#                                    $self->{_pid}
#      RETURNS:  Count of probes
#  DESCRIPTION:  Returns number of probes that the current platform has
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub countProbes {
    my ( $self, $pid ) = @_;

    my $dbh     = $self->{_dbh};
    my $sth     = $dbh->prepare('SELECT COUNT(*) FROM probe WHERE pid=?');
    my $rc      = $sth->execute($pid);
    my ($count) = $sth->fetchrow_array;
    $sth->finish;

    return $count;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  default_update
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD::default_update
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_update {
    my $self = shift;
    return if not defined $self->{_id};

    eval { $self->{_upload_completed} = $self->uploadProbes( update => 1 ); }
      or do {
        my $exception = $@;
        my $msg = ( defined $exception ) ? "$exception" : '';
        $self->add_message( { -class => 'error' }, "No records loaded. $msg" );
      };

    # show body for "readrow"
    $self->set_action('');
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  default_create
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD::default_create
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_create {
    my $self = shift;
    return if defined $self->{_id};

    eval { $self->{_upload_completed} = $self->uploadProbes( update => 0 ); }
      or do {
        my $exception = $@;
        my $msg = ( defined $exception ) ? "$exception" : '';
        $self->add_message( { -class => 'error' }, "No records loaded. $msg" );

        # show body for form_create again
        $self->set_action('form_create');
        return;
      };

    # Show body for the created platform
    if ( defined $self->{_last_insert_id} ) {

        $self->redirect(
            $self->get_resource_uri( id => $self->{_last_insert_id} ) );
        return 1;

        # Code below results in Platform table to be shown in the Studies
        # section.
        #$self->{_id} = $self->{_last_insert_id};
        #$self->set_action('');
        #$self->register_actions( '' => { body => 'readrow_body' });
        #$self->readrow_head();
        #return;
    }

    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  uploadProbes
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub uploadProbes {
    my $self = shift;
    my %args = @_;

    my $update = $args{update};

    require SGX::CSV;
    my ( $outputFileName, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, 'file',
        csv_in_opts     => { quote_char => undef },
        parser          => \@probe_parser,
        required_fields => 1
      );

    my $dbh            = $self->{_dbh};
    my $temp_table     = time() . '_' . getppid();
    my $old_AutoCommit = $dbh->{AutoCommit};
    $dbh->{AutoCommit} = 0;

    my $t0 = Benchmark->new();

    my $cmd_createPlatform =
      ($update) ? $self->_update_command() : $self->_create_command();

    my $sth_create_temp = $dbh->prepare(<<"END_loadTermDefs_createTemp");
CREATE TEMPORARY TABLE $temp_table (
    reporter char(18) NOT NULL,
    probe_sequence varchar(100) DEFAULT NULL,
    probe_comment varchar(2047) DEFAULT NULL
) ENGINE=MEMORY
END_loadTermDefs_createTemp

    my $sth_load = $dbh->prepare(<<"END_loadTermDefs");
LOAD DATA LOCAL INFILE ?
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    reporter,
    probe_sequence,
    probe_comment
)
END_loadTermDefs

    my $sth_insert_update = ($update)
      ? $dbh->prepare(<<"END_update")
UPDATE probe INNER JOIN $temp_table AS temptable
    ON probe.reporter=temptable.reporter
    AND probe.pid=?
SET probe.probe_sequence=temptable.probe_sequence
SET probe.probe_comment=temptable.probe_comment
END_update
      : $dbh->prepare(<<"END_insert");
INSERT INTO probe (reporter, probe_sequence, probe_comment, pid)
SELECT
    reporter,
    probe_sequence,
    probe_comment,
    ? AS pid
FROM $temp_table
END_insert

    my ( $recordsLoaded, $recordsUpdated );
    my @ret;
    @ret = eval {
        $cmd_createPlatform->();
        my $pid = ($update) ? $self->{_id} : $self->get_last_insert_id();
        $sth_create_temp->execute();
        $recordsLoaded  = $sth_load->execute($outputFileName);
        $recordsUpdated = $sth_insert_update->execute($pid);

        $dbh->commit;
        $self->{_last_insert_id} = $pid if not $update;

        my $t1 = Benchmark->new();
        unlink $outputFileName;

        $self->add_message(
            sprintf(
                <<END_success,
Success! Found %d valid entries; inserted %d probes. The operation took %s.
END_success
                $recordsValid, $recordsUpdated,
                timestr( timediff( $t1, $t0 ) )
            )
        );
        1;
    } or do {
        my $exception = $@;
        $dbh->rollback;
        unlink $outputFileName;

        $sth_create_temp->finish;
        $sth_load->finish;
        $sth_insert_update->finish;

        if ( $exception and $exception->isa('Exception::Class::DBI::STH') ) {

            # catch dbi::sth exceptions. note: this block catches duplicate
            # key record exceptions.
            $self->add_message(
                { -class => 'error' },
                sprintf(
                    <<"end_dbi_sth_exception",
Error loading probes into the database. The database response was:\n\n%s.\n
No changes to the database were stored.
end_dbi_sth_exception
                    $exception->error
                )
            );
        }
        else {
            $self->add_message(
                { -class => 'error' },
'Error loading probes into the database. No changes to the database were stored.'
            );
        }
        ();
    };
    $dbh->{AutoCommit} = $old_AutoCommit;
    return @ret;
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
        $q->a( { -href => '#annotation' }, $q->em('Genomic Annotation') ) =>
          $q->div(
            { -id => '#annotation' },

    #---------------------------------------------------------------------------
    #  Probe locations
    #---------------------------------------------------------------------------
            $q->h3(
                'Upload/Replace Annotation ('
                  . $q->a(
                    { -href => $self->get_resource_uri( b => 'clearAnnot' ) },
                    'clear' )
                  . ')'
            ),
            $q->p(<<"END_info"),
Note: Only information for the probe ids that are included in the file will be
updated. If you wish to fully replace annotation for all existing probes, clear
the annotation first by pressing "clear" above.
END_info
            $q->start_form(
                -method   => 'POST',
                -enctype  => 'multipart/form-data',
                -onsubmit => 'return validate_fields(this, ["fileProbeLoci"]);',
                -action   => $self->get_resource_uri(
                    b   => 'uploadProbeLoci',
                    '#' => 'annotation'
                )
            ),
            $q->dl(
                $q->dt('Path to file:'),
                $q->dd(
                    $q->filefield(
                        -id   => 'fileProbeLoci',
                        -name => 'file',
                        -title =>
                          'File containing probe-accession number annotation'
                    ),
                    file_opts_html( $q, 'probelociOpts' ),
                ),
                $q->dt('Choose columns:'),
                $q->dd(
                    $q->div(
                        { -class => 'input_container' },
                        $q->input(
                            {
                                -type    => 'checkbox',
                                -checked => 'checked',
                                -name    => 'map_loci',
                                -id      => 'check_map_loci',
                                -value   => 'Mapping Locations',
                                -title   => 'Upload mapping locations'
                            }
                        ),
                        $q->input(
                            {
                                -type    => 'checkbox',
                                -checked => 'checked',
                                -name    => 'accnum',
                                -id      => 'check_accnum',
                                -value   => 'Accession Numbers',
                                -title   => 'Upload accession numbers'
                            }
                        ),
                        $q->input(
                            {
                                -type  => 'checkbox',
                                -name  => 'gene_symbols',
                                -id    => 'check_gene_symbols',
                                -value => 'Gene Symbols',
                                -title => 'Upload gene symbols'
                            }
                        )
                    ),
                    $q->div(
                        {
                            -class => 'hint visible',
                            -id    => 'annot_genome_hint'
                        },
                        ''
                    )
                ),

#                $q->dd(
#                    $q->div(
#                        { -class => 'hint visible', -id => 'probeloci_hint' },
#                        $q->p(
#                            'The file should contain the following columns: '
#                        ),
#                        $q->ol(
#                            $q->li('Probe ID'),
#                            $q->li(
#'Mapping Location(s). Example: <strong>chr1:1208765-1208786, chr22:106895-106912</strong>'
#                            ),
#                            $q->li(
#'Accession Number(s). Example: <strong>NM_1023678, AK678920</strong>'
#                            ),
#                            $q->li(
#'Gene Symbol(s). Example: <strong>Akr1, Akr7</strong>'
#                            )
#                        )
#                    ),
#                ),
                $q->dt('&nbsp;'),
                $q->dd(
                    $q->submit(
                        -name  => 'b',
                        -value => 'Upload',
                        -title => 'Upload probe locations',
                        -class => 'button black bigrounded'
                    )
                )
            ),
            $q->end_form,
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



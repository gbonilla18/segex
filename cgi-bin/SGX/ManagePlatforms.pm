package SGX::ManagePlatforms;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use Scalar::Util qw/looks_like_number/;
use SGX::Debug qw/Dumper/;
use SGX::Util qw/car file_opts_html file_opts_columns coord2int/;
use SGX::Abstract::Exception ();
require Data::UUID;
use List::Util qw/sum/;
use SGX::Config qw/$YUI_BUILD_ROOT/;

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
                        __extra_html__ => join(
                            '',
                            file_opts_html( $q, 'probeseqOpts' ),
                            file_opts_columns(
                                $q,
                                id    => 'annot_probe',
                                items => [
                                    probe => {
                                        -checked  => 'checked',
                                        -disabled => 'disabled',
                                        -value    => 'Probe ID'
                                    },
                                    probe_seq => {
                                        -checked => 'checked',
                                        -value   => 'Probe Sequence',
                                    },
                                    probe_note => { -value => 'Probe Note' }
                                ]
                            )
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
                    annot_counts => [ pid => 'pid', { join_type => 'LEFT' } ],
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
                        label   => 'Probes',
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
            annot_counts => {
                table => 'probe',
                key   => [qw/pid/],
                view  => [qw/annot_count/],
                meta  => {
                    annot_count => {
                        __sql__ => 'COUNT(ProbeGene.gid)',
                        label   => 'Annot. Records',
                        parser  => 'number'
                    },
                },
                group_by => [qw/pid/],
                join =>
                  [ ProbeGene => [ rid => 'rid', { join_type => 'LEFT' } ] ]
            },
            locus_counts => {
                table => 'probe',
                key   => [qw/pid/],
                view  => [qw/locus_count/],
                meta  => {
                    locus_count => {
                        __sql__ => 'COUNT(locus.rid)',
                        label   => 'Map. Loci',
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
                        label  => 'No.',
                        parser => 'number',
                    },
                    description => { label => 'Study' },
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
        clearAnnot => { redirect => 'ajax_clear_annot' },
        uploadAnnot => { head => 'UploadAnnot_head', body => 'readrow_body' },
        form_assign =>
          { head => 'form_assign_head', body => 'form_assign_body' },

       #uploadGene   => { head => 'UploadGene_head',   body => 'readrow_body' },
       #uploadGO     => { head => 'UploadGO_head',     body => 'readrow_body' },
       #uploadAccNum => { head => 'UploadAccNum_head', body => 'readrow_body' }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageSpecies
#       METHOD:  ajax_clear_annot
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub ajax_clear_annot {
    my $self = shift;
    return $self->_ajax_process_request(
        sub {
            my $self = shift;
            my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};

            # prepare request only
            my @sth;
            my @param;

            push @sth, $dbh->prepare(<<"END_delete");
DELETE ProbeGene FROM ProbeGene INNER JOIN probe ON probe.pid=? AND ProbeGene.rid=probe.rid
END_delete
            push @param, [ $self->{_id} ];

            push @sth, $dbh->prepare(<<"END_delete");
DELETE locus FROM locus INNER JOIN probe ON probe.pid=? AND locus.rid=probe.rid
END_delete
            push @param, [ $self->{_id} ];

            return sub {
                my @return_codes = map {
                    my $p = shift @param;
                    $_->execute(@$p)
                } @sth;
                $_->finish() for @sth;
                return 1;
            };
        }
    );
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
    my ( $js_src_yui, $js_src_code, $css_src_yui ) =
      @$self{qw{_js_src_yui _js_src_code _css_src_yui}};

    push @$css_src_yui, 'button/assets/skins/sam/button.css';
    push @$js_src_yui,  'button/button-min.js';
    push @$js_src_code,
      ( { -src => 'collapsible.js' }, { -code => <<"END_SETUPTOGGLES" } );
YAHOO.util.Event.addListener(window,'load',function(){
    setupCheckboxes({
        idPrefix:   'annot_probe',
        minChecked: 1
    });
});
END_SETUPTOGGLES

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

    my $clearAnnotURI = $self->get_resource_uri( b => 'clearAnnot' );
    push @$css_src_yui, 'button/assets/skins/sam/button.css';
    push @$js_src_yui,  'button/button-min.js';
    push @$js_src_code,
      ( { -src => 'collapsible.js' }, { -code => <<"END_SETUPTOGGLES" } );
var wait_indicator;
YAHOO.util.Event.addListener('clearAnnot', 'click', function(){
        if (!confirm("Are you sure you want to clear annotation for this platform?\\n\\nWarning: this will clear both probe mapping locations and associated accession numbers and genes.")) {
            return false;
        }
        wait_indicator = createWaitIndicator(wait_indicator, '$YUI_BUILD_ROOT/assets/skins/sam/ajax-loader.gif');
        var callbackObject = {
            success:function(o) {
                wait_indicator.hide();
            },
            failure:function(o) { 
                wait_indicator.hide();
                alert("Clear request failed.");
            },
            scope:this
        };
        wait_indicator.show();
        YAHOO.util.Connect.asyncRequest(
            "POST", 
            "$clearAnnotURI",
            callbackObject,
            null
        );
        return true;
});

YAHOO.util.Event.addListener(window,'load',function(){

    setupCheckboxes({
        idPrefix:   'annot_probe',
        minChecked: 1
    });

    setupCheckboxes({
        idPrefix: 'annot_genome',
        minChecked: 1
    });

});
END_SETUPTOGGLES

    return $self->SUPER::readrow_head();
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  UploadAnnot_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  upload (1) mapping locations, (2) accession numbers, (3) gene
#                symbols.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub UploadAnnot_head {
    my $self = shift;

    my $ret        = $self->readrow_head();
    my $species_id = $self->{_id_data}->{sid};
    my $pid        = $self->{_id};

    my $q                 = $self->{_cgi};
    my $upload_maploci    = defined( $q->param('map_loci') );
    my $upload_chromosome = defined( $q->param('chromosome') );
    my $upload_start      = defined( $q->param('start') );
    my $upload_end        = defined( $q->param('end') );
    my $upload_maploci2   = $upload_chromosome || $upload_start || $upload_end;

    my $upload_accnums = defined( $q->param('accnum') );
    my $upload_symbols = defined( $q->param('gene_symbols') );

    my $process_accnum = sub {
        my $printfun = shift;
        my $line_num = shift;
        my $fields   = shift;

        my ( $print_loci, $print_symbols ) = @$printfun;

        #----------------------------------------------------------------------
        #  get probe id (first column)
        #----------------------------------------------------------------------
        my $probe_id;
        if ( $fields->[0] =~ m/^([^\s,\/\\=#()"]{1,18})$/ ) {
            $probe_id = uc($1);
        }
        else {
            SGX::Exception::User->throw(
                error => "Cannot parse probe ID on line $line_num" );
        }
        my $i = 1;

        #----------------------------------------------------------------------
        #  get mapping locations (second column)
        #----------------------------------------------------------------------
        if ($upload_maploci) {

            # grab locus field
            my $locus = $fields->[$i];
            $i++;

            my @loci;
            while (
                $locus =~ /\b(?:chr|)([^,;\s]+)\s*:\s*([,\d]+)-([,\d]+)\b/g )
            {
                push @loci, [ $1, coord2int($2), coord2int($3) ];
            }
            $print_loci->( $probe_id, @$_ ) for @loci;
        }
        elsif ($upload_maploci2) {

            # use (chromosome, start, end)
            my ( $chr, $start, $end );
            if ($upload_chromosome) {
                $chr = $fields->[$i];
                $chr =~ s/^chr//;
                $i++;
            }
            if ($upload_start) {
                $start = $fields->[$i];
                $i++;
            }
            if ($upload_end) {
                $end = $fields->[$i];
                $i++;
            }
            $print_loci->( $probe_id, $chr, $start, $end );
        }

        #----------------------------------------------------------------------
        #  get accession numbers (third column)
        #----------------------------------------------------------------------
        if ($upload_accnums) {

            # disallow spaces and plus signs
            $print_symbols->( $probe_id, 0, $_ )
              for ( map { $_ =~ /^([^\+\s]+)$/ }
                split( /[,;\s]+/, $fields->[$i] ) );
            $i++;
        }

        #----------------------------------------------------------------------
        # get gene symbols (fourth column)
        #----------------------------------------------------------------------
        if ($upload_symbols) {

            # disallow spaces and plus signs
            $print_symbols->( $probe_id, 1, $_ )
              for ( map { $_ =~ /^([^\+\s]+)$/ }
                split( /[,;\s]+/, $fields->[$i] ) );
            $i++;
        }

        return 1;
    };

    require SGX::CSV;
    my ( $outputFileNames, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, 'file',
        csv_in_opts => { quote_char => undef },
        rewrite     => 2,
        process     => $process_accnum
      );

    my ( $filename_maploci, $filename_symbols ) = @$outputFileNames;

    my $ug = Data::UUID->new();

    #---------------------------------------------------------------------------
    #  add gene symbols
    #---------------------------------------------------------------------------

    if ($upload_symbols) {
        $self->add_message('Loading accession numbers/gene symbols:');
        my $symbol_table = $ug->to_string( $ug->create() );
        $symbol_table =~ s/-/_/g;
        $symbol_table = "tmp$symbol_table";
        my @sth_symbols;
        my @param_symbols;

        push @sth_symbols, <<"END_loadTermDefs_createTemp";
CREATE TEMPORARY TABLE $symbol_table (
    reporter char(18) NOT NULL,
    gtype tinyint(3) unsigned NOT NULL DEFAULT '0',
    gsymbol char(32) DEFAULT NULL,
    KEY reporter (reporter),
    KEY gsymbol (gsymbol)
) ENGINE=MEMORY
END_loadTermDefs_createTemp
        push @param_symbols, [];

        push @sth_symbols, <<"END_loadTermDefs";
LOAD DATA LOCAL INFILE ?
INTO TABLE $symbol_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    reporter,
    gtype,
    gsymbol
)
END_loadTermDefs
        push @param_symbols, [$filename_symbols];

        push @sth_symbols, <<"END_delete";
DELETE ProbeGene 
FROM ProbeGene 
    INNER JOIN probe ON probe.pid=? AND ProbeGene.rid=probe.rid
    INNER JOIN $symbol_table USING(reporter)
END_delete
        push @param_symbols, [$pid];

        push @sth_symbols, <<"END_insert_gene";
INSERT IGNORE INTO gene (sid, gtype, gsymbol)
SELECT
    ? AS sid,
    temptable.gtype,
    temptable.gsymbol
FROM $symbol_table AS temptable
    INNER JOIN probe
        ON probe.pid=?
        AND temptable.reporter=probe.reporter 
END_insert_gene
        push @param_symbols, [ $species_id, $pid ];

        push @sth_symbols, <<"END_insert_ProbeGene";
INSERT IGNORE INTO ProbeGene (rid, gid)
SELECT
    probe.rid,
    gene.gid
FROM $symbol_table AS temptable
    INNER JOIN probe
        ON probe.pid=?
        AND probe.reporter=temptable.reporter 
    INNER JOIN gene
        ON gene.sid=?
        AND gene.gsymbol=temptable.gsymbol
END_insert_ProbeGene
        push @param_symbols, [ $pid, $species_id ];

        SGX::CSV::delegate_fileUpload(
            delegate   => $self,
            statements => \@sth_symbols,
            parameters => \@param_symbols,
            filename   => $filename_symbols
        );
    }

    #---------------------------------------------------------------------------
    #  add mapping locations
    #---------------------------------------------------------------------------

    if ($upload_maploci) {
        $self->add_message('Loading mapping locations:');
        my $maploci_table = $ug->to_string( $ug->create() );
        $maploci_table =~ s/-/_/g;
        $maploci_table = "tmp$maploci_table";
        my @sth_maploci;
        my @param_maploci;

        push @sth_maploci, <<"END_loadTermDefs_createTemp";
CREATE TEMPORARY TABLE $maploci_table (
    reporter char(18) NOT NULL,
    chr varchar(127) NOT NULL,
    start int(10) unsigned NOT NULL,
    end int(10) unsigned NOT NULL
) ENGINE=MEMORY
END_loadTermDefs_createTemp
        push @param_maploci, [];

        push @sth_maploci, <<"END_loadTermDefs";
LOAD DATA LOCAL INFILE ?
INTO TABLE $maploci_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    reporter,
    chr,
    start,
    end
)
END_loadTermDefs
        push @param_maploci, [$filename_maploci];

        push @sth_maploci, <<"END_delete";
DELETE locus 
FROM locus 
    INNER JOIN probe ON locus.rid=probe.rid AND probe.pid=?
    INNER JOIN $maploci_table USING(reporter)
END_delete
        push @param_maploci, [$pid];

        push @sth_maploci, <<"END_insert_gene";
INSERT INTO locus (rid, sid, chr, zinterval)
SELECT
    probe.rid AS rid,
    ? AS sid,
    temptable.chr AS chr,
    LineString(Point(0,temptable.start), Point(0,temptable.end)) AS zinterval
FROM $maploci_table AS temptable
    INNER JOIN probe
        ON probe.pid=?
        AND temptable.reporter=probe.reporter 
END_insert_gene
        push @param_maploci, [ $species_id, $pid ];

        SGX::CSV::delegate_fileUpload(
            delegate   => $self,
            statements => \@sth_maploci,
            parameters => \@param_maploci,
            filename   => $filename_maploci
        );
    }

    return $ret;
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

    my $q             = $self->{_cgi};
    my $filefield     = 'file';
    my $filefield_val = $q->param($filefield);
    if ( defined($filefield_val) and $filefield_val ne '' ) {
        $self->uploadProbes( update => 1, filefield => $filefield );
    }

    # show body for "readrow"
    $self->SUPER::default_update();
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

    my $q             = $self->{_cgi};
    my $filefield     = 'file';
    my $filefield_val = $q->param($filefield);
    if ( defined($filefield_val) and $filefield_val ne '' ) {
        $self->uploadProbes( update => 0, filefield => $filefield );
    }
    else {
        return $self->SUPER::default_create();
    }

    # Show body for the created platform
    if ( defined $self->{_last_insert_id} ) {

        $self->redirect(
            $self->get_resource_uri( id => $self->{_last_insert_id} ) );
        return 1;
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
    my $self      = shift;
    my %args      = @_;
    my $update    = $args{update};
    my $filefield = $args{filefield};

    my $q           = $self->{_cgi};
    my $upload_seq  = defined( $q->param('probe_seq') );
    my $upload_note = defined( $q->param('probe_note') );

    my @probe_parser = (

        # Probe ID
        sub {

        # Regular expression for the first column (probe/reporter id) reads as
        # follows: from beginning to end, match any character other than [space,
        # forward/back slash, comma, equal or pound sign, opening or closing
        # parentheses, double quotation mark] from 1 to 18 times.
            if ( shift =~ m/^([^\s,\/\\=#()"]{1,18})$/ ) {
                return uc($1);
            }
            else {
                SGX::Exception::User->throw(
                    error => 'Cannot parse probe ID on line ' . shift );
            }
        },

        (
            $upload_seq
            ? sub {

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
              }
            : ()
        ),

        (
            $upload_note
            ? sub {

                # Probe Comment: untaint input value
                my ($x) = shift =~ /(.*)/;
                if ( length($x) > 2047 ) {
                    SGX::Exception::User->throw( error =>
                          'Probe comment length exceeds preset limit on line '
                          . shift );
                }
                else {
                    return $x;
                }
              }
            : ()
        )
    );

    require SGX::CSV;
    my ( $outputFileNames, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages(
        $self, $filefield,
        csv_in_opts     => { quote_char => undef },
        parser          => \@probe_parser,
        required_fields => 1
      );

    my ($filename_probes) = @$outputFileNames;

    my $ug         = Data::UUID->new();
    my $temp_table = $ug->to_string( $ug->create() );
    $temp_table =~ s/-/_/g;
    $temp_table = "tmp$temp_table";

    my @sth_probes;
    my @param_probes;

    push @sth_probes,
      sprintf(
        "CREATE TEMPORARY TABLE $temp_table (%s) ENGINE=MEMORY",
        join( ',',
            'reporter char(18) NOT NULL',
            ( $upload_seq  ? 'probe_sequence varchar(100) DEFAULT NULL' : () ),
            ( $upload_note ? 'probe_comment varchar(2047) DEFAULT NULL' : () ) )
      );
    push @param_probes, [];

    push @sth_probes, sprintf(
        <<"END_loadTermDefs",
LOAD DATA LOCAL INFILE ?
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (%s)
END_loadTermDefs
        join( ',',
            'reporter',
            ( $upload_seq  ? 'probe_sequence' : () ),
            ( $upload_note ? 'probe_comment'  : () ) )
    );
    push @param_probes, [$filename_probes];

    push @sth_probes, (
        $update
        ? (
            ( $upload_seq || $upload_note )
            ? sprintf(
                <<"END_update",
UPDATE probe INNER JOIN $temp_table AS temptable
ON probe.reporter=temptable.reporter AND probe.pid=?
SET %s
END_update
                join(
                    ',',
                    (
                        $upload_seq
                        ? 'probe.probe_sequence=temptable.probe_sequence'
                        : ()
                    ),
                    (
                        $upload_note
                        ? 'probe.probe_comment=temptable.probe_comment'
                        : ()
                    )
                )
              )
            : ()
          )
        : sprintf(
            "INSERT INTO probe (%s) SELECT %s FROM $temp_table",
            join( ',',
                'pid',
                'reporter',
                ( $upload_seq  ? 'probe_sequence' : () ),
                ( $upload_note ? 'probe_comment'  : () ) ),
            join( ',',
                '? AS pid',
                'reporter',
                ( $upload_seq  ? 'probe_sequence' : () ),
                ( $upload_note ? 'probe_comment'  : () ) )
        )
    );

    my $exec_command =
        $update
      ? $self->_update_command()
      : $self->_create_command();
    push @param_probes, [
        ( $update && !( $upload_seq || $upload_note ) )

        # nothing
        ? ()

          # execute update/create command and return platform id
        : sub {
            $exec_command->();
            my $insert_id = $self->get_last_insert_id();
            $self->{_last_insert_id} = $insert_id;
            return ( $update ? $self->{_id} : $insert_id );
          }
    ];

    SGX::CSV::delegate_fileUpload(
        delegate   => $self,
        statements => \@sth_probes,
        parameters => \@param_probes,
        filename   => $filename_probes
    );

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
        $q->a( { -href => '#annotation' }, $q->em('Genomic Annotation') ) =>
          $q->div(
            { -id => '#annotation' },

    #---------------------------------------------------------------------------
    #  Probe locations
    #---------------------------------------------------------------------------
            $q->h3(
                'Upload/Replace Annotation',
                $q->button(
                    {
                        -id     => 'clearAnnot',
                        -script => '',
                        -class  => 'plaintext',
                        -value  => '(clear)'
                    }
                )
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
                    b   => 'uploadAnnot',
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
                    file_opts_columns(
                        $q,
                        id    => 'annot_genome',
                        items => [
                            probe => {
                                -checked  => 'checked',
                                -disabled => 'disabled',
                                -value    => 'Probe ID'
                            },
                            map_loci => {
                                -checked => 'checked',
                                -value   => 'Mapping Locations',
                                -title =>
'Mapping Locations (format: chrX:1,283,237-1,283,277 chr15:12,004,558-12,004,599)'
                            },
                            chr    => { -value => 'Chromosome' },
                            start  => { -value => 'Start' },
                            end    => { -value => 'End' },
                            accnum => {
                                -checked => 'checked',
                                -value   => 'Accession Numbers',
                                -title   => 'Accession Numbers (if multiple, must be separated by either commas, semicolons, or white space)'
                            },
                            gene_symbols => {
                                -checked => 'checked',
                                -value   => 'Gene Symbols',
                                -title   => 'Gene Symbols (if multiple, must be separated by either commas, semicolons, or white space)'
                            }
                        ]
                    )
                ),
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



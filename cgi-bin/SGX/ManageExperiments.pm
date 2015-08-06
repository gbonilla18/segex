package SGX::ManageExperiments;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Util qw/file_opts_html file_opts_columns/;
use SGX::Abstract::Exception ();
require SGX::Model::PlatformStudyExperiment;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD::init
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $class = shift;
    my $self  = $class->SUPER::init(@_);

    $self->register_actions(
        form_assign => {
            head => 'form_assign_head',
            body => 'form_assign_body',
            perm => 'user'
        }
    );

    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};
    my $curr_proj = $s->{session_cookie}->{curr_proj};
    my ( $pid, $stid ) = $self->get_id_data();
    $self->set_attributes(

		        _permission_level => 'user',

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
			'StudyExperiment' => {
                key       => [qw/eid stid/],
                base      => [qw/eid stid/],
                join_type => 'INNER'
            },
			'SampleExperiment' => {
				table 	=> "SampleExperiment",
                key       => [qw/eid smid/],
                base      => [qw/eid smid/],
                join_type => 'INNER'
            },
			'sample_brief' => {
				resource  => 'samples',
                item_name => 'sample',
				key       => [qw/smid/],
				view     => [qw/smdesc/],
				names     => [qw/smdesc/],
				table 	=> 'sample',
				join_type => 'LEFT'
			},
			    
            'study_brief' => {

                # this table is used in View All Experiments
                table    => 'study',
                key      => [qw/stid/],
                base     => [qw/description/],
                view     => [qw/description/],
                resource => 'studies',

                # table key to the left, URI param to the right
                names => [qw/description/],
                meta  => {
                    stid        => { label => 'No.', parser => 'number' },
                    description => {
                        label        => 'Study(-ies)',
                        formatter    => sub { 'formatPubMed' },
                        __readonly__ => 1,
                        __sql__ =>
'GROUP_CONCAT(CONCAT(study_brief.description, \' (\', study_brief.pubmed, \')\') SEPARATOR \', \')'
                    }
                }
            },
            'study' => {

                # this table is used in Edit Experiment
                key      => [qw/stid/],
                base     => [qw/description pubmed/],
                view     => [qw/description pubmed/],
                resource => 'studies',

                # table key to the left, URI param to the right
                names => [qw/description/],
                meta  => {
                    stid => { label => 'No.', parser => 'number' },
                    description => { label => 'Study', __readonly__ => 1 },
                    pubmed      => {
                        label        => 'PubMed',
                        __readonly__ => 1,
                        formatter    => sub { 'formatPubMed' }
                    }
                },
                join => [
                    StudyExperiment => [
                        stid => 'stid',
                        { constraint => [ eid => sub { shift->{_id} } ] }
                    ]
                ]
            },
			'sample_filtered' => {
				table  => 'sample_view',
				resource  => 'samples',
                item_name  => 'sample_view',
				base  => [qw/smdesc lpname rsname tname /],
                key  => [qw/smid/],
                view  => [qw/smdesc lpname rsname tname /],
				#    names     => [qw/smdesc lpid rsid tid/],
				names  => [qw/smid/],
				meta  => { 
					smdesc => { label => 'Sample Description' },
								lpname => { label => 'Library Preparation' },
								rsname => { label => 'RNA Category' },
								tname => { label => 'Tissue' },
					},
				join => [
                    SampleExperiment => [
                        smid => 'smid',
	                    { constraint => [ eid => sub { shift->{_id} } ] }
                    ],
                ]
            },
			'sample_filtered1' => {
				table    => 'sample_view',
				resource  => 'samples',
                item_name => 'sample_view',
				base	=> [qw/smdesc lpname rsname tname /],
                key       => [qw/smid/],
                view      => [qw/smdesc lpname rsname tname /],
				#    names     => [qw/smdesc lpid rsid tid/],
				names     => [qw/smid/],
				meta      => { 
						smdesc => { label => 'Sample 1 Description' },
						lpname => { label => 'Library Preparation' },
						rsname => { label => 'RNA Category' },
						tname => { label => 'Tissue' },
					},
				join => [
                    SampleExperiment => [
                        smid => 'smid',
	                    { constraint => [ eid => sub { shift->{_id} } ] }
                    ],
                ]
            },
			'sample_filtered2' => {
				table    => 'sample_view',
				resource  => 'samples',
                item_name => 'sample_view',
				base	=> [qw/smdesc lpname rsname tname /],
                key       => [qw/smid/],
                view      => [qw/smdesc lpname rsname tname /],
				#    names     => [qw/smdesc lpid rsid tid/],
				names     => [qw/smid/],
				meta      => { smdesc => { label => 'Sample 2 Description' },
						lpname => { label => 'Library Preparation' },
						rsname => { label => 'RNA Category' },
						tname => { label => 'Tissue' },
						
						},
				join => [
                    SampleExperiment => [
                        smid => 'smid',
						{ constraint => [ eid => sub { shift->{_id} } ] }
                    ],
                ]
            },
            'platform' => {
                resource  => 'platforms',
                item_name => 'platform',
                key       => [qw/pid/],
                view      => [qw/pname/],
                names     => [qw/pname/],
                meta      => { pname => { label => 'Platform' } },

               #join => [ species => [ sid => 'sid', { join_type => 'LEFT' } ] ]
            },
			
			'sample1' => {
				table    => 'sample1',
				resource  => 'samples',
                item_name => 'sample1',
                key       => [qw/smid1/],
                view      => [qw/smdesc1 lpname1 rsname1 tname1 /],
				#    names     => [qw/smdesc lpid rsid tid/],
				names     => [qw/smid1/],
				meta      => { 
							smdesc1 => { label => 'Sample 1 Description' },
							lpname1 => { label => 'Library Preparation' },
							rsname1 => { label => 'RNA Category' },
							tname1 => { label => 'Tissue' },
						},
            },
			
			'sample2' => {
				table    => 'sample2',
				resource  => 'samples',
                item_name => 'sample2',
                key       => [qw/smid2/],
                view      => [qw/smdesc2 lpname2 rsname2 tname2 /],
				#    names     => [qw/smdesc lpid rsid tid/],
				names     => [qw/smid2/],
				meta      => { smdesc2 => { label => '2 from sample' },
						},
            },
			data_count => {
                table => 'response',
                key   => [qw/eid rid/],
                view  => [qw/probe_count/],
                meta  => {
                    probe_count => {
                        __sql__ => 'COUNT(data_count.rid)',
                        label   => 'Probes',
                        parser  => 'number'
                    },
                },
                group_by => [qw/eid/]
            },
            #species => {
            #    key   => [qw/sid/],
            #    view  => [qw/sname/],
            #    names => [qw/sname/],
            #    meta  => { sname => { label => 'Species' } }
            #},
            'experiment' => {
                item_name => 'experiment',
                key       => [qw/eid/],
                view      => [
                    qw/eid sample1 sample2 ExperimentDescription AdditionalInformation  /
                ],
                resource => 'experiments',
                base     => [
                    qw/sample1 sample2 ExperimentDescription
                      AdditionalInformation s1id s2id pid stid file/ # add smdesc here
                ],

                # table key to the left, URI param to the right
                selectors => { pid => 'pid' },
                names     => [qw/eid sample1 sample2/],
                meta      => {
                    file => {
                        label          => 'Upload Data File',
                        __type__       => 'filefield',
                        __optional__   => 1,
                        __special__    => 1,
                        __extra_html__ => $q->div(
                            file_opts_html( $q, 'fileOpts' ),
                            file_opts_columns(
                                $q,
                                id    => 'datafile',
                                items => [
                                    probe => {
                                        -checked  => 'checked',
                                        -disabled => 'disabled',
                                        -value    => 'Probe ID'
                                    },
                                    ratio => {
                                        -checked => 'checked',
                                        -value   => 'Ratio'
                                    },
                                    fold_change => {
                                        -checked => 'checked',
                                        -value   => 'Fold Change'
                                    },
                                    intensity1 => {
                                        -checked => 'checked',
                                        -value   => 'Intensity-1'
                                    },
                                    intensity2 => {
                                        -checked => 'checked',
                                        -value   => 'Intensity-2'
                                    },
                                    pvalue1 => {
                                        -checked => 'checked',
                                        -value   => 'P-Value 1'
                                    },
                                    pvalue2 => { -value => 'P-Value 2' },
                                    pvalue3 => { -value => 'P-Value 3' },
                                    pvalue4 => { -value => 'P-Value 4' }
                                ]
                            )
                        )
                    },
                    eid => {
                        label        => 'No.',
                        parser       => 'number',
                        __readonly__ => 1
                    },
					s1id => {
                        label      => 'inside meta Sample 1 name',
                        -maxlength => 255,
                        -size      => 35,
						__readonly__ => 1,
					   __extra_html__ =>
'<p class="visible hint">(Typically) the control sample</p>',
                        parser   => 'number',
						__type__ => 'popup_menu',
						__tie__ => [ ( sample_brief=> 's1id' ) ],
					},
					
					s2id => {
                        label      => 'inside meta Sample 2  name',
                        -maxlength => 255,
                        -size      => 35,
						__readonly__ => 1,
					   __extra_html__ =>
'<p class="visible hint">(Typically) the treatmen sample</p>',
                        parser   => 'number',
						__type__ => 'popup_menu',
						__tie__ => [ ( sample_brief=> 's2id' ) ],

					},
                    sample1 => {
                        label      => 'Sample 1 name',
                        -maxlength => 255,
                        -size      => 35,
                        __extra_html__ =>
'<p class="visible hint">(Typically) the control sample</p>'
                    },
                    sample2 => {
                        label      => 'Sample 2 name',
                        -maxlength => 255,
                        -size      => 35,
                        __extra_html__ =>
'<p class="visible hint">(Typically) the experimental sample</p>'
                    },
                    ExperimentDescription => {
                        label        => 'Exp. Description',
                        -maxlength   => 255,
                        -size        => 55,
                        __optional__ => 1,
                    },
                    AdditionalInformation => {
                        label        => 'Additional info',
                        -maxlength   => 255,
                        -size        => 55,
                        __optional__ => 1
                    },

                  
                    # stid here is needed for Study popup in Upload Data page
                    stid => {
                        label          => 'Study',
                        parser         => 'number',
                        __type__       => 'popup_menu',
                        __special__    => 1,
                        __optional__   => 1,
                        __createonly__ => 1
                    },
                    pid => {
                        label    => 'Platform',
                        parser   => 'number',
                        __type__ => 'popup_menu',
                        (
                              ( defined($pid) && $pid =~ /^\d+$/ )
                            ? ()
                            : ( __tie__ => [ ( platform => 'pid' ) ] )
                        ),
                        __readonly__ => 1,
                        __extra_html__ =>
'<p class="hint visible">When uploading data that use probes not previously entered in Segex, you should first set up a new platform.</p>'
                    },
                },
                lookup => [
                    data_count => [ eid => 'eid', { join_type => 'LEFT' } ],
                    (
                        # No need to display platform column if specific
                        # platform is requested.
                        (
                                 defined($pid)
                              && $pid =~ /^\d+$/
                              && !$self->get_dispatch_action() eq 'form_create'
                        ) ? ()
                        : ( 'platform' => [ 'pid' => 'pid' ] )
                    ),
					(
                        (
                            !$self->get_dispatch_action() eq 'form_create'
                        ) ? ()
                        : ( sample_brief      => [  s1id=>'smid'  ])
                    ),
                ],
                join => [
					sample1=> [
                        's1id' => 'smid1',
						{ join_type => 'LEFT' },
						
                     ],
					 sample2=> [
                        's2id' => 'smid2',
						{ join_type => 'LEFT' },
						
                     ],
                    # sample1 => [
                        # 's1id' => 'smid1',
						# { join_type => 'LEFT' },
						
                    # ],

					StudyExperiment => [
                        eid => 'eid',
                        { selectors => { stid => 'stid' } }
                    ],
                    
					study_brief => [
                        'StudyExperiment.stid' => 'stid',
                        { join_type => 'LEFT' }
                    ],
                    (
                        (
                                 defined($curr_proj)
                              && $curr_proj =~ /^\d+$/
                              && ( !defined($stid)
                                || $stid ne '' )
                        )
                        ? (
                            ProjectStudy => [
                                'StudyExperiment.stid' => 'stid',
                                {
                                    join_type  => 'INNER',
                                    constraint => [ prid => $curr_proj ]
                                }
                            ]
                          )
                        : ()
                    ),
                ],
            },
            
        },
        _default_table  => 'experiment',
        _readrow_tables => [
            # 'study' => {
                # heading    => 'Studies Experiment is Assigned to',
                # actions    => { form_assign => 'assign' },
                # remove_row => { verb => 'unassign', table => 'StudyExperiment' }
            # },
			### TODO 6/29 need to fix this part
			# 'sample1' => {
                # heading    => 'Sample in this experiment',
                # actions    => { form_assign => 'assign' },
                # remove_row => { verb => 'unassign', table => 'sample' }
            # },
			 'sample_filtered' => {
                heading    => 'Samples in this experiment',
                 actions    => { form_assign => 'assign' },
                 remove_row => { verb => 'delete', table => 'SampleExperiment' }
             },
			
        ],
        # _readrow_tables => [
           
			# ### TODO 6/29 need to fix this part
			 # 'sample_filtered' => {
                # heading    => 'Samples in this experiment',
                 # actions    => { form_assign => 'assign' },
                 # remove_row => { verb => 'delete', table => 'SampleExperiment' }
             # },
			
			
        # ],
        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} ),
    );

    $self->{_id_data}->{pid}  = $pid;
    $self->{_id_data}->{stid} = $stid;

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  get_id_data
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_id_data {
    my $self    = shift;
    my $q       = $self->{_cgi};
    my $id_data = $self->{_id_data} || {};

    my ( $pid, $stid ) = @$id_data{qw/pid stid/};
    $pid  = $q->param('pid')  if not defined $pid;
    $stid = $q->param('stid') if not defined $stid;

    if ( defined $stid ) {
        my $pse = $self->{_PlatformStudyExperiment};
        if ( not defined $pse ) {
            $pse =
              SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} );
            $pse->init( platform_by_study => 1 );
        }
        my $pid_from_stid = $pse->getPlatformFromStudy($stid);
        $pid = $pid_from_stid if not defined $pid;
        if (   defined($pid_from_stid)
            && $pid_from_stid =~ /^\d+$/
            && defined($pid)
            && $pid =~ /^\d+$/
            && $pid_from_stid != $pid )
        {
            $stid = undef;
        }
    }

    return ( $pid, $stid );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
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
YAHOO.util.Event.addListener(window,'load',function(){
    setupCheckboxes({
        idPrefix: 'datafile',
        minChecked: 1
    });
});
END_SETUPTOGGLES
    return $self->SUPER::readrow_head();
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  form_create_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides SGX::CRUD::form_create_head
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_head {
    my $self = shift;

    # add platform dropdown
    push @{ $self->{_css_src_yui} }, 'button/assets/skins/sam/button.css';
    push @{ $self->{_js_src_yui} },  'button/button-min.js';

    # add platform dropdown
    push @{ $self->{_js_src_code} }, { -src => 'collapsible.js' };

    push @{ $self->{_js_buffer} }, <<"END_SETUPTOGGLES";
YAHOO.util.Event.addListener(window,'load',function(){
    setupToggles('change',
        { 'pid': { 'defined' : ['stid_dt', 'stid_dd'] } }, 
        isDefinedSelection
    );
    setupCheckboxes({
        idPrefix: 'datafile',
        minChecked: 1
    });
});
END_SETUPTOGGLES
    push @{ $self->{_js_src_code} }, { -src => 'PlatformStudyExperiment.js' };
    push @{ $self->{_js_src_code} }, {
        -code => $self->get_pse_dropdown_js(

            # default: show all studies or studies for a specific platform
            platforms         => undef,
            platform_by_study => 1,
            studies           => 1,
            extra_studies =>
              { '' => { description => '@Unassigned Experiments' } }
        )
    };

    $self->SUPER::form_create_head();

    my ( $q, $id_data ) = @$self{qw/_cgi _id_data/};
    my $stid = $id_data->{stid} || '';
    if ( $self->{_upload_completed} ) {
        $self->add_message(
            'The uploaded data were placed in a new experiment under: '
              . $q->a(
                {
                    -href => $q->url( -absolute => 1 )
                      . sprintf(
                        '?a=experiments&pid=%s&stid=%s',
                        $id_data->{pid}, $stid
                      )
                },
                $self->{_PlatformStudyExperiment}
                  ->getPlatformStudyName( $id_data->{pid}, $stid )
              )
        );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  form_create_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Overrides Strategy::CRUD::form_create_body
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
      $q->h3(
        $self->format_title( 'Upload data to a new ' . $self->get_item_name() )
      ),

      # form
      $self->body_create_update_form(
        mode       => 'create',
        cgi_extras => { -enctype => 'multipart/form-data' }
      );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  default_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD default_head
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_head {
    my $self = shift;

    # view all rows
    $self->SUPER::default_head();

    my $s         = $self->{_UserSession};
    my $curr_proj = $s->{session_cookie}->{curr_proj};
    my $stid      = $self->{_id_data}->{stid};

    # add platform dropdown
    push @{ $self->{_js_src_code} }, (
        { -src => 'PlatformStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(

                # default: show all studies or studies for a specific platform
                platforms         => 1,
                studies           => 1,
                platform_by_study => 1,
                extra_platforms   => { all => { pname => '@All Platforms' } },
                extra_studies     => {
                    all => {
                        description => (
                            ( defined($curr_proj) && $curr_proj =~ /^\d+$/ )
                            ? '@Assigned Experiments (All Studies)'
                            : '@All Experiments (All Studies)'
                        )
                    },
                    '' => { description => '@Unassigned Experiments' }
                }
            )
        },
    );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD default_body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {

    # Form HTML for the study table.
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Platform dropdown
    #---------------------------------------------------------------------------
    my $resource_uri = $self->get_resource_uri();
    return $q->h2( $self->{_title} ),
      $self->body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),

      # Resource URI: /studies
      $self->view_start_get_form(),
      $q->dl(
	   $q->dt( $q->label( { -for => 's1id' }, 'Sample 1 (from default_body):' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 's1id',
                -id    => 's1id',
                -title => 'Choose sample',
            )
        ),
        $q->dt( $q->label( { -for => 'pid' }, 'Platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 'pid',
                -id    => 'pid',
                -title => 'Choose platform',
            )
        ),
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 'stid',
                -id    => 'stid',
                -title => 'Choose study',
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $self->view_hidden_resource(),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Load',
                -title => 'Get studies for the selected platform'
            )
        )
      ),
      $q->end_form,

    #---------------------------------------------------------------------------
    #  Table showing all studies in all platforms
    #---------------------------------------------------------------------------
      $q->h3( { -id => 'caption' }, '' ),
      $q->div(
        $q->a( { -id => $self->{dom_export_link_id} }, 'View as plain text' ) ),
      $q->div( { -class => 'clearfix', -id => $self->{dom_table_id} }, '' );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  form_assign_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_assign_head {
    my $self = shift;
    return unless defined $self->{_id};    # _id must be present
    $self->_readrow_command()->();

    push @{ $self->{_js_src_code} },
      (
        { -src => 'PlatformStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(
                platforms              => 1,
                platform_by_experiment => 1,
                studies                => 1
            )
        }
      );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
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
	
	#### added by GB
	#### update other tables (for sample, like library prep, etc.)
	my $sample1field     = 's1id';
	my $sample1field_val = $q->param($sample1field);
	
	my $form_test=join(", ", $sample1field_val);
	 $self->add_message( { -class => 'error' },
                "data from nested form ... or something $form_test" );
	
    my $filefield     = 'file';
    my $filefield_val = $q->param($filefield);
    if ( defined($filefield_val) and $filefield_val ne '' ) {

        # code below should be executed only when upload actually happens
        require SGX::UploadData;
        my $data = SGX::UploadData->new( delegate => $self );
        eval {
            $self->{_upload_completed} =
              $data->uploadData( filefield => 'file', update => 1 );
        } or do {
            my $exception = Exception::Class->caught();
            my $msg =
                 eval { $exception->error }
              || "$exception"
              || '';
            $self->add_message( { -class => 'error' },
                "No records loaded. $msg" );
        };
    }

    # show body for "readrow"
    $self->SUPER::default_update();
    $self->set_action('');
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  default_create
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  override CRUD::default_create
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_create {
    my $self = shift;
    return if defined $self->{_id};

    require SGX::UploadData;
    my $data = SGX::UploadData->new( delegate => $self );

    eval {
        $self->{_upload_completed} =
          $data->uploadData( filefield => 'file', update => 0 );
    } or do {
        my $exception = Exception::Class->caught();
        my $msg =
             eval { $exception->error }
          || "$exception"
          || '';
        $self->add_message( { -class => 'error' }, "No records loaded. $msg" );
    };

    # show body for form_create again
    $self->set_action('form_create');
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  form_assign_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_assign_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Assign Studies to this Experiment
    #---------------------------------------------------------------------------

    return $q->h2( 'Editing Experiment: '
          . $self->{_id_data}->{sample2} . ' / '
          . $self->{_id_data}->{sample1} ),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Experiment' ],
        'create' => [ 'form_assign', 'Assign to Studies' ]
      ),
      $q->h3('Assign to Studies'),
      $q->dl(
        $q->dt( $q->label( { -for => 'pid' }, 'From platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -id       => 'pid',
                -disabled => 'disabled'
            )
        ),
      ),

      # Resource URI: /studies/id
      $q->start_form(
        -accept_charset => 'ISO-8859-1',
        -method         => 'POST',
        -action         => $self->get_resource_uri()
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name => 'stid',
                -id   => 'stid',
                -title =>
qq/You can select multiple studies here by holding down Control or Command key before clicking./,
                -multiple => 'multiple',
                -size     => 7,
                -values   => [],
                -labels   => {}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'table', -value => 'StudyExperiment' ),
            $q->hidden( -name => 'b',     -value => 'assign' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Assign',
                -title => qq/Assign this experiment to selected studies/
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  get_pse_dropdown_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:   # :TODO:10/08/2011 11:42:09:es: Isolate this method into an
#     outside class
#     SEE ALSO:  n/a
#===============================================================================
sub get_pse_dropdown_js {
    my ( $self, %args ) = @_;

    my $pse = $self->{_PlatformStudyExperiment};
    $pse->init(
        platforms => 1,
        %args
    );

    # If a study is set, use the corresponding platform while ignoring the
    # platform parameter.
    my ( $pid, $stid ) = $self->get_id_data();
    $self->{_id_data}->{pid}  = $pid;
    $self->{_id_data}->{stid} = $stid;

    my ( $q, $js ) = @$self{qw/_cgi _js_emitter/};
    return $js->let(
        [
            PlatfStudyExp =>
              $self->{_PlatformStudyExperiment}->get_ByPlatform(),
            currentSelection => [
                'platform' => {
                    elementId => 'pid',
                    element   => undef,
                    selected  => ( ( defined $pid ) ? { $pid => undef } : {} ),
                    updateViewOn => [ sub { 'window' }, 'load' ],
                    updateMethod => sub   { 'populatePlatform' }
                },
                (
                    ( $args{studies} )
                    ? (
                        'study' => {
                            elementId => 'stid',
                            element   => undef,
                            selected  => (
                                  ( defined $stid )
                                ? { $stid => undef }
                                : {}
                            ),
                            updateViewOn =>
                              [ sub { 'window' }, 'load', 'pid', 'change' ],
                            updateMethod => sub { 'populatePlatformStudy' }
                        }
                      )
                    : ()
                ),
                (
                    ( $args{experiments} )
                    ? (
                        'experiment' => {
                            elementId => 'eid',
                            element   => undef,
                            selected  => {},
                            updateViewOn =>
                              [ sub { 'window' }, 'load', 'stid', 'change' ],
                            updateMethod => sub { 'populateStudyExperiment' }
                        }
                      )
                    : ()
                )
            ]
        ],
        declare => 1
    ) . $js->apply( 'setupPPDropdowns', [ sub { 'currentSelection' } ] );
}

1;

__END__

=head1 NAME

SGX::ManageStudies

=head1 SYNOPSIS

=head1 DESCRIPTION
Module for managing experiment table.

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut



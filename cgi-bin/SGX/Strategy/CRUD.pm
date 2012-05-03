package SGX::Strategy::CRUD;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

require Tie::IxHash;
use SGX::Config qw/$IMAGES_DIR $YUI_BUILD_ROOT/;

use SGX::Util qw/inherit_hash tuples notp car cdr list_values equal uniq/;
use SGX::Abstract::Exception ();
use SGX::Debug;

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Override _init
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, @param ) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@param);

    require SGX::Abstract::JSEmitter;
    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );
    $self->set_attributes(
        dom_table_id       => 'crudTable',
        dom_export_link_id => 'crudTable_astext',

        _js_emitter => $js,
        _js_env     => $js->register_var( '_glob', [qw/lookupTables/] ),
        _js_buffer  => [],

        _other   => {},
        _id      => undef,
        _id_data => {}
    );
    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Initialize parts that deal with responding to CGI queries
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    $self->SUPER::init();

    $self->set_attributes( _permission_level => 'user' );

    # :TODO:10/06/2011 16:29:20:es: Include GET/POST dispatching?
    # E.g.:
    #       form_create => { GET => form_create_head, POST => create_default },
    #       form_assign => { _default => form_assign }
    #
    # dispatch table for other requests (returning 1 results in response
    # without a body)
    $self->register_actions(

        # default action
        (
            $self->get_id()
            ? (
                '' => {
                    head => 'readrow_head',
                    body => 'readrow_body'
                }
              )
            : ()
        ),
        form_create =>
          { head => 'form_create_head', body => 'form_create_body' },
        ajax_create => { redirect => 'ajax_create' },
        ajax_update => { redirect => 'ajax_update' },
        ajax_delete => { redirect => 'ajax_delete' },
        assign      => { redirect => 'default_assign' },
        create      => { redirect => 'default_create' },
        update      => { redirect => 'default_update' },
        delete      => { redirect => 'default_delete' }
    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_resource_uri
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Override get_resource_uri such that, if we are dealing with an
#                element in a collection, add element id to the URI.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_resource_uri {
    my ( $self, %args ) = @_;
    return $self->SUPER::get_resource_uri( id => $self->{_id}, %args );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _head_data_table
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _head_data_table {
    my ( $self, $table, %args ) = @_;

    # :TODO:09/17/2011 10:18:14:es: parametrize this method such that it would
    # be possible to have more than one DataTable control per page.

    #---------------------------------------------------------------------------
    #  setup
    #---------------------------------------------------------------------------
    my $item_name    = $self->get_item_name($table);
    my $remove_row   = $args{remove_row} || {};
    my $view_row     = $args{view_row} || {};
    my @editPhrase   = ( ( $view_row->{verb} || 'edit' ), $item_name );
    my @deletePhrase = ( ( $remove_row->{verb} || 'delete' ), $item_name );

    my $js  = $self->{_js_emitter};
    my $s2n = $self->{_this_symbol2name};

    #---------------------------------------------------------------------------
    #  Compiling names to something like _a7, _a0. This way we don't have to
    #  worry about coming up with unique names for the given set.
    #---------------------------------------------------------------------------
    my $wait_indicator_image_url =
      "$YUI_BUILD_ROOT/assets/skins/sam/ajax-loader.gif";
    my $var = $js->register_var(
        '_a',
        [
            qw/data cellUpdater cellDropdown cellDropdownDirect DataTable
              resourceURIBuilder rowNameBuilder deleteDataBuilder DataSource/
        ]
    );

    #---------------------------------------------------------------------------
    #  Find out which field is key field -- createResourceURIBuilder
    #  (Javascript) needs this.
    #---------------------------------------------------------------------------
    $table = $self->{_default_table} unless defined $table;
    my $table_defs = $self->{_table_defs};
    my $table_info = $table_defs->{$table};
    my ( $this_keys, $this_join, $this_name_symbols, $this_resource ) =
      @$table_info{qw/key join names resource/};
    my ( $this_meta, $this_view ) = @$self{qw/_this_meta _this_view/};
    my %resource_extra = (
        ( map { $_ => $_ } @$this_keys[ 1 .. $#$this_keys ] ),
        ( @$this_keys ? ( id => $this_keys->[0] ) : () )
    );

    #---------------------------------------------------------------------------
    #  YUI column definitions
    #---------------------------------------------------------------------------

    my $lookupTables = $self->{_js_env}->{lookupTables};

    my $column = $self->_head_column_def(
        table_info           => $table_info,
        js_emitter           => $js,
        data_table           => $var->{data},
        cell_updater         => $var->{cellUpdater},
        cell_dropdown        => $var->{cellDropdown},
        lookup_tables        => $lookupTables,
        cell_dropdown_direct => $var->{cellDropdownDirect},
        readonly             => $args{readonly}
    );

    my @column_defs = (

        # default table view (default table referred to by an empty string)
        ( map { $column->( [ undef, $_ ] ) } @$this_view ),

        # views in looked-up tables (stored in {_other})
        (
            map {
                my ( $other_table, $fields_this_other ) = @$_;
                my $lookupTable_other = $lookupTables->($other_table);
                map {
                    $column->(
                        [ $other_table, $_, $fields_this_other->[0] ],
                        formatter => $js->apply(
                            'createJoinFormatter',
                            [ $fields_this_other, $lookupTable_other, $_ ]
                        )
                      )
                  } @{ $table_defs->{$other_table}->{view} }
              } tuples( $table_info->{lookup} )
        ),

        # delete row
        (
            ($remove_row)
            ? $column->(
                undef,
                label => $deletePhrase[0],    #join( ' ', @deletePhrase ),
                formatter =>
                  $js->apply( 'createDeleteFormatter', [@deletePhrase] )
              )
            : ()
        ),

        # edit row (optional)
        (
            ($view_row)
            ? $column->(
                undef,
                label     => $editPhrase[0],    #join( ' ', @editPhrase ),
                formatter => $js->apply(
                    'createEditFormatter',
                    [ @editPhrase, $var->{resourceURIBuilder} ]
                )
              )
            : ()
        )
    );

    #---------------------------------------------------------------------------
    #  Which fields can be used to "name" rows -- createRowNameBuilder
    #  (Javascript) needs this
    #---------------------------------------------------------------------------
    my @name_columns = grep { exists $s2n->{$_} } @$this_name_symbols;

    #---------------------------------------------------------------------------
    #  Arguments supplied to createDeleteDataBuilder (Javascript): table - table
    #  to delete from, key - columns that can be used as indeces for deleting
    #  rows.
    #---------------------------------------------------------------------------
    my %del_table_args;
    if ($remove_row) {
        my $del_table = $remove_row->{table} || $table;
        my $del_table_info = $self->{_table_defs}->{$del_table};
        %del_table_args = (
            table => $del_table,
            key   => +{
                map { $_ => $_ }
                grep { exists $s2n->{$_} } @{ $del_table_info->{key} }
            }
        );
    }

    #---------------------------------------------------------------------------
    #  YUI table definition
    #---------------------------------------------------------------------------
    # Need to set a= and id= parameters because otherwise current settings will
    # be used from {_ResourceName} and {_id}.
    my $table_resource_uri = $self->get_resource_uri(
        a  => $this_resource,
        id => undef
    );
    my $onloadLambda = $js->lambda(
        [],
        $js->let(
            [
                $var->{resourceURIBuilder} => $js->apply(
                    'createResourceURIBuilder',
                    [ $table_resource_uri, \%resource_extra ]
                ),
                $var->{rowNameBuilder} => $js->apply(
                    'createRowNameBuilder', [ \@name_columns, $item_name ]
                ),
                (
                    ($remove_row)
                    ? (
                        $var->{deleteDataBuilder} =>
                          $js->apply( 'createDeleteDataBuilder',
                            [ \%del_table_args ] )

                      )
                    : ()
                ),
                $var->{cellUpdater} => $js->apply(
                    'createCellUpdater',
                    [ $var->{resourceURIBuilder}, $var->{rowNameBuilder} ]
                ),
                $var->{cellDropdown} => $js->apply(
                    'createCellDropdown',
                    [ $var->{resourceURIBuilder}, $var->{rowNameBuilder} ]
                ),
                $var->{cellDropdownDirect} => $js->apply(
                    'createCellDropdownDirect',
                    [ $var->{resourceURIBuilder}, $var->{rowNameBuilder} ]
                ),
                $var->{DataTable} => $js->apply(
                    'YAHOO.widget.DataTable',
                    [
                        $self->{dom_table_id},
                        \@column_defs,
                        $js->apply(
                            'newDataSourceFromArrays', [ $var->{data} ]
                        )
                    ],
                    new_object => 1
                )
            ],
            declare => 1
        ),
        $js->apply(
            'subscribeEnMasse',
            [
                $var->{DataTable},
                {

                    # only highlight those cells that have .yui-dt-editable DOM
                    # class
                    cellMouseoverEvent => $js->literal('highlightEditableCell'),

                    # unhighlight all cells
                    cellMouseoutEvent =>
                      $var->{DataTable}->('onEventUnhighlightCell'),
                    linkClickEvent => $js->lambda(

                        # this JS function prevents Cell Editor from showing up
                        # after the link inside the cell has been clicked.
                        [ $js->literal('oArg') ],
                        $js->apply( 'return', [ $js->false ] )
                    ),
                    cellClickEvent =>
                      $var->{DataTable}->('onEventShowCellEditor'),

                    #cellUpdateEvent => $js->apply(
                    #    'createUpdateHandler', []
                    #),
                    (
                        ($remove_row)
                        ? (
                            buttonClickEvent => $js->apply(
                                'createRowDeleter',
                                [
                                    $deletePhrase[0],
                                    (
                                        ( defined $self->{_id} )

                                        # if id, only POST delete requests to
                                        # current URI
                                        ? $js->apply(
                                            'createResourceURIBuilder',
                                            [ $self->request_uri() ]
                                          )

                                          # otherwise, use standard per-row
                                          # resource URI builder
                                        : $var->{resourceURIBuilder}
                                    ),
                                    $var->{deleteDataBuilder},
                                    $var->{rowNameBuilder},
                                    $wait_indicator_image_url
                                ]
                            )
                          )
                        : ()
                    )
                }
            ]
        )
    );

    #---------------------------------------------------------------------------
    #  return text
    #---------------------------------------------------------------------------
    return $js->let(
        [
            $var->{data} => $js->apply(
                'expandJoinedFields',
                [
                    {
                        caption => 'Showing all Studies',
                        records => $self->getJSRecords($table_info),
                        headers => $self->getJSHeaders(), # parametrize by table
                        fields  => [ keys %$s2n ],
                        meta   => $self->_export_meta($this_meta),
                        lookup => $self->{_this_lookup}
                    },
                    $self->{_js_env}->{lookupTables}
                ]
            )
        ],
        declare => 1
      )
      . $js->apply(
        'YAHOO.util.Event.addListener',
        [
            $self->{dom_export_link_id},
            'click',
            $js->literal('export_table'),
            $var->{data},
            $js->true
        ]
      )
      . $js->apply(
        'YAHOO.util.Event.addListener',
        [ $js->literal('window'), 'load', $onloadLambda ],
      );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  dispatch_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch_js {
    my $self = shift;

    $self->_head_init();
    $self->{_title} = $self->format_title(
        'manage ' . $self->pluralize_noun( $self->get_item_name() ) );

    # otherwise we always do one of the three things: (1) dispatch to readall
    # (id not present), (2) dispatch to readrow (id present), (3) redirect if
    # preliminary processing routine (e.g. create request handler) tells us so.
    return if $self->_dispatch_by( $self->get_dispatch_action() => 'redirect' );

    if ( $self->_dispatch_by( $self->get_dispatch_action() => 'head' ) ) {
        $self->_js_dump();
        return 1;
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _js_dump
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _js_dump {
    my $self = shift;
    my ( $js_src_code, $code ) = @$self{qw/_js_src_code _js_buffer/};
    push @$js_src_code, +{ -code => join( "\n", @$code ) };
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _js_dump_lookups
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _js_dump_lookups {
    my $self = shift;
    my ( $js, $js_env, $code, $_other ) =
      @$self{qw/_js_emitter _js_env _js_buffer _other/};
    unshift @$code,
      '' . $js->let( [ $js_env->{lookupTables} => $_other ], declare => 1 );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  get_lookup
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Given a table structure/hash, returns {look-up} component while
#                adding to it all information from {meta}.
#       THROWS:  no exceptions
#     COMMENTS:
# :TODO:09/29/2011 20:27:16:es: Add parameter that would allow us to specify
# which fields exactly get processed. For example, when displaying a table, we
# only need fields from {view}, and if there are fields not in {view} that are
# "tied" to external tables, we don't need to perfom join/look-up queries on
# those other tables when forming HTML page. Note: {key} will always get
# selected together with {view} when displaying a page. When generating a Create
# page, on the other hand, {key} will not be added to {base}. Using {key} and
# {view} lists will also allow us to preserve order...
#
# At the moment, adding key field, e.g. 'pid' to {view} causes numeric output to
# be printed..
#
#     SEE ALSO:  n/a
#===============================================================================
#sub _get_lookup {
#    my ($table_info, $field_list) = @_;
#    $table_info->{lookup} = [] unless defined $table_info->{lookup};
#    my ($fields_meta) = @$table_info{qw/meta/};
#
#    my $table_lookup = [];
#    foreach my $this_field (@$field_list) {
#        my $this_meta = $fields_meta->{$this_field} || {};
#        my $tie_info = $this_meta->{__tie__};
#        push(
#            @$table_lookup,
#            (
#                map { $_->[0] => [ $this_field => $_->[1] ] }
#                  tuples($tie_info)
#            )
#        ) if defined $tie_info;
#    }
#    return $table_lookup;
#}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _export_meta
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  To export {meta} as JSON, we filter out all key-value pairs
#                with keys that begin with dash or underscore.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _export_meta {
    my ( $self, $meta ) = @_;
    $meta = {} unless defined $meta;
    my %export_meta;
    while ( my ( $key, $value ) = each %$meta ) {
        my %export_value;
        while ( my ( $subkey, $subvalue ) = each %$value ) {
            $export_value{$subkey} = $subvalue if $subkey !~ m/^[-_]/;
        }
        $export_meta{$key} = \%export_value;
    }
    return \%export_meta;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  readrow_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readrow_head {
    my $self = shift;

    # default table row
    $self->_readrow_command()->();

    # other tables if any are specified
    foreach ( tuples( $self->{_readrow_tables} ) ) {
        my ( $table => $opts ) = @$_;
        $self->generate_datatable( $table, readonly => 1, %$opts );
    }

    # background image from: http://subtlepatterns.com/?p=703
    push @{ $self->{_css_src_code} }, +{ -code => <<"END_css"};
.yui-skin-sam .yui-navset .yui-content { 
    background-image:url('$IMAGES_DIR/fancy_deboss.png'); 
}
END_css

    push @{ $self->{_css_src_yui} }, ('tabview/assets/skins/sam/tabview.css');
    push @{ $self->{_js_src_yui} },  ('tabview/tabview-min.js');
    my $code = $self->{_js_buffer};
    push @$code, <<"END_onload";
YAHOO.util.Event.addListener(window, 'load', function() {
    var tabView = new YAHOO.widget.TabView('property_editor');
    selectTabFromHash(tabView);
});
END_onload

    $self->_js_dump_lookups();
    $self->_js_populate_dropdowns();    # will use default table
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  default_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_head {
    my $self  = shift;
    my $table = $self->{_default_table};
    my $ret   = $self->generate_datatable(
        $table,
        remove_row => { verb => 'delete' },
        view_row   => { verb => 'edit' }
    );

    $self->_js_dump_lookups();
    return $ret;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  generate_datatable
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub generate_datatable {
    my ( $self, $table,      %args ) = @_;
    my ( $q,    $table_defs, $code ) = @$self{qw/_cgi _table_defs _js_buffer/};
    my $table_info = $table_defs->{$table};

    SGX::Exception::Internal->throw(
        error => "Missing definition for table `$table`" )
      unless defined $table_info;

    $self->_readall_command($table)->();

    # generate all the neccessary Javascript for the YUI DataTable control
    push @$code, $self->_head_data_table( $table, %args );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Show body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch {
    my ($self) = @_;

    # :TRICKY:08/17/2011 13:00:12:es: CGI.pm -nosticky option seems to not be
    # working as intended. See: http://www.perlmonks.org/?node_id=689507. Using
    # delete_all() ensures that param array is cleared and no form field
    # inherits old values.
    my $q = $self->{_cgi};
    $q->delete_all();

    # show body
    my (@body) = $self->_dispatch_by( $self->get_dispatch_action() => 'body' );
    return @body if ( @body > 0 );

    # default actions
    return ( defined $self->{_id} )
      ? $self->readrow_body
      : $self->default_body;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  get_id
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_id {
    my $self = shift;

    # first try private field
    my $id = $self->{_id};
    return $id if defined $id and $id ne '';

    # now try to get id from the CGI object
    my $q = $self->{_cgi};
    $id = $q->url_param('id');
    if ( defined $id and $id ne '' ) {
        $self->{_id} = $id;    # cache the id
        return $id;
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _delete
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_delete {
    my $self = shift;
    eval { $self->_delete_command()->() == 1; } or do {
        my $exception = Exception::Class->caught();
        my $msg = eval { $exception->error } || "$exception";
        $self->add_message( { -class => 'error' }, $msg );
        $self->set_action('');    # show body for "readall"
        return;
    };
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _update
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_update {
    my $self = shift;
    eval { $self->_update_command()->() == 1; } or do {
        my $exception = Exception::Class->caught();
        my $msg = eval { $exception->error } || "$exception";
        $self->add_message( { -class => 'error' }, $msg );
        $self->set_action('');    # show body for "readrow"
        return;
    };
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _assign
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_assign {
    my $self = shift;
    $self->_assign_command()->();
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _create
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_create {
    my $self = shift;
    return if defined $self->{_id};

    eval { $self->_create_command()->() == 1; } or do {
        my $exception = Exception::Class->caught();
        my $msg = eval { $exception->error } || "$exception";
        $self->add_message( { -class => 'error' }, $msg );
        $self->set_action('form_create');    # show body for form_create again
        return;
    };

    # get inserted row id when inserting a new row, then redirect to the
    # newly created resource.
    my $insert_id = $self->get_last_insert_id();
    $self->{_last_insert_id} = $insert_id;
    if ( defined $insert_id ) {
        $self->redirect( $self->get_resource_uri( id => $insert_id ) );
        return 1;                            # redirect (do not show body)
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  get_last_insert_id
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_last_insert_id {
    my $self = shift;
    my $table = shift || $self->{_default_table};

    my $dbh = $self->{_dbh};

    # car() selects first column from the list
    my $id_column = car $self->_select_fields(
        table    => $table,
        fieldset => 'key',
        dealias  => '__sql__'
    );
    return $dbh->last_insert_id( undef, undef, $table, $id_column );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  ajax_delete
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:
# http://stackoverflow.com/questions/2342579/http-status-code-for-update-and-delete/2342589#2342589
#===============================================================================
sub ajax_delete {
    my $self = shift;
    return $self->_ajax_process_request('_delete_command');
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  ajax_update
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub ajax_update {
    my $self = shift;
    return $self->_ajax_process_request('_update_command');
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  ajax_create
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub ajax_create {
    my $self = shift;
    return $self->_ajax_process_request('_create_command');
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _head_column_def
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  PerlCritic: Subroutine "_head_column_def" with high complexity score
#     (36).  Consider refactoring  (Severity: 3)
#     SEE ALSO:  n/a
#===============================================================================
sub _head_column_def {
    my ( $self, %args ) = @_;
    my $_other = $self->{_other};

    my $table_defs = $self->{_table_defs};
    my $table_info = $args{table_info}
      || $table_defs->{ $self->{_default_table} };
    my $meta = $table_info->{meta};

    my %mutable;
    %mutable =
      map { $_ => 1 } $self->_select_fields(
        table    => $table_info,
        fieldset => [
            $self->_select_fields(
                table    => $table_info,
                fieldset => 'view'
            ),
            map { $_->[0] } list_values( @{ $table_info->{lookup} } )
        ],
        omitting => [ '__readonly__', '__special__' ]
      ) if not $args{readonly};

    my $js                   = $args{js_emitter};
    my $data_table           = $args{data_table};
    my $cell_updater         = $args{cell_updater};
    my $cell_dropdown        = $args{cell_dropdown};
    my $lookupTables         = $args{lookup_tables};
    my $cell_dropdown_direct = $args{cell_dropdown_direct};

    my $TRUE  = $js->true;
    my $FALSE = $js->false;

    my $arg_defaults = $args{defaults} || {};
    my %default_column = (
        resizeable => $TRUE,
        %$arg_defaults
    );

    #---------------------------------------------------------------------------
    # Return a function that lets us easily define YUI DataTable columns. The
    # function takes a [ $table, $field ] tuple plus extra options. If $table is
    # empty string, assume it's the main table whose data are stored in
    # $self->{_this...}. Only fields from the main table can be editable.
    #---------------------------------------------------------------------------
    return sub {
        my ( $datum, %extra_definitions ) = @_;
        my ( $mytable, $symbol, $propagate_key ) =
          ( defined $datum ) ? @$datum : ( undef, undef, undef );

        my $index =
            ( defined $symbol )
          ? ( ( defined($mytable) ) ? "$mytable.$symbol" : $symbol )
          : undef;

        my $this_meta =
          ( defined $symbol )
          ? (
              ( defined $mytable )
            ? ( $_other->{$mytable}->{meta}->{$symbol} || {} )
            : ( $meta->{$symbol} || {} )
          )
          : {};

        my $label = $this_meta->{label};

    #---------------------------------------------------------------------------
    #  cell editor (either text or dropdown)
    #---------------------------------------------------------------------------
        my @live_field;

        if ( defined($symbol) ) {
            my $type = $this_meta->{__type__} || 'textfield';

            # add formatter if specified
            if ( my $formatter = $this_meta->{formatter} ) {
                push @live_field, ( formatter => $formatter );
            }

            # add editor
            if (   defined($cell_updater)
                && !defined($mytable)
                && $mutable{$symbol}
                && $type =~ m/^text/ )
            {
                push @live_field,
                  ( editor => $js->apply( $cell_updater, [$symbol] ) );
            }
            elsif (defined($mytable)
                && defined($propagate_key)
                && $mutable{$propagate_key}
                && defined( $table_defs->{$mytable}->{names} )
                && @{ $table_defs->{$mytable}->{names} } == 1
                && $table_defs->{$mytable}->{names}->[0] eq $symbol )
            {

         # display dropdown cell editor in case of the following: (a) we are
         # working with a joined table ($mytable ne ''), (b) key of the joined
         # table is declared mutable in the main table, (c) current field of the
         # joined table is in {names} of joined table, (d) {names} consists of
         # only one field.
                push @live_field,
                  (
                    editor => $js->apply(
                        $cell_dropdown,
                        [ $lookupTables->($mytable), $propagate_key, $symbol ]
                    )
                  );
            }
            elsif (defined($cell_dropdown_direct)
                && ( $type eq 'popup_menu' || $type eq 'checkbox' )
                && defined( $this_meta->{dropdownOptions} ) )
            {
                my $dropdownOptions_ref =
                  $data_table->('meta')->($symbol)->('dropdownOptions');
                push(
                    @live_field,
                    (
                        editor => $js->apply(
                            $cell_dropdown_direct,
                            [ $symbol, $dropdownOptions_ref ]
                        )
                    )
                ) if $mutable{$symbol};
                push @live_field,
                  (
                    formatter => $js->apply(
                        'createRenameFormatter', [$dropdownOptions_ref]
                    )
                  );
            }
        }

  #---------------------------------------------------------------------------
  #  return hash/object
  #---------------------------------------------------------------------------
  # :BUG:09/11/2011 19:46:13:es: Current version of YUI (v2.8...?) has a bug: if
  # two columns have the same key (same data source field), sorting is broken
  # (actually kind of works but with some obvious problems).
        return {
            %default_column,
            ( ( defined $index ) ? ( key => "$index" ) : () ),
            sortable => (
                (
                    defined($symbol)
                      && (
                        !defined($mytable)
                        || (   defined( $table_defs->{$mytable}->{names} )
                            && @{ $table_defs->{$mytable}->{names} } == 1
                            && $table_defs->{$mytable}->{names}->[0] eq
                            $symbol )
                      )
                )
                ? $TRUE
                : $FALSE
            ),
            label => $label,
            @live_field,
            %extra_definitions
        };
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  getJSRecords
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJSRecords {
    my $self = shift;
    my $table = shift || $self->{_default_table};

    my $table_info =
      ( ref $table eq 'HASH' )
      ? $table
      : ( $self->{_table_defs}->{$table} || {} );

    my $key = $table_info->{key}->[0];

    # :TODO:10/26/2011 11:14:13:es: parametrize data by table
    # declare data sources and options
    my $data = $self->{_this_data};    # data source

    # including all columns...
    my $sort_col = $self->{_this_symbol2index}->{$key};    # column to sort on

    # :TRICKY:09/17/2011 17:13:54:es: Using numerical sort for now. In the
    # future it may be a good idea to make sort type (numerical vs string)
    # user-configurable. See http://raleigh.pm.org/sorting.html
    return ( defined $sort_col )
      ? [ sort { $a->[$sort_col] <=> $b->[$sort_col] } @$data ]
      : $data;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  getJSHeaders
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJSHeaders {

    # :TODO:10/26/2011 11:13:53:es: parametrize this by table
    my $self = shift;
    return $self->{_this_index2name};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  lookup_prepare
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Fills out {_other}
#     SEE ALSO:  n/a
#===============================================================================
sub _lookup_prepare {
    my ( $self, $table_info, %args ) = @_;

    # now add all fields on which we are joining if they are absent
    my ( $dbh,       $table_defs ) = @$self{qw/_dbh _table_defs/};
    my ( $this_meta, $lookup )     = @$table_info{qw/meta lookup/};

    my $composite_labels = $args{labels};
    my $fields = $args{fields} || 'base';

    my %lookup_join_sth;    # hash of statement handles for looked-up tables
    my $_other = $self->{_other};

    # limit lookups to fields present in base if base is requested
    my %lookup_fields = map { $_ => 1 } @{ $table_info->{$fields} };
    my @lookup_tuples =
        ( $fields eq 'base' )
      ? ( grep { exists $lookup_fields{ $_->[1]->[0] } } tuples($lookup) )
      : ( tuples($lookup) );

    foreach (@lookup_tuples) {
        my ( $lookup_table_alias, $val )         = @$_;
        my ( $this_field,         $other_field ) = @$val;

        # we ignore {} optional data
        my $opts = $table_defs->{$lookup_table_alias};

        # modify $composite_labels such that fields on which we join are
        # always SELECTed. No need to modify {look-up} here because by
        # definition $this_field already exists in look-up.
        if ( defined($composite_labels)
            && !exists( $composite_labels->{$this_field} ) )
        {
            $composite_labels->{$this_field} =
              $this_meta->{$this_field}->{label};
        }

        my ( $other_key, $other_view, $other_meta, $other_names ) =
          @$opts{qw/key view meta names/};

        # prepend key field(s)
        my $other_select_fields =
          _get_view_labels( [ @$other_key, @$other_view ], $other_meta );

        # :TRICKY:09/28/2011 12:27:23:es: _build_select modifies
        # $other_select_fields
        my ( $lookup_query, $lookup_params ) =
          $self->_build_select( $lookup_table_alias, $other_select_fields,
            $opts );

        #warn $lookup_query;

        $lookup_join_sth{$lookup_table_alias} =
          [ $dbh->prepare($lookup_query), $lookup_params ];

        # fields below will be exported to JS
        $_other->{$lookup_table_alias} = {}
          unless defined $_other->{$lookup_table_alias};
        my $js_store = $_other->{$lookup_table_alias};
        $js_store->{symbol2name} = $other_select_fields;
        $js_store->{symbol2index} =
          _symbol2index_from_symbol2name($other_select_fields);
        $js_store->{index2symbol} = [ keys %$other_select_fields ];
        $js_store->{key}          = $other_key;
        $js_store->{view}         = $other_view;
        $js_store->{names}        = $other_names;
        $js_store->{meta}         = $self->_export_meta($other_meta);
    }

    return \%lookup_join_sth;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _lookup_execute
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _lookup_execute {
    my ( $self, $lookup_join_sth ) = @_;
    my $_other = $self->{_other};
    while ( my ( $otable, $val ) = each %$lookup_join_sth ) {
        my ( $osth, $oparams ) = @$val;
        my $rc = $osth->execute(@$oparams);
        $_other->{$otable}->{index2name} = $osth->{NAME};
        $_other->{$otable}->{records}    = $osth->fetchall_arrayref;
        $osth->finish;
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _readall_command
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _readall_command {
    my ( $self, $table_alias ) = @_;
    $table_alias = $self->{_default_table} unless $table_alias;
    return unless defined $table_alias;

    my ( $dbh, $q, $table_defs ) = @$self{qw{_dbh _cgi _table_defs}};
    my $table_info = $table_defs->{$table_alias};
    return unless $table_info;

    my ( $key, $this_meta, $this_view ) = @$table_info{qw/key meta view/};

    # prepend key fields, preserve order of fields in {view}
    my $composite_labels =
      _get_view_labels( [ @$key, @$this_view ], $this_meta );

    my $new_opts = inherit_hash( { group_by => $key }, $table_info );

    # :TRICKY:09/28/2011 12:25:52:es: _lookup_prepare modifies $composite_labels
    my $lookup_join_sth = $self->_lookup_prepare(
        $new_opts,
        labels => $composite_labels,
        fields => 'view'
    );

    # :TRICKY:09/28/2011 12:26:49:es: _build_select modifies $composite_labels
    # as well as $new_opts
    my ( $query, $params ) =
      $self->_build_select( $table_alias, $composite_labels, $new_opts );

    $self->{_this_symbol2name} = $composite_labels;
    $self->{_this_symbol2index} =
      _symbol2index_from_symbol2name($composite_labels);
    $self->{_this_lookup} = $new_opts->{lookup};
    $self->{_this_view}   = $new_opts->{view};
    $self->{_this_meta}   = $new_opts->{meta};

    #warn $query;
    #warn Dumper($params);

    my $sth = $dbh->prepare($query);

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {

        # main query execute
        my $rc = $sth->execute(@$params);
        $self->{_this_index2name} = $sth->{NAME};
        $self->{_this_data}       = $sth->fetchall_arrayref;
        $sth->finish;

        $self->_lookup_execute($lookup_join_sth);

        return $rc;
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _get_view_labels
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _get_view_labels {
    my ( $view, $meta ) = @_;
    my %ret;
    my $ret_t =
      tie( %ret, 'Tie::IxHash', map { $_ => $meta->{$_}->{label} } @$view );
    return \%ret;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _symbol2index_from_symbol2name
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _symbol2index_from_symbol2name {
    my $symbol2name = shift;
    my $i           = 0;
    my %symbol2index;
    my $symbol2index_t =
      tie( %symbol2index, 'Tie::IxHash',
        map { $_ => $i++ } keys %$symbol2name );
    return \%symbol2index;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _valid_SQL_identifier
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:
#     http://www.postgresql.org/docs/current/static/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS
#===============================================================================
sub _valid_SQL_identifier {
    return shift =~ m/^[a-zA-Z_][0-9a-zA-Z_\$]*$/;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _build_predicate
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _build_predicate {
    my ( $self, $table_alias => $obj, $prefix ) = @_;

    my @pred_and;
    my @exec_params;
    my @constr;
    my $mod_join_type;

    my $clear_constr = 0;
    my $dbh          = $self->{_dbh};

    foreach ( tuples( $obj->{constraint} ) ) {
        my ( $field, $value ) = @$_;
        $field = "$table_alias.$field"
          if ( $field !~ m/\./ );
        if ( ref $value eq 'CODE' ) {
            push @pred_and,    "$field=?";
            push @exec_params, $value->($self);
        }
        elsif ( defined $value ) {
            push @pred_and, "$field=" . $dbh->quote($value);
        }
        else {
            push @pred_and, "$field IS NULL";
        }
    }

    # if $other_table_defs->{selectors} has a selector field set to empty
    # string (denoting NULL) in the CGI parameter array and that field is
    # one of key fields in that table (key fields will always be NOT NULL),
    # the join type will be changed from INNER to LEFT and a WHERE predicate
    # component will be emitted: table.field IS NULL.
    my $q         = $self->{_cgi};
    my $other_sel = $obj->{selectors} || {};
    my $other_key = $obj->{key} || [];
    my %selectors = %$other_sel;
    if ( lc($prefix) eq 'and' ) {
        foreach my $special_field ( grep { defined } @$other_sel{@$other_key} )
        {
            my $val = $q->param($special_field);
            if ( defined($val) && $val eq '' ) {

                # find unassigned records
                $mod_join_type = 'LEFT';
                push @constr, ( "$table_alias.$special_field" => undef );
                delete $selectors{$special_field};
            }
            elsif ( !defined($val) || $val !~ /^\d+$/ ) {

                # find all records
                $mod_join_type = 'LEFT';
                $clear_constr  = 1;
            }
        }
    }
    while ( my ( $uri_sel, $sql_sel ) = each %selectors ) {
        foreach (
            map { ( $_ ne '' ) ? $_ : undef }
            grep { $_ ne 'all' } $q->param($uri_sel)
          )
        {
            push @pred_and,    "$table_alias.$sql_sel=?";
            push @exec_params, $_;
        }
    }

    my $pred =
      ( ( @pred_and > 0 ) ? "$prefix " : '' ) . join( ' AND ', @pred_and );

    return ( $pred, \@exec_params, \@constr, $mod_join_type, $clear_constr );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _build_join
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _build_join {
    my ( $self, $table_alias => $cascade ) = @_;

    my $table_defs = $self->{_table_defs};

    my @query_components;
    my @exec_params;

    foreach ( tuples( $cascade->{join} ) ) {
        my ( $other_table_alias, $info ) = @$_;

        my ( $this_field, $other_field, $opts ) = @$info;
        $this_field = "$table_alias.$this_field"
          if ( $this_field !~ m/\./ );

        my $other_table_defs = $table_defs->{$other_table_alias} || {};

        my $new_opts = inherit_hash( $opts, $other_table_defs );

        my $other_table = $new_opts->{table};
        $other_table =
          ( !defined($other_table) || $other_table eq $other_table_alias )
          ? $other_table_alias
          : "$other_table AS $other_table_alias";

        my ( $join_pred, $join_params, $constr, $mod_join_type, $clear_constr )
          = $self->_build_predicate(
            $other_table_alias => $new_opts,
            'AND'
          );

        if ($clear_constr) {
            $cascade->{constraint} = [];
        }
        else {
            push @{ $cascade->{constraint} }, @$constr;
        }

        my $join_type = $new_opts->{join_type} || 'LEFT';
        $join_type = $mod_join_type if defined $mod_join_type;

        if ( $join_type ne '' ) {
            my $pred =
"$join_type JOIN $other_table ON $this_field=$other_table_alias.$other_field";
            push @query_components, "$pred $join_pred";
            push @exec_params,      @$join_params;
        }
    }
    return ( join( ' ', @query_components ), \@exec_params );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _build_select_fields
#   PARAMETERS:  ????
#      RETURNS:  hash: sql => alias
#  DESCRIPTION:  Pull select fields from {view} of joined tables
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _build_select_fields {
    my ( $self, $symbol2name, $table_alias => $cascade ) = @_;

    my ( $this_view, $this_meta ) = @$cascade{qw/view meta/};
    my $table_defs = $self->{_table_defs};

    # not using this_table->{view} here because may need extra fields for
    # lookups not present in the {view}.
    my %ret;
    my $ret_t = tie( %ret, 'Tie::IxHash' );
    %ret =
      map {
        my $field_meta = $this_meta->{$_}       || {};
        my $sql_col    = $field_meta->{__sql__} || $_;
        (
            _valid_SQL_identifier($sql_col)
            ? "$table_alias.$sql_col"
            : $sql_col
          ) => $symbol2name->{$_}
      } keys %$symbol2name;

    foreach ( tuples( $cascade->{join} ) ) {
        my ( $other_table_alias, $info ) = @$_;
        my $other_table_defs = $table_defs->{$other_table_alias} || {};
        my $new_opts = inherit_hash( $info->[2], $other_table_defs );
        my ( $other_view, $other_meta ) = @$new_opts{qw/view meta/};

        foreach my $field_alias (@$other_view) {
            my $field_meta = $other_meta->{$field_alias} || {};
            my $sql_col    = $field_meta->{__sql__}      || $field_alias;
            my $symbol =
              _valid_SQL_identifier($sql_col)
              ? "$other_table_alias.$sql_col"
              : $sql_col;
            my $label = $field_meta->{label} || $field_alias;

            # do not select the same data twice
            if ( not exists $ret{$symbol} ) {
                $symbol2name->{$field_alias} = $label;
                $ret{$symbol} = $label;

                # also modify cascade {view} and {meta}
                push @$this_view, $field_alias;
                $field_meta->{__readonly__} = 1;
                $this_meta->{$field_alias} = $field_meta;
            }
        }
    }
    return \%ret;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _build_select
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _build_select {
    my ( $self, $table_alias, $symbol2name, $cascade ) = @_;
    my $dbh = $self->{_dbh};

    my $table = $cascade->{table} || $table_alias;
    my $meta  = $cascade->{meta}  || {};

    my @query_components;
    my @exec_params;

    # SELECT
    my $select_hash =
      $self->_build_select_fields( $symbol2name, $table_alias => $cascade );
    push @query_components, 'SELECT ' . join(
        ',',
        map {
            my $alias = $select_hash->{$_};
            $_
              . (
                ( defined $alias and $_ ne $alias )
                ? ' AS ' . $dbh->quote($alias)
                : ''
              )
          } keys %$select_hash
      )
      . ' FROM '
      . ( ( $table ne $table_alias ) ? "$table AS $table_alias" : $table );

    # JOINS
    my ( $join_pred, $join_params ) =
      $self->_build_join( $table_alias => $cascade );
    push @query_components, $join_pred;
    push @exec_params,      @$join_params;

    # WHERE
    my ( $where_pred, $where_params ) =
      $self->_build_predicate( $table_alias => $cascade, 'WHERE' );
    push @query_components, $where_pred;
    push @exec_params,      @$where_params;

    # GROUP BY
    if ( my $group_by = $cascade->{group_by} ) {
        push @query_components,
          'GROUP BY ' . join( ',', map { "$table_alias.$_" } @$group_by );
    }

    my $query = join( ' ', @query_components );
    return ( $query, \@exec_params );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _readrow_command
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _readrow_command {
    my ( $self, $table_alias ) = @_;
    my $id = $self->{_id};
    return unless defined $id;

    $table_alias = $self->{_default_table} unless $table_alias;
    return unless defined $table_alias;

    my ( $dbh, $q, $table_defs ) = @$self{qw{_dbh _cgi _table_defs}};
    my $table_info = $table_defs->{$table_alias};
    return unless $table_info;

    my @key = $self->_select_fields(
        table    => $table_info,
        fieldset => 'key',
        dealias  => '__sql__'
    );
    return if @key != 1;

    my $table = $table_info->{table} || $table_alias;
    my $predicate = join( ' AND ', map { "$_=?" } @key );

    my $read_fields = join(
        ',',
        $self->_select_fields(
            table => $table_info,

            # concatenate name and base field sets, eliminating duplicates
            fieldset =>
              [ uniq( @{ $table_info->{base} }, @{ $table_info->{names} } ) ],
            omitting => '__special__',
            dealias  => '__sql__'
        )
    );
    my $query =
      "SELECT $read_fields FROM $table AS $table_alias WHERE $predicate";

    my $lookup_join_sth =
      $self->_lookup_prepare( $table_info, fields => 'base' );

    my $sth = $dbh->prepare($query);

    my @params = ( $id, ( map { $q->param($_) } cdr @key ) );

    #warn $query;
    #warn Dumper( \@params );

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {
        my $rc = $sth->execute(@params);
        $self->{_id_data} = $sth->fetchrow_hashref;
        $sth->finish;

        $self->_lookup_execute($lookup_join_sth);

        return $rc;
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _delete_command
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _delete_command {
    my $self = shift;
    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};
    my $table = car( $q->param('table') ) || $self->{_default_table};
    return unless defined $table;

    # :TODO:10/26/2011 11:22:52:es: check whether $table or $table_alias should
    # be used here
    my $table_info = $self->{_table_defs}->{$table};
    return unless $table_info;

    my @key = $self->_select_fields(
        table    => $table_info,
        fieldset => 'key',
        dealias  => '__sql__'
    );
    my $predicate = join( ' AND ', map { "$_=?" } @key );
    my $query     = "DELETE FROM $table WHERE $predicate";
    my @params    = ( $self->{_id}, ( map { $q->param($_) } cdr @key ) );

    my $sth = $dbh->prepare($query);

    my $old_AutoCommit = $dbh->{AutoCommit};
    $dbh->{AutoCommit} = 0;

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {
        my $rc = eval { $sth->execute(@params) } or do {
            my $exception = Exception::Class->caught();
            $dbh->rollback;
            $sth->finish;
            $dbh->{AutoCommit} = $old_AutoCommit;
            if ($exception) {
                if ( eval { $exception->can('rethrow') } ) {
                    $exception->rethrow();
                }
                else {
                    SGX::Exception::Internal->throw( error => "$exception" );
                }
            }
            else {
                return 0;
            }
        };
        $dbh->commit;
        $sth->finish;
        $dbh->{AutoCommit} = $old_AutoCommit;
        return $rc;
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _assign_command
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _assign_command {
    my ($self) = @_;
    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};
    my $table = car $q->param('table');
    return unless defined $table;

    # :TODO:10/26/2011 11:23:21:es: check whether $table or $table_alias
    # should be used here
    my $table_info = $self->{_table_defs}->{$table};
    return unless $table_info;

    # We do not support creation queries on resource links that correspond to
    # elements (have ids) when database table has one key or fewer.
    my $id  = $self->{_id};
    my @key = $self->_select_fields(
        table    => $table_info,
        fieldset => 'key',
    );
    return if ( !defined($id) || @key != 2 );

    my @dealiased_key = $self->_select_fields(
        table    => $table_info,
        fieldset => \@key,
        dealias  => '__sql__'
    );

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    # Note: we make exception when inserting a record when resource id is
    # already present: in those cases we create links.

    my $query = sprintf(
        "INSERT IGNORE INTO $table (%s) VALUES (%s)",
        join( ',', @dealiased_key ),
        join( ',', map { '?' } @dealiased_key )
    );
    my $sth = $dbh->prepare($query);

    my @param_set = ( $q->param( $key[1] ) );

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {
        my $rc = 0;
        foreach (@param_set) {
            $rc += $sth->execute( $id, $_ );
        }
        $sth->finish;
        return $rc;
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _create_command
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _create_command {
    my $self = shift;
    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};
    my $table = car( $q->param('table') ) || $self->{_default_table};
    return unless defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return unless $table_info;

    # We do not support creation queries on resource links that correspond to
    # elements (have ids) when database table has one key or fewer.
    my $id  = $self->{_id};
    my $key = $table_info->{key};
    return if defined $id and @$key < 2;

    my @fields = $self->_select_fields(
        table    => $table_info,
        omitting => '__special__',
        fieldset => 'base'
    );

    my @dealiased_fields = $self->_select_fields(
        table    => $table_info,
        fieldset => \@fields,
        dealias  => '__sql__'
    );

    my $query = sprintf(
        "INSERT INTO $table (%s) VALUES (%s)",
        join( ',', @dealiased_fields ),
        join( ',', map { '?' } @dealiased_fields )
    );
    my $sth = $dbh->prepare($query);

    my $translate_val =
      $self->_get_param_values( $table_info->{meta}, 'create' );

    my @params =
        ( defined $id )
      ? ( $id, map { $translate_val->($_) } cdr @fields )
      : map { $translate_val->($_) } @fields;

    #warn $query;
    #warn Dumper(\@params);

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {
        my $rc = $sth->execute(@params);
        $sth->finish;
        return $rc;
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _get_param_values
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _get_param_values {
    my ( $self, $meta, $mode ) = @_;
    my $q = $self->{_cgi};
    return sub {
        my $param     = shift;
        my @result    = $q->param($param);
        my $this_meta = $meta->{$param} || {};
        my $type      = $this_meta->{__type__} || '';
        if ( $type eq 'checkbox' ) {
            return ( @result > 1 ) ? 1 : 0;
        }
        else {
            my $label = $this_meta->{label} || $param;

            # confirmation-specific check (when the same field has to be typed
            # in twice by the user).
            SGX::Exception::User->throw(
                error => "You need to enter the same $label value twice" )
              if (
                   $this_meta->{__confirm__}
                && $mode eq 'create'
                && ( @result < 2
                    || !equal(@result) )
              );

            return _process_val( $label => $this_meta, car(@result) );
        }
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _process_val
#   PARAMETERS:  {} - meta
#                SCALAR - value
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _process_val {
    my $label     = shift;
    my $this_meta = shift;
    my $val       = shift;
    my $parser    = $this_meta->{parser};

    # preventing not only empty strings but also anything which consists
    # entirely of white space.
    SGX::Exception::User->throw( error =>
          "You did not provide a value for the required field `$label'\n" )
      if ( !$this_meta->{__optional__}
        && ( !defined($val) || $val =~ /^\s*$/ ) );

    if ( my $encoder = $this_meta->{__encode__} ) {
        return $encoder->($val);
    }

    # strip spaces from beginning and end
    return undef unless defined $val;
    $val =~ m/^\s*(.+)\s*/;
    my $clean_val = $1;
    $clean_val = '' unless defined $clean_val;

    # for numeric types, interpret empty strings as NULL
    if (   defined($parser)
        && $parser eq 'number'
        && $clean_val eq '' )
    {
        return undef;
    }
    else {
        return $clean_val;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  prepare_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub prepare_head {
    my $self = shift;
    my $dbh  = $self->{_dbh};
    my $ret  = $self->SUPER::prepare_head();

    # do not disconnect before session data are committed
    $dbh->disconnect() if defined $dbh;

    return $ret;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _select_fields
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _select_fields {
    my ( $self, %args ) = @_;

    # step -1: set up table
    my $table = $args{table} || $self->{_default_table};
    my $table_info =
      ( ref $table eq 'HASH' )
      ? $table
      : ( $self->{_table_defs}->{$table} || {} );

    my $meta = $table_info->{meta} || {};

    # step 0: set up fieldset
    my $list = $args{fieldset} || 'base';
    my $fields =
      ( ref $list eq 'ARRAY' )
      ? $list
      : ( $table_info->{$list} || [] );

    # step 1: omit filter
    my $filter = sub {
        my $filter_on = $args{omitting};
        return ($filter_on)
          ? (
            ( ref $filter_on eq 'ARRAY' )
            ? (
                grep {
                    my $this_meta = $meta->{$_};
                    !defined($this_meta)
                      || notp( @$this_meta{@$filter_on} )
                  } @_
              )
            : grep { !defined( $meta->{$_} ) || !$meta->{$_}->{$filter_on} } @_
          )
          : @_;
    };

    # step 2: dealias
    my $dealias = sub {
        my $dealias_on = $args{dealias};
        return ($dealias_on)
          ? (
            map {
                    ( defined $meta->{$_} )
                  ? ( $meta->{$_}->{$dealias_on} || $_ )
                  : $_
              } @_
          )
          : @_;
    };

    return $dealias->( $filter->(@$fields) );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _meta_get_cgi
#   PARAMETERS:  $symbol => {meta}, unlimited => T/F
#      RETURNS:  ????
#  DESCRIPTION:  Get the CGI portion of field properties (ones that start with a
#                dash).
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _meta_get_cgi {
    my $self   = shift;
    my $symbol = shift;
    my $meta   = shift || {};
    my %args   = @_;

    my $method = $meta->{__type__} || 'textfield';
    my $label  = $meta->{label}    || $symbol;

    my %prefixes = (
        textfield  => 'Enter',
        textarea   => 'Enter',
        popup_menu => 'Choose',
        filefield  => '',
    );

    return (

        # defaults
        -title => $self->format_title(
            ( ( defined $prefixes{$method} ) ? $prefixes{$method} : 'Set' )
            . " $label"
        ),
        (
              ( $meta->{__readonly__} && !$args{unlimited} )
            ? ( -disabled => 'disabled' )
            : ()
        ),
        -id   => $symbol,
        -name => $symbol,

        # the rest
        map { $_ => $meta->{$_} } grep { /^-/ } keys %$meta
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _update_command
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _update_command {
    my $self = shift;
    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};
    my $table = car( $q->param('table') ) || $self->{_default_table};

    # :TODO:09/15/2011 13:22:27:es:  fix this: there should be two default
    # tables, one when {_id} is not set, and one when it is set.
    #
    return unless defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return unless $table_info;

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    my @fields_to_update =
      grep { defined $q->param($_) } $self->_select_fields(
        table    => $table_info,
        fieldset => 'base',
        omitting => [ '__readonly__', '__special__' ]
      );

    my $assignment = join(
        ',',
        map { "$_=?" } $self->_select_fields(
            table    => $table_info,
            fieldset => \@fields_to_update,
            dealias  => '__sql__'
        )
    );

    my @key = $self->_select_fields(
        table    => $table_info,
        fieldset => 'key',
        dealias  => '__sql__'
    );

    my $predicate = join( ' AND ', map { "$_=?" } @key );
    my $query = "UPDATE $table SET $assignment WHERE $predicate";

    # assuming that $self->{_id} corresponds to the first key field
    my $translate_val =
      $self->_get_param_values( $table_info->{meta}, 'update' );
    my @params = (
        ( map { $translate_val->($_) } @fields_to_update ),
        $self->{_id}, ( map { $translate_val->($_) } cdr @key )
    );
    my $sth = $dbh->prepare($query);

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {
        my $rc = $sth->execute(@params);
        $sth->finish;
        return $rc;
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _ajax_process_request
#   PARAMETERS:  $command_factory can be either name of a method (string) or a
#                reference to a subroutine.
#
#      RETURNS:  ????
#  DESCRIPTION:  This is a generic method for handling AJAX requests
#       THROWS:  no exceptions
#     COMMENTS:
#     SEE ALSO:  n/a
#===============================================================================
sub _ajax_process_request {

    my ( $self, $command_factory, %args ) = @_;

    my $success_code =
      ( defined $args{success_code} )
      ? $args{success_code}
      : 204;    # 204 No Content unless specified otherwise

    #---------------------------------------------------------------------------
    #  prepare statement
    #---------------------------------------------------------------------------
    my $command = eval {
        ( ref $command_factory eq 'CODE' )
          ? $command_factory->($self)
          : $self->$command_factory();
    } or do {
        my $exception = Exception::Class->caught();
        my $msg = eval { $exception->error } || "$exception";
        $self->add_message( { -class => 'error' }, $msg );
        $self->set_header(
            -status => 400,    # 400 Bad Request
            -cookie => undef
        );
        return 1;
    };

    #---------------------------------------------------------------------------
    #  execute statement
    #---------------------------------------------------------------------------
    my $rows_affected = 0;
    eval { ( $rows_affected = ( $command->() || 0 ) ) == 1; } or do {
        my $exception = Exception::Class->caught();
        if ( $exception or $rows_affected != 0 ) {
            if ($exception) {
                my $msg = eval { $exception->error } || "$exception";
                $self->add_message( { -class => 'error' }, $msg );
            }

            # Unexpected condition: either error occured or the number of
            # updated rows is unknown ($rows_affected == -1) or the number of
            # updated rows is more than one.
            $self->set_header(
                -status => 500,    # 500 Internal Server Error
                -cookie => undef
            );
            return 1;
        }
        else {
            $self->add_message(
                { -class => 'error' },
                'The record you are trying to modify has been deleted or moved'
            );

            # No error and no rows updated ($rows_affected == 0)
            $self->set_header(
                -status => 404,    # 404 Not Found
                -cookie => undef
            );
            return 1;
        }
    };

    # Normal condition -- one row updated
    $self->set_header(
        -status => $success_code,
        -cookie => undef
    );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _head_init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _head_init {
    my $self = shift;

    # add DataTable with Paginator; also use util.Connection for AJAX
    push @{ $self->{_css_src_yui} },
      (
        'paginator/assets/skins/sam/paginator.css',
        'datatable/assets/skins/sam/datatable.css',
        'container/assets/skins/sam/container.css'
      );
    push @{ $self->{_js_src_yui} },
      (
        'element/element-min.js',       'datasource/datasource-min.js',
        'datatable/datatable-min.js',   'paginator/paginator-min.js',
        'connection/connection-min.js', 'container/container-min.js'
      );
    push @{ $self->{_js_src_code} }, ( +{ -src => 'TableUpdateDelete.js' } );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  form_create_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_head {
    my $self = shift;
    return if defined $self->{_id};    # no _id

    #---------------------------------------------------------------------------
    #  Lookups
    #---------------------------------------------------------------------------
    # using default table
    my $lookup_join_sth =
      $self->_lookup_prepare( $self->{_table_defs}->{ $self->{_default_table} },
        fields => 'base' );
    $self->_lookup_execute($lookup_join_sth);    # fills {_other}
    $self->_js_dump_lookups();                   # dumps {_other}
    $self->_js_populate_dropdowns();             # will use default table

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _js_populate_dropdowns
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _js_populate_dropdowns {
    my $self       = shift;
    my $table      = shift || $self->{_default_table};
    my $table_info = $self->{_table_defs}->{$table};
    my ( $js, $js_env, $code ) = @$self{qw/_js_emitter _js_env _js_buffer/};

    #---------------------------------------------------------------------------
    #  JS code
    #---------------------------------------------------------------------------

    push @$code, ''
      . $js->apply(
        'YAHOO.util.Event.addListener',
        [
            $js->literal('window'),
            'load',
            $js->apply(
                'populateDropdowns',
                [
                    $js_env->{lookupTables}, $table_info->{lookup},
                    $self->{_id_data}
                ]
            )
        ]
      );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  get_item_name
#   PARAMETERS:  $table -- table name
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_item_name {
    my $self = shift;
    my $table = shift || $self->{_default_table};

    my $table_defs = $self->{_table_defs}     || {};
    my $table_info = $table_defs->{$table}    || {};
    my $item_name  = $table_info->{item_name} || $table;

    return $item_name;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CRUD
#       METHOD:  get_row_name
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_row_name {
    my $self = shift;
    my $table = shift || $self->{_default_table};

    my $table_info =
      ( ref $table eq 'HASH' )
      ? $table
      : ( $self->{_table_defs}->{$table} || {} );

    my $name_fields = $table_info->{names};
    my $id_data     = $self->{_id_data};
    return join( ' / ', @$id_data{@$name_fields} );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CRUD
#       METHOD:  readrow_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  reads one row from the default table
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readrow_body {
    my $self       = shift;
    my $extra_tabs = shift;

    my $q          = $self->{_cgi};
    my $table_defs = $self->{_table_defs};
    my $table_info = $table_defs->{ $self->{_default_table} };
    my $item_name  = $table_info->{item_name};

    # :TODO:08/11/2011 16:35:27:es: breadcrumbs would be useful here

    my $edit_content_id = 'edit';

    my $readrow_table_tuple = $self->{_readrow_tables} || [ undef, {} ];
    my ( $readrow_table, $readrow_table_info ) = @$readrow_table_tuple;
    my $extra_actions = $readrow_table_info->{actions} || {};
    my $extra_actions_html = join(
        ' <span class="separator">/</span> ',
        (
            map { $self->action_link( $_, $extra_actions->{$_} ) }
              keys %$extra_actions
        ),
        $q->a( { -id => $self->{dom_export_link_id} }, 'view as plain text' ),
    );

    return $q->h2( $self->format_title("editing $item_name:") . ' '
          . $self->get_row_name() ),
      $q->div(
        { -id => 'property_editor', -class => 'yui-navset' },
        $q->ul(
            { -class => 'yui-nav' },
            $q->li(
                { -class => 'selected' },
                $q->a(
                    { -href => "#$edit_content_id" },
                    $q->em( $self->format_title("$item_name attributes") )
                )
            ),
            (
                ( defined $readrow_table ) ? $q->li(
                    $q->a(
                        {
                            -href => '#' . $self->pluralize_noun($readrow_table)
                        },
                        $q->em( $readrow_table_info->{heading} )
                    )
                  ) : ()
            ),
            map { $q->li($_) } keys %$extra_tabs
        ),
        $q->div(
            { -class => 'yui-content' },
            $q->div(
                { -id => $edit_content_id },
                $self->body_create_update_form( mode => 'update' )
            ),
            (
                ( defined $readrow_table ) ? $q->div(
                    { -id => $self->pluralize_noun($readrow_table) },
                    $q->p($extra_actions_html),
                    $q->div(
                        {
                            -class => 'clearfix',
                            -id    => $self->{dom_table_id}
                        },
                        ''
                    )
                  ) : ()
            ),
            values %$extra_tabs
        )
      );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CRUD
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  reads default table
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {

    # Form HTML for the project table.
    my $self = shift;
    my $q    = $self->{_cgi};

    my $resource_uri = $self->get_resource_uri();
    return $q->h2( $self->{_title} ),
      $self->body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),

    #---------------------------------------------------------------------------
    #  Table
    #---------------------------------------------------------------------------
      $q->h3( { -id => 'caption' }, '' ),
      $q->div(
        $q->a( { -id => $self->{dom_export_link_id} }, 'View as plain text' ) ),
      $q->div( { -class => 'clearfix', -id => $self->{dom_table_id} }, '' );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  form_create_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
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
      $self->body_create_update_form( mode => 'create' );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  body_create_form
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub body_create_update_form {
    my $self       = shift;
    my %args       = @_;
    my $mode       = $args{mode} || 'create';
    my $cgi_extras = $args{cgi_extras};

    my ( $q, $js ) = @$self{qw/_cgi _js_emitter/};

    # will select from: default table / base fieldset / omitting optional fields
    # / no dealiasing.

    my $onsubmit = $js->apply(
        'return',
        [
            $js->apply(
                'validate_fields',
                [
                    sub { 'this' },
                    [
                        $self->_select_fields(
                            omitting => [
                                '__optional__',
                                ( $mode ne 'create' )
                                ? '__createonly__'
                                : ()
                            ]
                        )
                    ]
                ]
            )
        ]
    );

    # form
    return $q->start_form(
        -accept_charset => 'ISO-8859-1',
        -method         => 'POST',
        -action         => $self->get_resource_uri(),
        -onsubmit       => $onsubmit,
        %$cgi_extras
      ),
      $q->dl(
        $self->body_edit_fields( mode => $mode ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'b', -value => $mode ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => $self->format_title($mode),
                -title =>
                  $self->format_title( $mode . ' ' . $self->get_item_name() )
            )
        )
      ),
      $q->end_form();
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  body_edit_fields
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Helps generate a Create/Update HTML form
#       THROWS:  no exceptions
#     COMMENTS:  n/a
#     SEE ALSO:  n/a
#===============================================================================
sub body_edit_fields {
    my ( $self, %args ) = @_;
    my ( $q, $table, $table_defs ) =
      @$self{qw/_cgi _default_table _table_defs/};
    my $unlimited_mode =
        ( defined $args{mode} )
      ? ( ( $args{mode} eq 'create' ) ? 1 : 0 )
      : 0;

    my $table_info   = $table_defs->{$table} || {};
    my $default_meta = $table_info->{meta}   || {};
    my $args_meta    = $args{meta}           || {};
    my $fields       = $table_info->{base};

    my $fields_meta =
      +{ map { $_ => inherit_hash( $args_meta->{$_}, $default_meta->{$_} ) }
          @$fields };

    my @tmp;
    my $id_data = $self->{_id_data} || {};

    foreach my $symbol (@$fields) {
        my $meta = $fields_meta->{$symbol} || {};
        my %cgi_meta = $self->_meta_get_cgi(
            $symbol   => $meta,
            unlimited => $unlimited_mode
        );
        my $extra_html = $meta->{__extra_html__} || '';

        my $method = $meta->{__type__} || 'textfield';
        my $label  = $meta->{label}    || $symbol;

        my $label_class = ( $meta->{__optional__} ) ? 'optional' : undef;
        $cgi_meta{-title} .= ' (Optional)'
          if $cgi_meta{-title} and $meta->{__optional__};

        next if ( $meta->{__createonly__} && !$unlimited_mode );
        if ( $method eq 'checkbox' ) {
            push @tmp,
              (
                $q->dt( { -id => "${symbol}_dt" }, '&nbsp;' ),
                $q->dd(
                    { -id => "${symbol}_dd" },
                    $q->hidden( -name => $symbol, -value => '0' ),
                    $q->$method(
                        -label => $label,
                        -value => '1',
                        (
                              ( $id_data->{$symbol} )
                            ? ( -checked => 'checked' )
                            : ()
                        ),
                        %cgi_meta
                    ),
                    $extra_html
                )
              );
        }
        elsif ( $method eq 'popup_menu' ) {
            my @values;
            my %labels;
            if ( my $dropdownOptions = $meta->{dropdownOptions} ) {
                foreach my $property (@$dropdownOptions) {
                    my ( $p_val, $p_lab ) = @$property{qw/value label/};
                    push @values, $p_val;
                    $labels{$p_val} = $p_lab;
                }
            }
            my $tied_to    = $meta->{__tie__};
            my $tied_table = ($tied_to) ? $table_defs->{ $tied_to->[0] } : {};
            my $item_name  = $tied_table->{item_name} || '';
            push @tmp,
              (
                $q->dt(
                    { -id => "${symbol}_dt", -class => $label_class },
                    $q->label( { -for => $symbol }, "$label:" )
                ),
                $q->dd(
                    { -id => "${symbol}_dd" },
                    $q->$method(
                        -values  => \@values,
                        -labels  => \%labels,
                        -default => $id_data->{$symbol},
                        %cgi_meta
                    ),
                    (
                        ($tied_to)
                        ? $q->a(
                            {
                                -href => $self->get_resource_uri(
                                    a  => $tied_table->{resource},
                                    b  => 'form_create',
                                    id => undef
                                ),
                                -title => "Click to add a new $item_name first",
                            },
                            "(set up new $item_name)"
                          )
                        : ()
                    ),
                    $extra_html
                )
              );
        }
        else {
            push @tmp,
              (
                $q->dt(
                    { -id => "${symbol}_dt", -class => $label_class },
                    $q->label( { -for => $symbol }, "$label:" )
                ),
                $q->dd(
                    { -id => "${symbol}_dd" },
                    $q->$method(
                        -value => $id_data->{$symbol},
                        %cgi_meta
                    ),
                    $extra_html
                )
              );
            if ( $unlimited_mode && $meta->{__confirm__} ) {
                my $suffix = '_confirm';
                push @tmp,
                  (
                    $q->dt(
                        {
                            -id    => "${symbol}_dt",
                            -class => $label_class
                        },
                        $q->label(
                            { -for => $symbol . $suffix },
                            "Confirm $label:"
                        )
                    ),
                    $q->dd(
                        { -id => "${symbol}_dd" },
                        $q->$method(
                            %cgi_meta,
                            -id    => $cgi_meta{-id} . $suffix,
                            -title => $cgi_meta{-title}
                              . ' Again to Prevent Typos'
                        ),
                        $extra_html
                    )
                  );
            }
        }
    }
    return @tmp;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  body_create_read_menu
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub body_create_read_menu {
    my ( $self, %args ) = @_;
    my $q = $self->{_cgi};

    return $q->ul(
        { -id => 'cr_menu', -class => 'clearfix' },
        $q->li( $self->action_link( @{ $args{'read'} } ) ),
        $q->li( $self->action_link( @{ $args{'create'} } ) )
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CRUD
#       METHOD:  action_link
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub action_link {
    my $self   = shift;
    my $action = shift;
    my $value  = shift;
    my $title  = shift;

    my $q = $self->{_cgi};

    return
      (
        ( !defined($action) && $self->{_ActionName} eq '' )
          or ( defined($action)
            and $self->{_ActionName} eq $action )
      ) ? $value
      : $q->a(
        {
            -href => $self->get_resource_uri( b => $action ),
            (
                  ( defined $title ) ? ( -title => $self->format_title($title) )
                : ()
            )
        },
        $value
      );
}

1;

__END__

#
#===============================================================================
#
#         FILE:  CRUD.pm
#
#  DESCRIPTION:
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  08/11/2011 11:59:04
#     REVISION:  ---
#===============================================================================



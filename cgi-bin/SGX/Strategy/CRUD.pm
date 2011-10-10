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

package SGX::Strategy::CRUD;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

use Carp;
use JSON;
use Tie::IxHash;
use List::Util qw/max/;
use Data::Dumper;
use Scalar::Util qw/looks_like_number/;
use SGX::Debug;
use SGX::Util qw/inherit_hash list_tuples/;

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
    $self->_set_attributes(
        dom_table_id       => 'crudTable',
        dom_export_link_id => 'crudTable_astext',
        _other             => {},
        _js_emitter        => SGX::Abstract::JSEmitter->new( pretty => 1 )
    );

    # dispatch table for other requests (returning 1 results in response
    # without a body)
    $self->_register_actions(
        'redirect' => {
            'ajax_create' => 'ajax_create',
            'ajax_update' => 'ajax_update',
            'ajax_delete' => 'ajax_delete',
            'assign'      => 'default_assign',
            'create'      => 'default_create',
            'update'      => 'default_update',
            'delete'      => 'default_delete'
        }
    );

    bless $self, $class;
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
#       METHOD:  ajax_dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _dispatch_by {
    my ( $self, $type, $action, @info ) = @_;
    my $dispatch_table = $self->{_dispatch_tables}->{$type};

    # execute methods that are in the intersection of those found in the
    # requested dispatch table and those tha can actually be executed.
    my $method = $dispatch_table->{$action};
    return if ( !defined($method) || !$self->can($method) );

    return $self->$method(@info);
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
    my ( $remove_row, $view_row ) = @args{qw/remove_row view_row/};
    my @deletePhrase = ( defined $remove_row ) ? @$remove_row : ('delete');
    push( @deletePhrase, $table ) if not defined $deletePhrase[1];
    my @editPhrase = ( defined $view_row ) ? @$view_row : ('edit');
    push( @editPhrase, $table ) if not defined $editPhrase[1];

    my $js  = $self->{_js_emitter};
    my $s2n = $self->{_this_symbol2name};

    #---------------------------------------------------------------------------
    #  Compiling names to something like _a7, _a0. This way we don't have to
    #  worry about coming up with unique names for the given set.
    #---------------------------------------------------------------------------
    my $var = $js->register_var(
        '_a',
        [
            qw/data cellUpdater cellDropdown cellDropdownDirect DataTable lookupTables
              resourceURIBuilder rowNameBuilder deleteDataBuilder DataSource/
        ]
    );

    #---------------------------------------------------------------------------
    #  Find out which field is key field -- createResourceURIBuilder
    #  (Javascript) needs this.
    #---------------------------------------------------------------------------
    $table = $self->{_default_table} if not defined($table);
    my $table_defs = $self->{_table_defs};
    my $table_info = $table_defs->{$table};
    my ( $this_keys, $this_join, $this_name_symbols, $this_resource ) =
      @$table_info{qw/key join names resource/};
    my ( $this_meta, $this_view ) = @$self{qw/_this_meta _this_view/};
    my %resource_extra = (
        ( map { $_ => $_ } @$this_keys[ 1 .. $#$this_keys ] ),
        ( (@$this_keys) ? ( id => $this_keys->[0] ) : () )
    );

    #---------------------------------------------------------------------------
    #  YUI column definitions
    #---------------------------------------------------------------------------
    my $column = $self->_head_column_def(
        table                => $table,
        js_emitter           => $js,
        data_table           => $var->{data},
        cell_updater         => $var->{cellUpdater},
        cell_dropdown        => $var->{cellDropdown},
        lookup_tables        => $var->{lookupTables},
        cell_dropdown_direct => $var->{cellDropdownDirect}
    );

    my $lookupTables = $var->{lookupTables};

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
              } list_tuples( @{ $table_info->{lookup} } )
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
        my $del_table      = $deletePhrase[1];
        my $del_table_info = $self->{_table_defs}->{$del_table};
        my @del_symbols =
          grep { exists $s2n->{$_} } @{ $del_table_info->{key} };
        my %extras = map { $_ => $_ } @del_symbols;
        %del_table_args = ( table => $del_table, key => \%extras );
    }

    #---------------------------------------------------------------------------
    #  YUI table definition
    #---------------------------------------------------------------------------
    #
    # Need to set a= and id= parameters because otherwise current settings will
    # be used from {_ResourceName} and {_id}.
    my $table_resource_uri = $self->get_resource_uri(
        a  => $this_resource,
        id => undef
    );
    my $onloadLambda = $js->lambda(
        [],
        $js->bind(
            [
                $var->{resourceURIBuilder} => $js->apply(
                    'createResourceURIBuilder',
                    [ $table_resource_uri, \%resource_extra ]
                ),
                $var->{rowNameBuilder} =>
                  $js->apply( 'createRowNameBuilder', [ \@name_columns ] ),
                (
                    ($remove_row)
                    ? (
                        $var->{deleteDataBuilder} =>
                          $js->apply( 'createDeleteDataBuilder',
                            [ \%del_table_args ] )

                      )
                    : ()
                ),
                $var->{DataSource} => $js->apply(
                    'newDataSourceFromArrays',
                    [ $var->{data} ]
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
                )
            ],
            declare => 1
        ),
        $js->bind(
            [
                $var->{DataTable} => $js->apply(
                    'YAHOO.widget.DataTable',
                    [
                        $self->{dom_table_id}, \@column_defs, $var->{DataSource}
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
                                    $var->{resourceURIBuilder},
                                    $var->{deleteDataBuilder},
                                    $var->{rowNameBuilder}
                                ]
                            )
                          )
                        : ()
                    )
                },
            ]
        )
    );

    #---------------------------------------------------------------------------
    #  return text
    #---------------------------------------------------------------------------
    return $js->bind(
        [
            $var->{lookupTables} => $self->{_other},
            $var->{data}         => $js->apply(
                'expandJoinedFields',
                [
                    {
                        caption => 'Showing all Studies',
                        records => $self->getJSRecords(),
                        headers => $self->getJSHeaders(),
                        fields  => [ keys %$s2n ],
                        meta    => $self->export_meta($this_meta),
                        lookup  => $self->{_this_lookup}
                    },
                    $var->{lookupTables}
                ]
            )
        ],
        declare => 1
      )

      . $js->apply(
        'YAHOO.util.Event.addListener',
        [
            $self->{dom_export_link_id},  'click',
            $js->literal('export_table'), $var->{data},
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
    my ($self) = @_;

    my ( $q, $js_src_yui, $js_src_code ) =
      @$self{qw/_cgi _js_src_yui _js_src_code/};

    my $action = $self->get_dispatch_action();

    $self->get_id();

    # ajax_* methods should take care of authorization: may want different
    # permission levels for update/delete statements for example. Additionally,
    # for normal requests, 302 Found (with a redirect to login page) should be
    # returned when user is unauthorized -- while AJAX requests should get 401
    # Authentication Required. Finally, for AJAX requests we do not display body
    # or bother to do further processing.
    return
      if (  $action =~ m/^ajax_/
        and $self->_dispatch_by( 'redirect', $action ) );

    return if $self->redirect_unauth('user');    # do not show body on redirect

    $self->_head_init();
    $self->set_title( $self->{_title} );

    # otherwise we always do one of the three things: (1) dispatch to readall
    # (id not present), (2) dispatch to readrow (id present), (3) redirect if
    # preliminary processing routine (e.g. create request handler) tells us so.
    #
    return if $self->_dispatch_by( 'redirect', $action );

    return 1 if $self->_dispatch_by( 'head', $action );    # show body

    # default actions
    return ( defined $self->{_id} )
      ? $self->readrow_head
      : $self->readall_head;
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
# page, on the other hand, {key} will not be added to {proto}. Using {key} and
# {view} lists will also allow us to preserve order...
#
# At the moment, adding key field, e.g. 'pid' to {view} causes numeric output to
# be printed..
#
#     SEE ALSO:  n/a
#===============================================================================
#sub _get_lookup {
#    my ($table_info, $field_list) = @_;
#    $table_info->{lookup} = [] if not defined $table_info->{lookup};
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
#                  list_tuples(@$tie_info)
#            )
#        ) if defined $tie_info;
#    }
#    return $table_lookup;
#}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  export_meta
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  To export {meta} as JSON, we filter out all key-value pairs
#                with keys that begin with dash or underscore.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub export_meta {
    my ( $self, $meta ) = @_;
    $meta = {} if not defined $meta;
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
    $self->_readrow_command()->();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  readall_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readall_head {
    my $self  = shift;
    my $table = $self->{_default_table};
    return $self->generate_datatable(
        $table,
        remove_row => ['delete'],
        view_row   => ['edit']
    );
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
    my ( $self, $table, %extras ) = @_;
    my ( $q, $table_defs ) = @$self{qw/_cgi _table_defs/};
    my $table_info = $table_defs->{$table};

    $self->_readall_command($table)->();

    # generate all the neccessary Javascript for the YUI DataTable control
    push @{ $self->{_js_src_code} },
      ( { -code => $self->_head_data_table( $table, %extras ) } );
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

    my $action = $self->get_dispatch_action();

    # :TRICKY:08/17/2011 13:00:12:es: CGI.pm -nosticky option seems to not be
    # working as intended. See: http://www.perlmonks.org/?node_id=689507. Using
    # delete_all() ensures that param array is cleared and no form field
    # inherits old values.
    my $q = $self->{_cgi};

    $q->delete_all();

    my (@body) = $self->_dispatch_by( 'body', $action );    # show body
    return @body if ( @body > 0 );

    # default actions
    return ( defined $self->{_id} )
      ? $self->readrow_body
      : $self->readall_body;
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
    my $q    = $self->{_cgi};
    $self->_delete_command()->();
    $q->delete_all();
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
    my $q    = $self->{_cgi};
    $self->_update_command()->();
    $q->delete_all();
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
    my $q    = $self->{_cgi};
    $self->_assign_command()->();
    $q->delete_all();
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

    my $command = $self->_create_command();
    return if ( $command->() != 1 );

    # get inserted row id when inserting a new row, then redirect to the
    # newly created resource.

    my ( $dbh, $table ) = @$self{qw/_dbh _default_table/};
    my $id_column = $self->{_table_defs}->{$table}->{key}->[0];
    my $insert_id = $dbh->last_insert_id( undef, undef, $table, $id_column );

    if ( defined $insert_id ) {
        $self->{_id} = $insert_id;
        $self->set_header(
            -location => $self->get_resource_uri( id => $insert_id ),
            -status   => 302                         # 302 Found
        );
        return 1;    # redirect (do not show body)
    }
    return;
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
    return $self->_ajax_process_request( \&_delete_command );
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
    return $self->_ajax_process_request( \&_update_command );
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
    return $self->_ajax_process_request( \&_create_command );
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

    # make a hash of mutable columns
    my $table =
      ( defined( $args{table} ) && $args{table} ne '' )
      ? $args{table}
      : $self->{_default_table};

    my $table_defs = $self->{_table_defs};
    my $table_info = $table_defs->{$table};
    my $meta       = $table_info->{meta};

    my %mutable =
      map { $_ => 1 } $self->_get_mutable( table_info => $table_info );

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

    # :TODO:09/18/2011 15:43:56:es: parametrize this by table
    #
    my ( $self, $table ) = @_;
    $table = $self->{_default_table} if not defined $table;
    my $key = $self->{_table_defs}->{$table}->{key}->[0];

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
    return shift->{_this_index2name};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  lookup_prepare
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _lookup_prepare {
    my ( $self, $table_info, $composite_labels ) = @_;

    # now add all fields on which we are joining if they are absent
    my ( $dbh,       $table_defs ) = @$self{qw/_dbh _table_defs/};
    my ( $this_meta, $lookup )     = @$table_info{qw/meta lookup/};

    #warn Dumper( _get_lookup($table_info, [keys %$composite_labels]) );

    my %lookup_join_sth;    # hash of statement handles for looked-up tables
    if ( my @lookup_copy = @{ $lookup || [] } ) {
        my $_other = $self->{_other};

        while ( my ( $lookup_table_alias, $val ) =
            splice( @lookup_copy, 0, 2 ) )
        {
            my ( $this_field, $other_field ) = @$val;

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

            my ( $other_key, $other_view, $other_meta ) =
              @$opts{qw/key view meta/};

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
              if not defined( $_other->{$lookup_table_alias} );
            my $js_store = ( $_other->{$lookup_table_alias} );
            $js_store->{symbol2name} = $other_select_fields;
            $js_store->{symbol2index} =
              _symbol2index_from_symbol2name($other_select_fields);
            $js_store->{index2symbol} = [ keys %$other_select_fields ];
            $js_store->{key}          = $other_key;
            $js_store->{view}         = $other_view;
            $js_store->{meta}         = $self->export_meta($other_meta);
        }
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

    my ( $dbh, $q, $table_defs ) = @$self{qw{_dbh _cgi _table_defs}};

    my $default_table = $self->{_default_table};
    $table_alias = $default_table if not $table_alias;
    return if not defined $table_alias;

    my $table_info = $table_defs->{$table_alias};
    return if not $table_info;

    my ( $key, $this_meta, $this_view ) = @$table_info{qw/key meta view/};

    # prepend key fields, preserve order of fields in {view}
    my $composite_labels =
      _get_view_labels( [ @$key, @$this_view ], $this_meta );

    # :TRICKY:09/06/2011 19:22:20:es: For left joins, we do not perform joins
    # in-SQL but instead run a separate query. For inner joins, we add predicate
    # to the main SQL query.

    my $new_opts = inherit_hash( { group_by => $key }, $table_info );

    # :TRICKY:09/28/2011 12:25:52:es: _lookup_prepare modifies $composite_labels
    my $lookup_join_sth =
      $self->_lookup_prepare( $new_opts, $composite_labels );

    # If _id is not set, rely on selectors only. If _id is set, use
    # default_table._id *and* selectors on the second table.
    #
    my ( $this_key, $default_key ) =
      ( $key->[0], $table_defs->{$default_table}->{key}->[0] );

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

    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        carp $error;
        return;
    };

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

    if ( my $constraints = $obj->{constraint} ) {
        my @constr_copy = @$constraints;

        my $dbh = $self->{_dbh};
        while ( my ( $constr_field, $constr_value ) =
            splice( @constr_copy, 0, 2 ) )
        {
            $constr_field = "$table_alias.$constr_field"
              if ( $constr_field !~ m/\./ );
            if ( ref $constr_value eq 'CODE' ) {
                push @pred_and,    "$constr_field=?";
                push @exec_params, $constr_value->($self);
            }
            elsif ( defined $constr_value ) {
                push @pred_and, "$constr_field=" . $dbh->quote($constr_value);
            }
            else {
                push @pred_and, "$constr_field IS NULL";
            }
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
            elsif ( !defined($val) || !looks_like_number($val) ) {

                # find all records -- do not join
                $mod_join_type = '';
            }
        }
    }
    while ( my ( $uri_sel, $sql_sel ) = each %selectors ) {

        #my $val = $q->param($_);
        #if ( defined $val ) {
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

    return ( $pred, \@exec_params, \@constr, $mod_join_type );
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

    my $join = $cascade->{join};
    return ( '', [] ) if not defined $join;
    my $table_defs = $self->{_table_defs};

    my @query_components;
    my @exec_params;

    my @join_copy = @$join;
    while ( my ( $other_table_alias, $info ) = splice( @join_copy, 0, 2 ) ) {

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

        my ( $join_pred, $join_params, $constr, $mod_join_type ) =
          $self->_build_predicate(
            $other_table_alias => $new_opts,
            'AND'
          );
        push @{ $cascade->{constraint} }, @$constr;
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
#       METHOD:  _buld_select_fields
#   PARAMETERS:  ????
#      RETURNS:  hash: sql => alias
#  DESCRIPTION:  Pull select fields from {view} of joined tables
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _buld_select_fields {
    my ( $self, $symbol2name, $table_alias => $cascade ) = @_;

    my ( $join, $this_view, $this_meta ) = @$cascade{qw/join view meta/};
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

    my @join_copy = @{ $join || [] };
    while ( my ( $other_table_alias, $info ) = splice( @join_copy, 0, 2 ) ) {

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
      $self->_buld_select_fields( $symbol2name, $table_alias => $cascade );
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
    return if not defined $self->{_id};

    my ( $dbh, $q, $table_defs ) = @$self{qw{_dbh _cgi _table_defs}};
    my $default_table = $self->{_default_table};
    $table_alias = $default_table if not $table_alias;
    return if not defined $table_alias;

    my $table_info = $table_defs->{$table_alias};
    return if not $table_info;

    my ( $key, $fields ) = @$table_info{qw/key proto/};
    my @key_copy = @$key;

    return if @key_copy != 1;

    my $table = $table_info->{table} || $table_alias;
    my $predicate = join( ' AND ', map { "$_=?" } @key_copy );
    my $read_fields = join( ',', @$fields );
    my $query =
      "SELECT $read_fields FROM $table AS $table_alias WHERE $predicate";

    #warn "getting lookups for $table_alias";
    my $lookup_join_sth = $self->_lookup_prepare($table_info);

    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        carp $error;
        return;
    };

    my @params =
      ( $self->{_id}, ( map { $q->param($_) } splice( @key_copy, 1 ) ) );

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
    my $table = $q->param('table');
    $table = $self->{_default_table}
      if ( !defined($table) || $table eq '' );
    return if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return if not $table_info;

    my $key       = $table_info->{key};
    my @key_copy  = @$key;
    my $predicate = join( ' AND ', map { "$_=?" } @key_copy );
    my $query     = "DELETE FROM $table WHERE $predicate";
    my @params = ( $self->{_id}, map { $q->param($_) } splice( @key_copy, 1 ) );

    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        carp $error;
        return;
    };

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
    my $table = $q->param('table');
    return if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return if not $table_info;

    # We do not support creation queries on resource links that correspond to
    # elements (have ids) when database table has one key or fewer.
    my $id  = $self->{_id};
    my $key = $table_info->{key};
    return if ( !defined($id) || @$key != 2 );

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    # Note: we make exception when inserting a record when resource id is
    # already present: in those cases we create links.

    my $assignment = join( ',', @$key );
    my $query      = "INSERT IGNORE INTO $table ($assignment) VALUES (?,?)";
    my $sth        = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        carp $error;
        return;
    };

    my @param_set = ( $q->param( $key->[1] ) );

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
    my $table = $q->param('table');
    $table = $self->{_default_table} if not defined $table;
    return if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return if not $table_info;

    my $id = $self->{_id};

    # We do not support creation queries on resource links that correspond to
    # elements (have ids) when database table has one key or fewer.
    my ( $key, $meta, $fields ) = @$table_info{qw/key meta proto/};
    return if defined $id and @$key < 2;

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    # Note: we make exception when inserting a record when resource id is
    # already present: in those cases we create links.
    my @proto = @$fields;

    my $translate_key = $self->_get_param_keys($meta);
    my @assigned_fields =
        ( defined $id )
      ? ( $proto[0], map { $translate_key->($_) } splice( @proto, 1 ) )
      : map { $translate_key->($_) } @proto;

    my $assignment = join( ',', @assigned_fields );
    my $placeholders = join( ',', map { '?' } @assigned_fields );
    my $query = "INSERT INTO $table ($assignment) VALUES ($placeholders)";
    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        carp $error;
        return;
    };

    my $translate_val = $self->_get_param_values($meta);
    my @params =
        ( defined $id )
      ? ( $id, map { $translate_val->($_) } splice( @assigned_fields, 1 ) )
      : map { $translate_val->($_) } @assigned_fields;

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
#       METHOD:  _get_param_keys
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _get_param_keys {
    my ( $self, $meta ) = @_;
    my $q = $self->{_cgi};
    return sub {
        my $field     = shift;
        my $this_meta = $meta->{$field} || {};
        my $type      = $this_meta->{__type__} || 'textfield';
        return ( defined $q->param($field) ) ? ($field) : ();
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
    my ( $self, $meta ) = @_;
    my $q = $self->{_cgi};
    return sub {
        my $param     = shift;
        my @result    = $q->param($param);
        my $this_meta = $meta->{$param} || {};
        my $type      = $this_meta->{__type__};
        if ( !defined($type) ) {
            return @result;
        }
        elsif ( $type eq 'checkbox' ) {
            return ( @result > 1 ) ? 1 : 0;
        }
        else {
            return @result;
        }
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _get_mutable
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Gets all fields from {proto} that not have -disabled key in
#                {meta}.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _get_mutable {
    my ( $self, %args ) = @_;
    my $table_info = $args{table_info}
      || $self->{_table_defs}->{ $args{table_name} };
    my ( $proto, $meta ) = @$table_info{qw/proto meta/};
    return grep { !exists $meta->{$_}->{-disabled} } @$proto;
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
    my $table = $q->param('table');

    # :TODO:09/15/2011 13:22:27:es:  fix this: there should be two default
    # tables, one when {_id} is not set, and one when it is set.
    #
    $table = $self->{_default_table} if not defined $table;
    return if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return if not $table_info;

    my ( $key, $meta ) = @$table_info{qw/key meta/};

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    my $translate_key = $self->_get_param_keys($meta);
    my @fields_to_update =
      map { $translate_key->($_) }
      $self->_get_mutable( table_info => $table_info );
    my @key_copy = @$key;

    my $assignment = join( ',',     map { "$_=?" } @fields_to_update );
    my $predicate  = join( ' AND ', map { "$_=?" } @key_copy );
    my $query = "UPDATE $table SET $assignment WHERE $predicate";

    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        carp $error;
        return;
    };

    my $translate_val = $self->_get_param_values($meta);
    my @params        = (
        ( map { $translate_val->($_) } @fields_to_update ),
        $self->{_id}, ( map { $translate_val->($_) } splice( @key_copy, 1 ) )
    );

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
#   PARAMETERS:  ????
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

    my $s = $self->{_UserSession};

    # hardcoding 'user' authorization level for now
    if ( !$s->is_authorized('user') ) {

        $self->set_header(
            -status => 401,    # 401 Unauthorized
            -cookie => undef
        );
        return 1;
    }
    my $command = $command_factory->($self);

    if ( not defined $command ) {
        $self->set_header(
            -status => 400,    # 400 Bad Request
            -cookie => undef
        );
        return 1;
    }

    my $rows_affected = 0;
    eval { ( $rows_affected = $command->() ) == 1; } or do {
        if ( ( my $exception = $@ ) or $rows_affected != 0 ) {

            # Unexpected condition: either error occured or the number of
            # updated rows is unknown ($rows_affected == -1) or the number of
            # updated rows is more than one.
            $self->set_header(
                -status => 500,    # 500 Internal Server Error
                -cookie => undef
            );
            $exception->throw() if $exception;
            return 1;
        }
        else {

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
        'datatable/assets/skins/sam/datatable.css'
      );
    push @{ $self->{_css_src_code} }, ( +{ -src => 'CRUD.css' } );
    push @{ $self->{_js_src_yui} },
      (
        'yahoo-dom-event/yahoo-dom-event.js', 'element/element-min.js',
        'datasource/datasource-min.js',       'datatable/datatable-min.js',
        'paginator/paginator-min.js',         'connection/connection-min.js'
      );
    push @{ $self->{_js_src_code} }, ( +{ -src => 'TableUpdateDelete.js' } );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _body_edit_fields
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Helps generate a Create/Update HTML form
#       THROWS:  no exceptions
#     COMMENTS:  PerlCritic: Subroutine "_body_edit_fields" with high complexity
#     score (22).  Consider refactoring  (Severity: 3)
#     SEE ALSO:  n/a
#===============================================================================
sub _body_edit_fields {
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
    my $fields       = $table_info->{proto};

    my $fields_meta =
      +{ map { $_ => inherit_hash( $args_meta->{$_}, $default_meta->{$_} ) }
          @$fields };

    my @tmp;
    my $id_data = $self->{_id_data} || {};

    foreach my $symbol (@$fields) {
        my $meta = $fields_meta->{$symbol} || {};
        my %cgi_meta = map { $_ => $meta->{$_} } grep { /^-/ } keys %$meta;
        delete $cgi_meta{-disabled} if $unlimited_mode;
        my $method = $meta->{__type__} || 'textfield';
        my $label  = $meta->{label}    || $symbol;
        $cgi_meta{-title} ||= (
            ( $method eq 'textfield' )
            ? 'Enter'
            : ( ( $method eq 'popup_menu' ) ? 'Choose' : 'Set' )
        ) . " $label";
        if ( $method eq 'checkbox' ) {
            push @tmp,
              (
                $q->dt('&nbsp;') => $q->dd(
                    $q->hidden( -name => $symbol, -value => '0' ),
                    $q->$method(
                        -id    => $symbol,
                        -name  => $symbol,
                        -label => $label,
                        -value => '1',
                        (
                              ( $id_data->{$symbol} )
                            ? ( -checked => 'checked' )
                            : ()
                        ),
                        %cgi_meta
                    )
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

            #else {
            # # lookup table
            #}
            push @tmp,
              (
                $q->dt( $q->label( { -for => $symbol }, "$label:" ) ) => $q->dd(
                    $q->$method(
                        -id      => $symbol,
                        -name    => $symbol,
                        -values  => \@values,
                        -labels  => \%labels,
                        -default => $id_data->{$symbol},
                        %cgi_meta
                    )
                )
              );
        }
        else {
            push @tmp,
              (
                $q->dt( $q->label( { -for => $symbol }, "$label:" ) ) => $q->dd(
                    $q->$method(
                        -id    => $symbol,
                        -name  => $symbol,
                        -value => $id_data->{$symbol},
                        %cgi_meta
                    )
                )
              );
        }

    }
    return @tmp;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _body_create_read_menu
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _body_create_read_menu {
    my ( $self, %args ) = @_;
    my $q = $self->{_cgi};

  # :TODO:09/22/2011 01:36:59:es: fix undefined value bug (appears in Manage...)
  #warn "$self->{_ActionName} eq $args{'create'}->[0]";
  #warn Dumper(\%args);
  #warn ((defined $args{'create'}->[0]) ? 'defined' : '?');

    return $q->ul(
        { -id => 'cr_menu', -class => 'clearfix' },
        ( $self->{_ActionName} eq $args{'create'}->[0] )
        ? (
            $q->li(
                $q->a(
                    {
                        -href =>
                          $self->get_resource_uri( b => $args{'read'}->[0] ),
                        -title => lc( $args{'read'}->[1] )
                    },
                    $args{'read'}->[1]
                )
            ),
            $q->li( $args{'create'}->[1] )
          )
        : (
            $q->li( $args{'read'}->[1] ),
            $q->li(
                $q->a(
                    {
                        -href =>
                          $self->get_resource_uri( b => $args{'create'}->[0] ),
                        -title => 'show form to ' . lc( $args{'create'}->[1] )
                    },
                    $args{'create'}->[1]
                )
            )
        )
    );
}

1;

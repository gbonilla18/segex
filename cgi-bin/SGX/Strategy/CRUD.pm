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

use JSON;
use Tie::IxHash;
use List::Util qw/max/;
use Data::Dumper;
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

    $self->_set_attributes(
        dom_table_id       => 'crudTable',
        dom_export_link_id => 'crudTable_astext',
        _other             => {}
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

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );

    my $s2n = $self->{_this_symbol2name};

    #---------------------------------------------------------------------------
    #  Compiling names to something like _a7, _a0. This way we don't have to
    #  worry about coming up with unique names for the given set.
    #---------------------------------------------------------------------------
    my $var = $js->register_var(
        '_a',
        [
            qw/data cellUpdater cellDropdown DataTable lookupTables
              resourceURIBuilder rowNameBuilder deleteDataBuilder DataSource/
        ]
    );

    #---------------------------------------------------------------------------
    #  Find out which field is key field -- createResourceURIBuilder
    #  (Javascript) needs this.
    #---------------------------------------------------------------------------
    $table = $self->{_default_table} if not defined($table);
    my $table_defs     = $self->{_table_defs};
    my $table_info     = $table_defs->{$table};
    my $keys           = $table_info->{key};
    my %resource_extra = (
        ( map { $_ => $_ } @$keys[ 1 .. $#$keys ] ),
        ( (@$keys) ? ( id => $keys->[0] ) : () )
    );

    #---------------------------------------------------------------------------
    #  YUI column definitions
    #---------------------------------------------------------------------------
    my $column = $self->_head_column_def(
        table         => $table,
        js_emitter    => $js,
        cell_updater  => $var->{cellUpdater},
        cell_dropdown => $var->{cellDropdown},
        lookup_tables => $var->{lookupTables}
    );

    my $lookupTables = $var->{lookupTables};

    my @column_defs = (

        # default table view (default table referred to by an empty string)
        ( map { $column->( [ undef, $_ ] ) } @{ $table_info->{view} } ),

        # views in left_joined tables
        (
            map {
                my $other_table       = $_;
                my $lookupTable_other = $lookupTables->($other_table);
                map {
                    $column->(
                        [ $other_table, $_ ],
                        formatter => $js->apply(
                            'createJoinFormatter', [ $lookupTable_other, $_ ]
                        )
                      )
                  } @{ $table_defs->{$other_table}->{view} }
              } keys %{ $self->{_other} }
        ),

        # delete row
        (
            ($remove_row)
            ? $column->(
                undef,
                label => join( ' ', @deletePhrase ),
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
                label     => join( ' ', @editPhrase ),
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
    my @nameIndexes = grep { exists $s2n->{$_} } @{ $table_info->{names} };

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
        a  => $table_info->{resource},
        id => undef
    );
    my $onloadLambda = $js->lambda(
        $js->bind(
            [
                $var->{resourceURIBuilder} => $js->apply(
                    'createResourceURIBuilder',
                    [ $table_resource_uri, \%resource_extra ]
                ),
                $var->{rowNameBuilder} =>
                  $js->apply( 'createRowNameBuilder', [ \@nameIndexes ] ),
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
                    'cellUpdater',
                    [ $var->{resourceURIBuilder}, $var->{rowNameBuilder} ]
                ),
                $var->{cellDropdown} => $js->apply(
                    'cellDropdown',
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
                        fields => $self->_head_response_schema()
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

    foreach my $selector ( @{ $table_info->{selectors} } ) {
        if ( defined( $q->param($selector) ) && $q->param($selector) eq 'all' )
        {

            # delete CGI parameter if set to 'all' and name belongs to selectors
            # array.
            $q->delete($selector);
        }
    }

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
    return undef;
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
#       METHOD:  _head_response_schema
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _head_response_schema {
    return [ keys %{ shift->{_this_symbol2name} } ];
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _head_column_def
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _head_column_def {
    my ( $self, %args )   = @_;
    my ( $s2n,  $_other ) = @$self{qw/_this_symbol2name _other/};

    # make a hash of mutable columns
    my $table =
      ( defined( $args{table} ) && $args{table} ne '' )
      ? $args{table}
      : $self->{_default_table};

    my $table_defs = $self->{_table_defs};
    my $table_info = $table_defs->{$table};
    my ( $table_mutable, $table_lookup ) = @$table_info{qw/mutable lookup/};
    my %mutable = map { $_ => 1 } @$table_mutable;

    my $js            = $args{js_emitter};
    my $cell_updater  = $args{cell_updater};
    my $cell_dropdown = $args{cell_dropdown};
    my $lookupTables  = $args{lookup_tables};

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
        my ( $mytable, $symbol ) =
          ( defined $datum ) ? @$datum : ( undef, undef );

        # determine key value of lookup table if dealing with such
        my $propagate_key =
          defined($mytable)
          ? $table_lookup->{$mytable}->[0]
          : undef;

        my $index =
            ( defined $symbol )
          ? ( ( defined($mytable) ) ? "$mytable.$symbol" : $symbol )
          : undef;
        my $label =
          ( defined $symbol )
          ? (
            ( defined($mytable) )
            ? $_other->{$mytable}->{symbol2name}->{$symbol}
            : $s2n->{$symbol}
          )
          : undef;

    #---------------------------------------------------------------------------
    #  cell editor (either text or dropdown)
    #---------------------------------------------------------------------------
        my @ajax_editor;

        if ( defined($symbol) ) {
            if (   defined($cell_updater)
                && !defined($mytable)
                && $mutable{$symbol} )
            {
                push @ajax_editor,
                  ( editor => $js->apply( $cell_updater, [$symbol] ) );
            }
            elsif (defined($cell_dropdown)
                && defined($mytable)
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
                push @ajax_editor,
                  (
                    editor => $js->apply(
                        $cell_dropdown,
                        [ $lookupTables->($mytable), $propagate_key, $symbol ]
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
            @ajax_editor,
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
#       METHOD:  _readall_command
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _readall_command {
    my ( $self, $table_alias, %args ) = @_;

    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};

    my $default_table = $self->{_default_table};
    $table_alias = $default_table
      if ( !defined($table_alias) || $table_alias eq '' );

    my $table_defs = $self->{_table_defs};
    my $table_info = $table_defs->{$table_alias};
    return undef if not $table_info;

    my ( $key, $this_labels, $this_view ) = @$table_info{qw/key labels view/};

    # prepend key fields, preserve order of fields in {view}
    my $composite_labels =
      _get_ordered_hash( [ @$key, @$this_view ], $this_labels );

    my %left_join_sth;    # hash of statement handles for lookup

    # :TRICKY:09/06/2011 19:22:20:es: For left joins, we do not perform joins
    # in-SQL but instead run a separate query. For inner joins, we add predicate
    # to the main SQL query.

    # now add all fields on which we are joining if they are absent
    my $lookup =
      ( defined $args{lookup} )
      ? $args{lookup}
      : $table_info->{lookup};
    if ($lookup) {
        my $_other = $self->{_other};

        while ( my ( $left_table_alias, $val ) = each(%$lookup) ) {
            my ( $this_field, $other_field, $opts ) = @$val;
            $opts = {} if not defined $opts;

            if ( not exists $composite_labels->{$this_field} ) {
                $composite_labels->{$this_field} = $this_labels->{$this_field};
            }

            my $left_table_info = $table_defs->{$left_table_alias};
            my ( $other_view, $other_labels ) =
              @$left_table_info{qw/view labels/};

            # prepend key field
            my $other_select_fields =
              _get_ordered_hash( [ $other_field, @$other_view ],
                $other_labels );

            my ( $left_query, $left_params ) =
              $self->_build_select( $left_table_alias, $other_select_fields,
                { %$opts, group_by => [$other_field] } );

            $left_join_sth{$left_table_alias} =
              [ $dbh->prepare($left_query), $left_params ];
            $_other->{$left_table_alias}->{symbol2name} = $other_select_fields;
            $_other->{$left_table_alias}->{symbol2index} =
              _symbol2index_from_symbol2name($other_select_fields);
            $_other->{$left_table_alias}->{index2symbol} =
              [ keys %$other_select_fields ];
            $_other->{$left_table_alias}->{lookup_by} = $this_field;
        }
    }

    $self->{_this_symbol2name} = $composite_labels;
    $self->{_this_symbol2index} =
      _symbol2index_from_symbol2name($composite_labels);

    # If _id is not set, rely on selectors only. If _id is set, use
    # default_table._id *and* selectors on the second table.
    #
    my ( $this_key, $default_key ) =
      ( $key->[0], $table_defs->{$default_table}->{key}->[0] );

    # return both query and parameter array
    my ( $query, $params ) = $self->_build_select(
        $table_alias,
        $composite_labels,
        {
            group_by => $key,
            %args
        }
    );

    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {
        my $rc;

        # main query execute
        $rc = $sth->execute(@$params);
        $self->{_this_index2name} = $sth->{NAME};

        $self->{_this_data} = $sth->fetchall_arrayref;

        $sth->finish;

        my $_other = $self->{_other};
        while ( my ( $otable, $val ) = each %left_join_sth ) {
            my ( $osth, $oparams ) = @$val;
            $rc = $osth->execute(@$oparams);
            $_other->{$otable}->{index2name} = $osth->{NAME};
            $_other->{$otable}->{data} =
              _data_transform( $osth->fetchall_arrayref );
            $osth->finish;
        }
        return $rc;
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _data_transform
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Transform $ARRAY1 = [ [ 61, 41174 ], [ 62, 50072, ... ] ];
#                into      $HASH1 = { 61 => [ 41174 ], 62 => [ 50072, ... ] };
#
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _data_transform {
    my $arrayref = shift;
    return +{ map { shift(@$_) => $_ } @$arrayref };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  _get_ordered_hash
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _get_ordered_hash {
    my ( $view, $labels ) = @_;
    my %ret;
    my $ret_t = tie( %ret, 'Tie::IxHash', map { $_ => $labels->{$_} } @$view );
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
    my ($symbol2name) = @_;
    my $i = 0;
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

#---------------------------------------------------------------------------
#  analogue to built-in keys function, except for lists, not hashes
#---------------------------------------------------------------------------
sub _list_keys {
    @_[ grep { !( $_ % 2 ) } 0 .. $#_ ];
}

#---------------------------------------------------------------------------
#  analogue to built-in values function, except for lists, not hashes
#---------------------------------------------------------------------------
sub _list_values {
    @_[ grep { $_ % 2 } 0 .. $#_ ];
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
    my ( $self, $table_alias, $obj, $prefix ) = @_;

    my @pred_and;
    my @exec_params;

    if ( my $constraints = $obj->{constraint} ) {
        my @constr_copy = @$constraints;

        my $dbh = $self->{_dbh};
        while ( my ( $constr_field, $constr_value ) =
            splice( @constr_copy, 0, 2 ) )
        {
            if ( ref $constr_value eq 'CODE' ) {
                push @pred_and,    "$table_alias.$constr_field=?";
                push @exec_params, $constr_value->($self);
            }
            else {
                push @pred_and,
                  "$table_alias.$constr_field=" . $dbh->quote($constr_value);
            }
        }
    }
    if ( my $selectors = $obj->{selectors} ) {
        my $q = $self->{_cgi};
        foreach (@$selectors) {
            my $val = $q->param($_);
            if ( defined $val ) {
                push @pred_and,    "$table_alias.$_=?";
                push @exec_params, $val;
            }
        }
    }

    my $pred =
      ( ( @pred_and > 0 ) ? "$prefix " : '' ) . join( ' AND ', @pred_and );

    return ( $pred, \@exec_params );
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
    my ( $self, $table_alias, $cascade, $join_type ) = @_;

    my $join_symb = lc($join_type) . '_join';

    my $join = $cascade->{$join_symb};
    return ( '', [] ) if not defined $join;
    my $table_defs = $self->{_table_defs};

    my @query_components;
    my @exec_params;

    while ( my ( $other_table_alias, $info ) = each %$join ) {

        my ( $this_field, $other_field, $opts ) = @$info;
        $opts = {} if not defined $opts;

        my %cascade_other = ( %{ $table_defs->{$other_table_alias} }, %$opts );

        my $other_table = $cascade_other{table};
        $other_table =
          ( !defined($other_table) || $other_table eq $other_table_alias )
          ? $other_table_alias
          : "$other_table AS $other_table_alias";

        my $pred =
"$join_type JOIN $other_table ON $table_alias.$this_field=$other_table_alias.$other_field";

        my ( $inner_pred, $inner_params ) = $self->_build_predicate(
            $other_table_alias => \%cascade_other,
            'AND'
        );
        push @query_components, "$pred $inner_pred";
        push @exec_params,      @$inner_params;
    }
    return ( join( ' ', @query_components ), \@exec_params );
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
    my ( $self, $table_alias, $symbol2name, $obj ) = @_;
    my $dbh        = $self->{_dbh};
    my $table_defs = $self->{_table_defs};
    my %cascade    = ( %{ $table_defs->{$table_alias} }, %$obj );
    my $table      = $cascade{table};
    $table = $table_alias if not defined $table;

    my @query_components;
    my @exec_params;

    # SELECT
    push @query_components, 'SELECT ' . join(
        ',',
        map {
            ( _valid_SQL_identifier($_) ? "$table_alias.$_" : $_ )
              . (
                defined( $symbol2name->{$_} )
                ? ' AS ' . $dbh->quote( $symbol2name->{$_} )
                : ''
              )
          } keys %$symbol2name
      )
      . ' FROM '
      . ( ( $table ne $table_alias ) ? "$table AS $table_alias" : $table );

    # JOINS
    my ( $inner_pred, $inner_params ) =
      $self->_build_join( $table_alias => \%cascade, 'INNER' );
    push @query_components, $inner_pred;
    push @exec_params,      @$inner_params;
    my ( $left_pred, $left_params ) =
      $self->_build_join( $table_alias => \%cascade, 'LEFT' );
    push @query_components, $left_pred;
    push @exec_params,      @$left_params;

    # WHERE
    my ( $where_pred, $where_params ) =
      $self->_build_predicate( $table_alias => \%cascade, 'WHERE' );
    push @query_components, $where_pred;
    push @exec_params,      @$where_params;

    # GROUP BY
    if ( my $group_by = $cascade{group_by} ) {
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
    my ($self) = @_;
    return if not defined $self->{_id};

    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};
    my $table = $self->{_default_table};
    return undef if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return undef if not $table_info;

    my ( $key, $fields ) = @$table_info{qw/key proto/};
    my @key_copy = @$key;

    return if @key_copy != 1;

    my $predicate = join( ' AND ', map { "$_=?" } @key_copy );
    my $read_fields = join( ',', @$fields );
    my $query = "SELECT $read_fields FROM $table WHERE $predicate";

    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my @params =
      ( $self->{_id}, ( map { $q->param($_) } splice( @key_copy, 1 ) ) );

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {
        my $rc = $sth->execute(@params);
        $self->{_id_data} = $sth->fetchrow_hashref;
        $sth->finish;
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
    my ($self) = @_;
    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};
    my $table = $q->param('table');
    $table = $self->{_default_table} if ( !defined($table) || $table eq '' );
    return undef if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return undef if not $table_info;

    my $key       = $table_info->{key};
    my @key_copy  = @$key;
    my $predicate = join( ' AND ', map { "$_=?" } @key_copy );
    my $query     = "DELETE FROM $table WHERE $predicate";
    my $sth       = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my @params = ( $self->{_id}, map { $q->param($_) } splice( @key_copy, 1 ) );

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
    return undef if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return undef if not $table_info;

    # We do not support creation queries on resource links that correspond to
    # elements (have ids) when database table has one key or fewer.
    my $id  = $self->{_id};
    my $key = $table_info->{key};
    return undef if ( !defined($id) || @$key != 2 );

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
        warn $error;
        return undef;
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
    my ($self) = @_;
    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};
    my $table = $q->param('table');
    $table = $self->{_default_table} if not defined $table;
    return undef if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return undef if not $table_info;

    my $id = $self->{_id};

    # We do not support creation queries on resource links that correspond to
    # elements (have ids) when database table has one key or fewer.
    my ( $key, $fields ) = @$table_info{qw/key proto/};
    return if defined $id and @$key < 2;

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    # Note: we make exception when inserting a record when resource id is
    # already present: in those cases we create links.
    my @proto = @$fields;
    my @assigned_fields =
        ( defined $id )
      ? ( $proto[0], grep { defined $q->param($_) } splice( @proto, 1 ) )
      : grep { defined $q->param($_) } @proto;

    my $assignment = join( ',', @assigned_fields );
    my $placeholders = join( ',', map { '?' } @assigned_fields );
    my $query = "INSERT INTO $table ($assignment) VALUES ($placeholders)";
    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my @params =
        ( defined $id )
      ? ( $id, map { $q->param($_) } splice( @assigned_fields, 1 ) )
      : map { $q->param($_) } @assigned_fields;

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
#       METHOD:  _update_command
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _update_command {
    my ($self) = @_;
    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};
    my $table = $q->param('table');

  # :TODO:09/15/2011 13:22:27:es:  fix this: there should be two default tables,
  # one when {_id} is not set, and one when it is set.
  #
    $table = $self->{_default_table} if not defined $table;
    return undef if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return undef if not $table_info;

    my ( $key, $fields ) = @$table_info{qw/key mutable/};

    my @key_copy = @$key;

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    my @fields_to_update = grep { defined( $q->param($_) ) } @$fields;

    my $assignment = join( ',',     map { "$_=?" } @fields_to_update );
    my $predicate  = join( ' AND ', map { "$_=?" } @key_copy );
    my $query = "UPDATE $table SET $assignment WHERE $predicate";

    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my @params = (
        ( map { $q->param($_) } @fields_to_update ),
        $self->{_id}, ( map { $q->param($_) } splice( @key_copy, 1 ) )
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

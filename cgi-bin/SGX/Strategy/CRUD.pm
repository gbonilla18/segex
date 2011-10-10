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
    my $id = $self->{_id};
    my %overridden = ( ( defined $id ) ? ( id => $id ) : (), %args );
    return $self->SUPER::get_resource_uri(%overridden);
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
    my ( $self, $table, $del_table, $del_verb, $show_edit ) = @_;

    #---------------------------------------------------------------------------
    #  setup
    #---------------------------------------------------------------------------
    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );
    my $s2i = $self->{_this_symbol2index};

    #---------------------------------------------------------------------------
    #  Important parameters
    #---------------------------------------------------------------------------
    my @deletePhrase = ( $del_verb, $table );
    my @editPhrase = ( 'edit', $table );

    #---------------------------------------------------------------------------
    #  Compiling names to something like _a7, _a0. This way we don't have to
    #  worry about coming up with unique names for the given set.
    #---------------------------------------------------------------------------
    my $var = $js->register_var(
        '_a',
        [
            qw/data cellUpdater DataTable leftJoin
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
        ( map { $keys->[$_] => "$_" } 1 .. $#$keys ),
        (@$keys) ? ( id => "0" ) : ()
    );

    #---------------------------------------------------------------------------
    #  YUI column definitions
    #---------------------------------------------------------------------------
    my $column = $self->_head_column_def(
        js_emitter   => $js,
        cell_updater => $var->{cellUpdater}
    );

    my $left_join_info = $table_info->{left_join};
    my $leftJoin       = $var->{leftJoin};
    my @column_defs    = (

        # default table view (default table referred to by an empty string)
        ( map { $column->( [ '', $_ ] ) } @{ $table_info->{view} } ),

        # views in left_joined tables
        (
            map {
                my $other_table = $_;
                my $this_join_col =
                  $s2i->{ $left_join_info->{$other_table}->[0] } . '';
                my $leftJoin_other = $leftJoin->($other_table);
                map {
                    $column->(
                        [ $other_table, $_ ],
                        formatter => $js->apply(
                            'createJoinFormatter',
                            [ $leftJoin_other, $_, $this_join_col ]
                        )
                      )
                  } @{ $table_defs->{$other_table}->{view} }
              } keys %{ $self->{_other} }
        ),

        # delete row
        $column->(
            undef,
            label => join( ' ', @deletePhrase ),
            formatter => $js->apply( 'createDeleteFormatter', [@deletePhrase] )
        ),

        # edit row (optional)
        (
            ($show_edit)
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
    my @nameIndexes =
      map { "$_" }
      grep { defined } map { $s2i->{$_} } @{ $table_info->{names} };

    #---------------------------------------------------------------------------
    #  Arguments supplied to createDeleteDataBuilder (Javascript): table - table
    #  to delete from, key - columns that can be used as indeces for deleting
    #  rows.
    #---------------------------------------------------------------------------
    my %del_table_args;
    if ( defined $del_table ) {
        my $del_table_info = $self->{_table_defs}->{$del_table};
        my @symbols =
          grep { exists $s2i->{$_} } @{ $del_table_info->{key} };
        my %extras = map { $_ => "$s2i->{$_}" } @symbols;
        %del_table_args = ( table => $del_table, key => \%extras );
    }

    #---------------------------------------------------------------------------
    #  YUI table definition
    #---------------------------------------------------------------------------
    my $onloadLambda = $js->lambda(
        $js->bind(
            [
                $var->{resourceURIBuilder} => $js->apply(
                    'createResourceURIBuilder',
                    [ $self->get_resource_uri(), \%resource_extra ]
                ),
                $var->{rowNameBuilder} =>
                  $js->apply( 'createRowNameBuilder', [ \@nameIndexes ] ),
                $var->{deleteDataBuilder} =>
                  $js->apply( 'createDeleteDataBuilder', [ \%del_table_args ] ),
                $var->{DataSource} => $js->apply(
                    'YAHOO.util.DataSource',
                    [ $var->{data}->('records') ],
                    new_object => 1
                ),
                $var->{cellUpdater} => $js->apply(
                    'cellUpdater',
                    [ $var->{resourceURIBuilder}, $var->{rowNameBuilder} ]
                )
            ],
            declare => 1
        ),
        $js->bind(
            [
                $var->{DataSource}->('responseType') =>
                  $js->literal('YAHOO.util.DataSource.TYPE_JSARRAY'),
                $var->{DataSource}->('responseSchema') =>
                  { fields => $self->_head_response_schema() }
            ],
            declare => 0
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
                    buttonClickEvent => $js->apply(
                        'createRowDeleter',
                        [
                            $deletePhrase[0],
                            $var->{resourceURIBuilder},
                            $var->{deleteDataBuilder},
                            $var->{rowNameBuilder}
                        ]
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
            $var->{leftJoin} => $self->{_other},
            $var->{data}     => {
                caption => 'Showing all Studies',
                records => $self->getJSRecords(),
                headers => $self->getJSHeaders()
            }
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

    my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};

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
    shift->_delete_command()->();
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
    shift->_update_command()->();
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
    my $self    = shift;
    my $command = $self->_assign_command();
    if ( $command->() > 0 ) { }
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
    my $self    = shift;
    my $command = $self->_create_command();
    if ( $command->() == 1 ) {

        # get inserted row id when inserting a new row, then redirect to the
        # newly created resource.
        if ( not defined $self->{_id} ) {
            my ( $dbh, $table ) = @$self{qw/_dbh _default_table/};
            my $id_column = $self->{_table_defs}->{$table}->{key}->[0];
            my $insert_id =
              $dbh->last_insert_id( undef, undef, $table, $id_column );
            if ( defined $insert_id ) {
                $self->{_id} = $insert_id;
                $self->set_header(
                    -location => $self->get_resource_uri( id => $insert_id ),
                    -status   => 302                         # 302 Found
                );
                return 1;    # redirect (do not show body)
            }
        }
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
    my $self = shift;
    my $s2i  = $self->{_this_symbol2index};
    return [ map { "$_" } values %$s2i ];
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
    my ( $self, %args ) = @_;
    my ( $s2i, $s2n, $_other ) =
      @$self{qw/_this_symbol2index _this_symbol2name _other/};

    # make a hash of mutable columns
    my $table =
      ( defined $args{table} ) ? $args{table} : $self->{_default_table};
    my $table_info = $self->{_table_defs}->{$table};
    my %mutable = map { $_ => 1 } @{ $table_info->{mutable} };

    my $extrasIndex = max( values %$s2i ) + 1;

    my $js           = $args{js_emitter};
    my $cell_updater = $args{cell_updater};

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
        my ( $table, $symbol ) = ( defined $datum ) ? @$datum : ( '', undef );

        my $index =
          ( $table eq '' and defined($symbol) and defined( $s2i->{$symbol} ) )
          ? $s2i->{$symbol}
          : $extrasIndex++;
        my $label =
          ( defined $symbol )
          ? (
            ( $table eq '' )
            ? $s2n->{$symbol}
            : $_other->{$table}->{symbol2name}->{$symbol}
          )
          : undef;
        return {
            %default_column,
            key      => "$index",
            sortable => ( defined($symbol) && $table eq '' ) ? $TRUE : $FALSE,
            label    => $label,
            (
                (
                         defined($symbol)
                      && defined($cell_updater)
                      && $table eq ''
                      && $mutable{$symbol}
                )
                ? ( editor => $js->apply( $cell_updater, [$symbol] ) )
                : ()
            ),
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

    my ( $self, $table ) = @_;
    $table = $self->{_default_table} if not defined $table;
    my $key = $self->{_table_defs}->{$table}->{key}->[0];

    # declare data sources and options
    my $data = $self->{_this_data};    # data source

    # columns to include in output
    my $s2i     = $self->{_this_symbol2index};
    my @columns = values %$s2i;

    my @tmp;
    my $sort_col = $s2i->{$key};       # column to sort on
    if ( defined $sort_col ) {
        foreach my $row ( sort { $a->[$sort_col] cmp $b->[$sort_col] } @$data )
        {
            my $i = 0;
            push @tmp, +{ map { $i++ => $_ } @$row[@columns] };
        }
    }
    else {
        foreach my $row (@$data) {
            my $i = 0;
            push @tmp, +{ map { $i++ => $_ } @$row[@columns] };
        }
    }
    return \@tmp;
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
    my $self = shift;

    # declare options
    my $s2i     = $self->{_this_symbol2index};
    my @columns = values %$s2i;

    my $names     = $self->{_this_index2name};
    my @use_names = @$names[@columns];

    return [ map { $names->[$_] } @columns ];
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
    my ( $self, $table, %args ) = @_;

    my ( $dbh, $q ) = @$self{qw{_dbh _cgi}};

    my $default_table = $self->{_default_table};
    $table = $default_table if not defined $table;

    my $table_defs = $self->{_table_defs};
    my $table_info = $table_defs->{$table};
    return undef if not $table_info;

    my ( $key, $selectable, $this_labels, $this_view ) =
      @$table_info{qw/key selectors labels view/};

    # prepend key fields, preserve order of fields in {view}
    my $composite_labels =
      _get_ordered_hash( [ @$key, @$this_view ], $this_labels );

    my %left_join_sth;    # hash of statement handles for left_join

    # :TRICKY:09/06/2011 19:22:20:es: For left joins, we do not perform joins
    # in-SQL but instead run a separate query. For inner joins, we add predicate
    # to the main SQL query.

    # now add all fields on which we are joining if they are absent
    my $left_join =
      ( defined $args{left_join} )
      ? $args{left_join}
      : $table_info->{left_join};
    if ($left_join) {
        my $_other = $self->{_other};

        #while ( my ( $this_field, $other ) = each(%$left_join) ) {
        while ( my ( $table_alias, $val ) = each(%$left_join) ) {
            my ( $this_field, $other_field, $opts ) = @$val;

            if ( not exists $composite_labels->{$this_field} ) {
                $composite_labels->{$this_field} = $this_labels->{$this_field};
            }

           #my ( $other_table, $other_field ) = @$other{qw/-table -constraint/};
            my ( $other_table, $constraint ) = @$opts{qw/-table -constraint/};
            $other_table = $table_alias if not defined $other_table;

            # right now doing nothing with constraints in left joins

            # if $other_table ne $table_alias, then form SELECT statement like
            # this: SELECT * FROM $other_table AS $table_alias

            my $other_info = $table_defs->{$other_table};
            my ( $other_view, $other_labels ) = @$other_info{qw/view labels/};

            # prepend key field
            my $other_select_fields =
              _get_ordered_hash( [ $other_field, @$other_view ],
                $other_labels );

            my $left_query = $self->_build_select(
                $other_table, $other_select_fields,
                group_by    => [ $other_table, $other_field ],
                table_alias => $table_alias
            );

            $left_join_sth{$other_table} = [
                $dbh->prepare($left_query),
                $self->_build_select_params($other_table)
            ];
            $_other->{$other_table}->{symbol2name} = $other_select_fields;
            $_other->{$other_table}->{symbol2index} =
              _symbol2index_from_symbol2name($other_select_fields);
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

    my @selectors = grep { defined( $q->param($_) ) } @$selectable;

    my @where_clause = (
        (
              ( defined $self->{_id} and $this_key eq $default_key )
            ? ("$table.$this_key=?")
            : ()
        ),
        map { "$table.$_=?" } @selectors
    );
    my $predicate =
      ( @where_clause > 0 )
      ? 'WHERE ' . join( ' AND ', @where_clause )
      : '';
    my $group_by = 'GROUP BY ' . join( ',', map { "$table.$_" } @$key );

    my $query = join(
        ' ',
        (
            $self->_build_select(
                $table, $composite_labels, inner_join => $args{inner_join}
            ),
            $predicate,
            $group_by
        )
    );

    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my @params = (
        (
              ( defined $self->{_id} and $this_key eq $default_key )
            ? ( $self->{_id} )
            : ()
        ),
        @{
            $self->_build_select_params( $table,
                inner_join => $args{inner_join} )
          },
        map { $q->param($_) } @selectors
    );

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {
        my $rc;

        # main query execute
        $rc = $sth->execute(@params);
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
#       METHOD:  _build_select_params
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _build_select_params {
    my ( $self, $table, %args ) = @_;

    # form INNER JOIN predicate
    my @inner_join_values;
    my $inner_join =
      ( $args{inner_join} )
      ? $args{inner_join}
      : $self->{_table_defs}->{$table}->{inner_join};
    if ($inner_join) {

        #while ( my ( $this_field, $info ) = each %$inner_join ) {
        while ( my ( $table_alias, $info ) = each %$inner_join ) {

            #my ( $other_table, $other_field, $constraints ) = @$info;
            my ( $this_field, $other_field, $opts ) = @$info;
            my ( $other_table, $constraints ) = @$opts{qw/-table -constraint/};

            if ($constraints) {
                while ( my ( $constr_field, $constr_value ) =
                    each %$constraints )
                {
                    push( @inner_join_values, $constr_value->($self) )
                      if ( ref $constr_value eq 'CODE' );
                }
            }
        }
    }
    return \@inner_join_values;
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
    my ( $self, $table, $symbol2name, %args ) = @_;
    my $dbh         = $self->{_dbh};
    my $table_alias = $args{table_alias};

    my $ret = 'SELECT ' . join(
        ',',
        map {
            ( ( _valid_SQL_identifier($_) ) ? "$table.$_ AS " : "$_ AS " )
              . $dbh->quote(
                ( defined $symbol2name->{$_} ) ? $symbol2name->{$_} : $_ )
          } keys %$symbol2name
      )
      . ' FROM '
      . ( ( defined $table_alias ) ? "$table AS $table_alias" : $table );

    # INNER JOIN
    my @inner_join_predicates;
    my $inner_join =
      ( $args{inner_join} )
      ? $args{inner_join}
      : $self->{_table_defs}->{$table}->{inner_join};
    if ($inner_join) {

        #while ( my ( $this_field, $info ) = each %$inner_join ) {
        while ( my ( $table_alias, $info ) = each %$inner_join ) {

            #my ( $other_table, $other_field, $constraints ) = @$info;
            my ( $this_field, $other_field, $opts ) = @$info;
            my ( $other_table, $constraints ) = @$opts{qw/-table -constraint/};
            $other_table =
              ( !defined($other_table) || $other_table eq $table_alias )
              ? $table_alias
              : "$other_table AS $table_alias";

            my $pred =
"INNER JOIN $other_table ON $table.$this_field=$table_alias.$other_field";
            if ($constraints) {
                my @pred_and = ('');
                while ( my ( $constr_field, $constr_value ) =
                    each %$constraints )
                {

                  # if $constr_value is an anonymous function (ref
                  # $constr_value eq 'CODE'), then evaluate it later and pass
                  # it as execute parameter to the query statement, and place
                  # a placeholder for now. Otherwise, insert the value directly.
                    push @pred_and, "$table_alias.$constr_field="
                      . (
                        ( ref $constr_value eq 'CODE' )
                        ? '?'
                        : $constr_value
                      );
                }
                $pred .= join( ' AND ', @pred_and );
            }
            push @inner_join_predicates, $pred;
        }
    }

    # GROUP BY
    if ( my $group_by = $args{group_by} ) {
        my ( $other_table, $other_field ) = @$group_by;
        push @inner_join_predicates, "GROUP BY $other_table.$other_field";
    }

    return join( ' ', $ret, @inner_join_predicates );
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
    return if @$key != 1;

    my $predicate = join( ' AND ', map { "$_=?" } @$key );
    my $read_fields = join( ',', @$fields );
    my $query = "SELECT $read_fields FROM $table WHERE $predicate";

    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my @params = ( $self->{_id}, ( map { $q->param($_) } splice( @$key, 1 ) ) );

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
    $table = $self->{_default_table} if not defined $table;
    return undef if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return undef if not $table_info;

    my $key       = $table_info->{key};
    my $predicate = join( ' AND ', map { "$_=?" } @$key );
    my $query     = "DELETE FROM $table WHERE $predicate";
    my $sth       = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my @params = ( $self->{_id}, map { $q->param($_) } splice( @$key, 1 ) );

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
    my $key = $table_info->{key};
    return undef if not defined $self->{_id} or @$key != 2;

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    # Note: we make exception when inserting a record when resource id is
    # already present: in those cases we create links.
    my @assigned_fields =
      ( $key->[0], grep { defined $q->param($_) } splice( @$key, 1 ) );

    my $assignment = join( ',', @assigned_fields );
    my $query      = "INSERT IGNORE INTO $table ($assignment) VALUES (?,?)";
    my $sth        = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my $id = $self->{_id};
    my @param_set =
      map { [ $id, $_ ] }
      map { $q->param($_) } splice( @assigned_fields, 1 );

    # separate preparation from execution because we may want to send different
    # error messages to user depending on where the error has occurred.
    return sub {
        my $rc = 0;
        foreach my $link (@param_set) {
            $rc += $sth->execute(@$link);
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

    # We do not support creation queries on resource links that correspond to
    # elements (have ids) when database table has one key or fewer.
    my ( $key, $fields ) = @$table_info{qw/key proto/};
    return if defined $self->{_id} and @$key < 2;

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    # Note: we make exception when inserting a record when resource id is
    # already present: in those cases we create links.
    my @assigned_fields =
        ( defined $self->{_id} )
      ? ( $fields->[0], grep { defined $q->param($_) } splice( @$fields, 1 ) )
      : grep { defined $q->param($_) } @$fields;

    my $assignment = join( ',', @assigned_fields );
    my $placeholders = join( ',', map { '?' } @assigned_fields );
    my $query = "INSERT INTO $table ($assignment) VALUES ($placeholders)";
    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my @params =
        ( defined $self->{_id} )
      ? ( $self->{_id}, map { $q->param($_) } splice( @assigned_fields, 1 ) )
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
    $table = $self->{_default_table} if not defined $table;
    return undef if not defined $table;

    my $table_info = $self->{_table_defs}->{$table};
    return undef if not $table_info;

    my ( $key, $fields ) = @$table_info{qw/key mutable/};

    # If param($field) evaluates to undefined, then we do not set the field.
    # This means that we cannot directly set a field to NULL -- unless we
    # specifically map a special character (for example, an empty string), to
    # NULL.
    my @fields_to_update = grep { defined( $q->param($_) ) } @$fields;

    my $assignment = join( ',',     map { "$_=?" } @fields_to_update );
    my $predicate  = join( ' AND ', map { "$_=?" } @$key );
    my $query = "UPDATE $table SET $assignment WHERE $predicate";
    my $sth = eval { $dbh->prepare($query) } or do {
        my $error = $@;
        warn $error;
        return undef;
    };

    my @params = (
        ( map { $q->param($_) } @fields_to_update ),
        $self->{_id}, ( map { $q->param($_) } splice( @$key, 1 ) )
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

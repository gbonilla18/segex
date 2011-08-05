
=head1 NAME

SGX::ManagePlatforms

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing platforms.

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::ManagePlatforms;

use strict;
use warnings;

use Switch;
use SGX::Abstract::JSEmitter;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, %param ) = @_;

    my ( $dbh, $q, $s, $js_src_yui, $js_src_code ) =
      @param{qw{dbh cgi user_session js_src_yui js_src_code}};

    ${$param{title}} = 'Manage Platforms';

    my $self = {
        _dbh         => $dbh,
        _cgi         => $q,
        _UserSession => $s,
        _js_src_yui  => $js_src_yui,
        _js_src_code => $js_src_code,

        _FieldNames   => '',
        _Data         => '',
        _pid          => undef,
        _PName        => undef,
        _def_f_cutoff => undef,
        _def_p_cutoff => undef,
        _Species      => undef
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  executes code appropriate for the given action
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch {
    my ($self) = @_;
    my $q = $self->{_cgi};
    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    print $self->getTableHTML();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
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

    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};
    my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    push @$js_src_yui,
      (
        'yahoo-dom-event/yahoo-dom-event.js', 'connection/connection-min.js',
        'dragdrop/dragdrop-min.js',           'container/container-min.js',
        'element/element-min.js',             'datasource/datasource-min.js',
        'paginator/paginator-min.js',         'datatable/datatable.js',
        'selector/selector-min.js'
      );

    switch ($action) {
        case 'Add' {
            return unless $s->is_authorized('user');
            $self->init();
            $self->insertNewPlatform();
            $self->redirectInternal('?a=managePlatforms');
        }
        case 'delete' {
            return unless $s->is_authorized('user');
            $self->init();
            $self->deletePlatform();
            $self->redirectInternal('?a=managePlatforms');
        }
        case 'update' {

   # :TODO:07/28/2011 03:35:57:es:  program basic data validation such that, for
   # example, setting a numeric-only column to a string won't result in a
   # successful update, and to ensure that P-values can be only in the range [0,
   # 1].
   # ajax_update takes care of authorization...
            $self->ajax_update(
                valid_fields => [qw{pname def_f_cutoff def_p_cutoff species}],
                table        => 'platform',
                key          => 'pid'
            );
        }
        else {
            return unless $s->is_authorized('user');

            $self->init();
            $self->loadAllPlatforms();

            # load platforms
            push @$js_src_code, { -src  => 'CellUpdater.js' };
            push @$js_src_code, { -code => $self->getTableJS() };
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  redirectInternal
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub redirectInternal {
    my ( $self, $query ) = @_;
    my ( $q,    $s )     = @$self{qw{_cgi _UserSession}};

    # redirect if we know where to... will send a redirect header, so
    # commit the session to data store now
    my $redirectURI =
      ( defined $q->url_param('destination') )
      ? $q->url( -base     => 1 ) . uri_unescape( $q->url_param('destination') )
      : $q->url( -absolute => 1 ) . $query;

    $s->commit();
    print $q->redirect(
        -uri    => $redirectURI,
        -status => 302,                 # 302 Found
        -cookie => $s->cookie_array()
    );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  loadAllPlatforms
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loads all platforms into the object from the database.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadAllPlatforms {
    my $self = shift;

    my $dbh = $self->{_dbh};

    my $loadQuery = <<"END_LoadQuery";
SELECT 
    platform.pname        AS 'Platform', 
    platform.def_f_cutoff AS 'Default Fold Change', 
    platform.def_p_cutoff AS 'Default P-Value', 
    platform.species      AS 'Species',
    platform.pid,
    IF(
        isAnnotated, 'Yes', 'No'
    )                           AS 'Annotated',
    COUNT(probe.rid)            AS 'Probe Count',
    COUNT(probe.probe_sequence) AS 'Probe Sequences',
    COUNT(probe.location)       AS 'Locations',
    COUNT(annotates.gid)        AS 'Probes with Annotations',
    COUNT(gene.seqname)         AS 'Gene Symbols',
    COUNT(gene.description)     AS 'Gene Names'    
FROM platform
LEFT JOIN probe USING(pid)
LEFT JOIN annotates USING(rid)
LEFT JOIN gene USING(gid)
GROUP BY pid
END_LoadQuery

    my $sth = $dbh->prepare($loadQuery);

    my $rc = $sth->execute;
    $self->{_FieldNames} = $sth->{NAME};
    $self->{_Data}       = $sth->fetchall_arrayref;
    $sth->finish;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  loadSinglePlatform
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loads a single platform from the database based on the URL parameter
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
#sub loadSinglePlatform {
#
#    #Grab object and id from URL.
#    my $self = shift;
#    my $q    = $self->{_cgi};
#    my $dbh  = $self->{_dbh};
#
#    #Run the SQL and get the data into the object.
#    my $sth = $dbh->prepare(<<"END_LoadSingleQuery");
#select
#    pname,
#    def_f_cutoff,
#    def_p_cutoff,
#    species,
#    pid,
#    CASE WHEN isAnnotated THEN 'Y' ELSE 'N' END AS 'Is Annotated'
#from platform
#WHERE pid=?
#END_LoadSingleQuery
#
#    my $rc = $sth->execute( $self->{_pid} );
#    $self->{_Data} = $sth->fetchall_arrayref;
#
#    foreach ( @{ $self->{_Data} } ) {
#        $self->{_PName}        = $_->[0];
#        $self->{_def_f_cutoff} = $_->[1];
#        $self->{_def_p_cutoff} = $_->[2];
#        $self->{_Species}      = $_->[3];
#    }
#
#    $sth->finish;
#    return 1;
#}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Load the data from the submitted form.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;

    my $q = $self->{_cgi};
    $self->{_PName}        = $q->param('pname');
    $self->{_def_f_cutoff} = $q->param('def_f_cutoff');
    $self->{_def_p_cutoff} = $q->param('def_p_cutoff');
    $self->{_Species}      = $q->param('species');

    # try to get platform id first from POST parameters, second from the URL
    $self->{_pid} = $q->param('id');
    $self->{_pid} = $q->url_param('id') if not defined $self->{_pid};

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  ajax_update
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Update part of CRUD operations. This is a *very generic* method
#                handling AJAX request -- basically update a key-value pair in a
#                specified row in the table.
#       THROWS:  no exceptions
#     COMMENTS:  :TODO:07/04/2011 16:48:45:es: Abstract out this method into a
#                base class for SGX modules.
#                :TODO:07/28/2011 00:38:55:es: Abstract out the model part of
#                this method into the model composable of the abstract class.
#     SEE ALSO:  n/a
#===============================================================================
sub ajax_update {

    my ( $self, %args ) = @_;

    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};

    my $valid_fields = $args{valid_fields};
    my $table        = $args{table};
    my $column       = $args{key};

    my %is_valid_field = map { $_ => 1 } @$valid_fields;

    if ( !$s->is_authorized('user') ) {

        # Send 401 Unauthorized header
        print $q->header( -status => 401 );
        $s->commit;    # must commit session before exit
        exit(0);
    }
    my $field = $q->param('field');
    if ( !defined($field) || $field eq '' || !$is_valid_field{$field} ) {

        # Send 400 Bad Request header
        print $q->header( -status => 400 );
        $s->commit;    # must commit session before exit
        exit(0);
    }

    # after field name has been checked against %valid_fields hash, it
    # is safe to fill it in directly:
    my $query = "update $table set $field=? where $column=?";

    # :TODO:07/27/2011 23:42:00:es: implement transactional updates. Separate
    # statement preparation from execution.

    # Note that when $q->param('value') is undefined, DBI should fill in
    # NULL into the corresponding placeholder.
    my $rc =
      eval { $dbh->do( $query, undef, $q->param('value'), $q->param('id') ); }
      || 0;

    if ( $rc > 0 ) {

        # Normal condition -- at least some rows were updated:
        # Send 200 OK header
        print $q->header( -status => 200 );
        $s->commit;    # must commit session before exit
        exit(1);
    }
    elsif ( my $exception = $@ ) {

        # Error condition -- no rows updated:
        # Send 400 Bad Request header
        print $q->header( -status => 400 );
        $s->commit;    # must commit session before exit
        $exception->throw();
    }
    else {

        # Normal condition -- no rows updated:
        # Send 404 Not Found header
        print $q->header( -status => 404 );
        $s->commit;    # must commit session before exit
        exit(0);
    }
    $s->commit;        # must commit session before exit
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  getPlatformList
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformList {
    my $self = shift;

    my $data     = $self->{_Data};    # data source
    my $sort_col = 3;                 # column to sort on

    my @tmp;
    foreach my $row ( sort { $a->[$sort_col] cmp $b->[$sort_col] } @$data ) {
        my $i = 0;
        push @tmp, +{ map { $i++ => $_ } @$row };
    }

    return \@tmp;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  getTableHTML
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Draw the javascript and HTML for the platform table.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getTableHTML {
    my $self = shift;

    my $q = $self->{_cgi};

    return
      $q->h2('Manage Platforms'),
      $q->h3( { -id => 'caption' }, '' ),
      $q->div(
        $q->a( { -id => 'PlatformTable_astext' }, 'View as plain text' ) ),
      $q->div( { -id => 'PlatformTable' }, '' ),
      $q->h3( { -id => 'Add_Caption' }, 'Add Platform' ),
      $q->start_form(
        -method   => 'POST',
        -action   => $q->url( -absolute => 1 ) . '?a=managePlatforms&b=add',
        -onsubmit => 'return validate_fields(this, [\'pname\',\'species\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'pname' }, 'Name:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'pname',
                -id        => 'pname',
                -maxlength => 120
            )
        ),
        $q->dt( $q->label( { -for => 'def_f_cutoff' }, 'Default FC cutoff' ) ),
        $q->dd(
            $q->textfield( -name => 'def_f_cutoff', -id => 'def_f_cutoff' )
        ),
        $q->dt(
            $q->label( { -for => 'def_p_cutoff' }, 'Default P-val. cutoff' )
        ),
        $q->dd(
            $q->textfield( -name => 'def_p_cutoff', -id => 'def_p_cutoff' )
        ),
        $q->dt( $q->label( { -for => 'species' }, 'Species:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'species',
                -id        => 'species',
                -maxlength => 255
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -class => 'button black bigrounded',
                -value => 'Add'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  getTableJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getTableJS {
    my $self = shift;

    my $names = $self->{_FieldNames};
    my $q     = $self->{_cgi};

    my $url_prefix = $q->url( -absolute => 1 );

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );
    return $js->define(
        {
            JSPlatformList => {
                caption => 'Showing all Platforms',
                records => $self->getPlatformList()
            }
        },
        declare => 1
    ) . <<"END_TableInfo";

YAHOO.util.Event.addListener("PlatformTable_astext", "click", export_table, JSPlatformList, true);

YAHOO.util.Event.addListener(window, 'load', function() {
    function createPlatformCellUpdater(field) {
        /*
         * this functions makes a hammer after it first builds a factory in the
         * neighborhood that makes hammers using the hammer construction factory
         * spec sheet in CellUpdater.js 
         */
        return createCellUpdater(field, "$url_prefix?a=managePlatforms", "4");
    }
    
    YAHOO.widget.DataTable.Formatter.formatPlatformDeleteLink = function(elCell, oRecord, oColumn, oData) 
    {
        elCell.innerHTML = '<a title="Delete Platform" onclick="alert(\\'This feature has been disabled till password protection can be implemented.\\');return false;" target="_self" href="$url_prefix?a=managePlatforms&b=delete&id=" + oData + "">Delete</a>';
    };
    
    var myColumnDefs = [
        {key:"0", sortable:true, resizeable:true, label:"$names->[0]",
    editor:createPlatformCellUpdater("pname")},
        {key:"1", sortable:true, resizeable:true, label:"$names->[1]",
    editor:createPlatformCellUpdater("def_f_cutoff")},
        {key:"2", sortable:true, resizeable:true, label:"$names->[2]",
    editor:createPlatformCellUpdater("def_p_cutoff")}, 
        {key:"3", sortable:true, resizeable:true, label:"$names->[3]",
    editor:createPlatformCellUpdater("species")},
        {key:"5", sortable:true, resizeable:true, label:"$names->[5]"},
        {key:"4", sortable:false, resizeable:true, label:"Delete Platform",formatter:"formatPlatformDeleteLink"},
        {key:"6", sortable:true, resizeable:true, label:"Probe Count"},
        {key:"7", sortable:true, resizeable:true, label:"Probe Sequences"},
        {key:"8", sortable:true, resizeable:true, label:"Probe Locations"},
        {key:"9", sortable:true, resizeable:true, label:"Probes with Annotations"},
        {key:"10", sortable:true, resizeable:true, label:"Gene Symbols"},
        {key:"11", sortable:true, resizeable:true, label:"Gene Names"}
    ];
    
        YAHOO.util.Dom.get("caption").innerHTML = JSPlatformList.caption;
        
        var myDataSource         = new YAHOO.util.DataSource(JSPlatformList.records);
        myDataSource.responseType     = YAHOO.util.DataSource.TYPE_JSARRAY;
        myDataSource.responseSchema     = {fields: ["0","1","2","3","4","5","6","7","8","9","10","11"]};
        var myData_config         = {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
        var myDataTable         = new YAHOO.widget.DataTable("PlatformTable", myColumnDefs, myDataSource, myData_config);
        
        // Set up editing flow 
        var highlightEditableCell = function(oArgs) { 
            var elCell = oArgs.target; 
            if(YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) { 
                this.highlightCell(elCell); 
            } 
        }; 
        
        myDataTable.subscribe("cellMouseoverEvent", highlightEditableCell); 
        myDataTable.subscribe("cellMouseoutEvent", myDataTable.onEventUnhighlightCell); 
        myDataTable.subscribe("cellClickEvent", myDataTable.onEventShowCellEditor);
});
END_TableInfo
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  insertNewPlatform
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub insertNewPlatform {
    my $self = shift;

    my $dbh = $self->{_dbh};

    my $query = <<"END_InsertQuery";
INSERT INTO platform 
    (pname, def_f_cutoff, def_p_cutoff, species) 
VALUES (?, ?, ?, ?)
END_InsertQuery

    my $rc = $dbh->do(
        $query, undef, $self->{_PName},
        $self->{_def_f_cutoff},
        $self->{_def_p_cutoff},
        $self->{_Species}
    );

    $self->{_pid} = $dbh->{mysql_insertid};

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  deletePlatform
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub deletePlatform {
    my ($self) = @_;

    my $pid = $self->{_pid};

    my $dbh = $self->{_dbh};

    # :TODO:07/28/2011 02:40:30:es: implement transactions for ACID
    my @queryDelete = (
'DELETE FROM annotates WHERE rid IN (SELECT rid FROM probe WHERE pid=?)',
'DELETE FROM experiment WHERE eid IN (SELECT eid FROM StudyExperiemnt WHERE stid IN (SELECT stid FROM study WHERE pid=?))',
'DELETE FROM StudyExperiemnt WHERE stid IN (SELECT stid FROM study WHERE pid=?)',
'DELETE FROM microarray WHERE rid in (SELECT rid FROM probe WHERE pid=?)',
        'DELETE FROM probe WHERE pid=?',
        'DELETE FROM study WHERE pid=?',
        'DELETE FROM platform WHERE pid=?'
    );
    foreach my $deleteStatement (@queryDelete) {

        # :TODO:07/28/2011 02:42:34:es: as of current, not implemented
        #$dbh->do( $deleteStatement, undef, $pid );
    }

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  editPlatform
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub editPlatform {
    my $self = shift;

    my $q = $self->{_cgi};

    #Edit existing platform.
    print $q->h2('Editing Platform'),
      $q->start_form(
        -method => 'POST',
        -action => $q->url( -absolute => 1 )
          . '?a=managePlatforms&b=editSubmit&id='
          . $self->{_pid},
        -onsubmit => 'return validate_fields(this, [\'pname\',\'species\']);'
      ),
      $q->dl(
        $q->dt('pname:'),
        $q->dd(
            $q->textfield(
                -name      => 'pname',
                -id        => 'pname',
                -maxlength => 120,
                -value     => $self->{_PName}
            )
        ),
        $q->dt( $q->label( { -for => 'def_f_cutoff' }, 'def_f_cutoff:' ) ),
        $q->dd(
            $q->textfield(
                -name => 'def_f_cutoff',
                -id   => 'def_f_cutoff',
                value => $self->{_def_f_cutoff}
            )
        ),
        $q->dt( $q->label( { -for => 'def_p_cutoff' }, 'def_p_cutoff:' ) ),
        $q->dd(
            $q->textfield(
                -name => 'def_p_cutoff',
                -id   => 'def_p_cutoff',
                value => $self->{_def_p_cutoff}
            )
        ),
        $q->dt( $q->label( { -for => 'species' }, 'species:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'species',
                -id        => 'species',
                -maxlength => 255,
                value      => $self->{_Species}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'SaveEdits',
                -id    => 'SaveEdits',
                -value => 'Save Edits'
            ),
            $q->span( { -class => 'separator' }, ' / ' )
        )
      ),
      $q->end_form;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  editSubmitPlatform
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub editSubmitPlatform {
    my $self = shift;

    my $dbh = $self->{_dbh};
    $dbh->do(
        <<"END_UpdateQuery",
UPDATE platform 
SET pname=?, def_f_cutoff=?, def_p_cutoff=?, species=?
WHERE pid=?
END_UpdateQuery
        undef,
        $self->{_PName},
        $self->{_def_f_cutoff},
        $self->{_def_p_cutoff},
        $self->{_Species},
        $self->{_pid}
    );

    return 1;
}

1;

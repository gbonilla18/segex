
=head1 NAME

SGX::ManagePlatforms

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing platforms.

=head1 AUTHORS
Michael McDuffie

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
use SGX::DrawingJavaScript;
use JSON::XS;

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
    my $class = shift;

    my $self = {
        _dbh => shift,
        _cgi => shift,

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
#  DESCRIPTION:  executes appropriate method for the given action
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch {
    my ( $self, $action ) = @_;

    my $q = $self->{_cgi};

    $action = '' if not defined($action);
    switch ($action) {
        case 'add' {
            $self->loadFromForm();
            $self->insertNewPlatform();
            print "<br />Record added - Redirecting...<br />";

            my $redirectSite =
                $q->url( -absolute => 1 )
              . '?a=uploadAnnot&newpid='
              . $self->{_pid};
            my $redirectString =
"<script type=\"text/javascript\">window.location = \"$redirectSite\"</script>";
            print "$redirectString";
        }
        case 'delete' {
            $self->loadFromForm();
            $self->deletePlatform();
            print "<br />Record deleted - Redirecting...<br />";

            my $redirectSite = $q->url( -absolute => 1 ) . '?a=managePlatforms';
            my $redirectString =
"<script type=\"text/javascript\">window.location = \"$redirectSite\"</script>";
            print "$redirectString";
        }
        else {

            # default action: just display the Manage Platforms form
            $self->loadAllPlatforms();
            $self->showPlatforms();
        }
    }
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

    my $sth = $dbh->prepare(<<"END_LoadQuery");
SELECT platform.pname, 
    platform.def_f_cutoff AS 'Default Fold Change', 
    platform.def_p_cutoff AS 'Default P-Value', 
    platform.species AS 'Species',
    platform.pid,
    CASE 
        WHEN isAnnotated THEN 'Yes' 
        ELSE 'No'
    END AS 'Annotated',
    COUNT(probe.rid) AS 'Probe Count',
    COUNT(probe.probe_sequence) AS 'Probe Sequences',
    COUNT(probe.location) AS 'Locations',
    COUNT(annotates.gid) AS 'Probes with Annotations',
    COUNT(gene.seqname) AS 'Gene Symbols',
    COUNT(gene.description) AS 'Gene Names'    
FROM platform
LEFT JOIN probe USING(pid)
LEFT JOIN annotates USING(rid)
LEFT JOIN gene USING(gid)
GROUP BY pid
END_LoadQuery
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
sub loadSinglePlatform {

    #Grab object and id from URL.
    my $self = shift;
    my $q    = $self->{_cgi};
    my $dbh  = $self->{_dbh};

    $self->{_pid} = $q->url_param('id');

    #Run the SQL and get the data into the object.
    my $sth = $dbh->prepare(<<"END_LoadSingleQuery");
select 
    pname, 
    def_f_cutoff, 
    def_p_cutoff, 
    species,
    pid,
    CASE WHEN isAnnotated THEN 'Y' ELSE 'N' END AS 'Is Annotated' 
from platform 
WHERE pid=?
END_LoadSingleQuery

    my $rc = $sth->execute( $self->{_pid} );
    $self->{_Data} = $sth->fetchall_arrayref;

    foreach ( @{ $self->{_Data} } ) {
        $self->{_PName}        = $_->[0];
        $self->{_def_f_cutoff} = $_->[1];
        $self->{_def_p_cutoff} = $_->[2];
        $self->{_Species}      = $_->[3];
    }

    $sth->finish;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  loadFromForm
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Load the data from the submitted form.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadFromForm {
    my $self = shift;

    my $q = $self->{_cgi};
    $self->{_PName}        = $q->param('pname');
    $self->{_def_f_cutoff} = $q->param('def_f_cutoff');
    $self->{_def_p_cutoff} = $q->param('def_p_cutoff');
    $self->{_Species}      = $q->param('species');
    $self->{_pid}          = $q->url_param('id');

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  showPlatforms
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Draw the javascript and HTML for the platform table.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub showPlatforms {
    my $self = shift;

    my $q = $self->{_cgi};

    my @JSPlatformList;

    #Loop through data and load into JavaScript array.
    foreach my $row ( sort { $a->[3] cmp $b->[3] } @{ $self->{_Data} } ) {
        my $i = 0;
        push @JSPlatformList, +{ map { $i++ => $_ } @$row };
    }

    print '<h2>Manage Platforms</h2><br /><br />' . "\n";
    print '<h3 name = "caption" id="caption"></h3>' . "\n";
    print '<div><a id="PlatformTable_astext">View as plain text</a></div>'
      . "\n";
    print '<div id="PlatformTable"></div>' . "\n";
    print "<script type=\"text/javascript\">\n";
    print sprintf(
        <<"END_JSPlatformList",
var JSPlatformList = {
    caption: 'Showing all Platforms',
    records: %s
};
END_JSPlatformList
        encode_json( \@JSPlatformList )
    );

    print
"YAHOO.util.Event.addListener(\"PlatformTable_astext\", \"click\", export_table, JSPlatformList, true);\n";
    $self->printTableInformation();
    $self->printDrawResultsTableJS();

    print "</script>\n";

    print '<br /><h3 name = "Add_Caption" id = "Add_Caption">Add Platform</h3>'
      . "\n";

    print $q->start_form(
        -method   => 'POST',
        -action   => $q->url( -absolute => 1 ) . '?a=managePlatforms&b=add',
        -onsubmit => 'return validate_fields(this, [\'pname\',\'species\']);'
      ),
      $q->dl(
        $q->dt('pname:'),
        $q->dd(
            $q->textfield(
                -name      => 'pname',
                -id        => 'pname',
                -maxlength => 120
            )
        ),
        $q->dt('def_f_cutoff:'),
        $q->dd(
            $q->textfield( -name => 'def_f_cutoff', -id => 'def_f_cutoff' )
        ),
        $q->dt('def_p_cutoff:'),
        $q->dd(
            $q->textfield( -name => 'def_p_cutoff', -id => 'def_p_cutoff' )
        ),
        $q->dt('species:'),
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
                -name  => 'AddPlatform',
                -id    => 'AddPlatform',
                -class => 'css3button',
                -value => 'Add Platform'
            )
        )
      ),
      $q->end_form;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  printDrawResultsTableJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub printDrawResultsTableJS {
    my $self = shift;
    print <<"END_printDrawResultsTableJS";
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
END_printDrawResultsTableJS

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  printTableInformation
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub printTableInformation {
    my $self = shift;

    my $arrayRef = $self->{_FieldNames};
    my @names    = @$arrayRef;
    my $q        = $self->{_cgi};
    my $deleteURL =
      $q->url( absolute => 1 ) . '?a=managePlatforms&b=delete&id=';
    my $editURL = $q->url( absolute => 1 ) . '?a=managePlatforms&b=edit&id=';

    #This is the code to use the AJAXy update box for platform name..
    my $postBackURLpname = '"' . $q->url( -absolute => 1 ) . '?a=updateCell"';
    my $postBackQueryParameterspname =
'"type=platform&pname=" + escape(newValue) + "&fold=" + encodeURI(record.getData("1")) + "&pvalue=" + encodeURI(record.getData("2")) + "&pid=" + encodeURI(record.getData("4"))';
    my $textCellEditorObjectpname =
      SGX::DrawingJavaScript->new( $postBackURLpname,
        $postBackQueryParameterspname );

    #This is the code to use the AJAXy update box for Default Fold Change..
    my $postBackURLfold = '"' . $q->url( -absolute => 1 ) . '?a=updateCell"';
    my $postBackQueryParametersfold =
'"type=platform&pname=" + encodeURI(record.getData("0")) + "&fold=" + escape(newValue) + "&pvalue=" + encodeURI(record.getData("2")) + "&pid=" + encodeURI(record.getData("4"))';
    my $textCellEditorObjectfold =
      SGX::DrawingJavaScript->new( $postBackURLfold,
        $postBackQueryParametersfold );

    #This is the code to use the AJAXy update box for P-value..
    my $postBackURLpvalue = '"' . $q->url( -absolute => 1 ) . '?a=updateCell"';
    my $postBackQueryParameterspvalue =
'"type=platform&pname=" + encodeURI(record.getData("0")) + "&fold=" + encodeURI(record.getData("1")) + "&pvalue=" + escape(newValue) + "&pid=" + encodeURI(record.getData("4"))';
    my $textCellEditorObjectpvalue =
      SGX::DrawingJavaScript->new( $postBackURLpvalue,
        $postBackQueryParameterspvalue );

    print '
        YAHOO.widget.DataTable.Formatter.formatPlatformDeleteLink = function(elCell, oRecord, oColumn, oData) 
        {
            elCell.innerHTML = "<a title=\"Delete Platform\" onclick=\"alert(\'This feature has been disabled till password protection can be implemented.\');return false;\" target=\"_self\" href=\"'
      . $deleteURL . '" + oData + "\">Delete</a>";
        }

        YAHOO.util.Dom.get("caption").innerHTML = JSPlatformList.caption;
        var myColumnDefs = [
        {key:"0", sortable:true, resizeable:true, label:"'
      . $names[0]
      . '",editor:'
      . $textCellEditorObjectpname->printTextCellEditorCode() . '},
        {key:"1", sortable:true, resizeable:true, label:"'
      . $names[1]
      . '",editor:'
      . $textCellEditorObjectfold->printTextCellEditorCode() . '},
        {key:"2", sortable:true, resizeable:true, label:"'
      . $names[2]
      . '",editor:'
      . $textCellEditorObjectpvalue->printTextCellEditorCode() . '}, 
        {key:"3", sortable:true, resizeable:true, label:"' . $names[3] . '"},
        {key:"5", sortable:true, resizeable:true, label:"' . $names[5] . '"},
        {key:"4", sortable:false, resizeable:true, label:"Delete Platform",formatter:"formatPlatformDeleteLink"},
        {key:"6", sortable:false, resizeable:true, label:"Probe Count"},
        {key:"7", sortable:false, resizeable:true, label:"Probe Sequences"},
        {key:"8", sortable:false, resizeable:true, label:"Probe Locations"},
        {key:"9", sortable:false, resizeable:true, label:"Probes with Annotations"},
        {key:"10", sortable:false, resizeable:true, label:"Gene Symbols"},
        {key:"11", sortable:false, resizeable:true, label:"Gene Names"}
        ];' . "\n";
    return 1;
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

    $dbh->do(
        <<"END_InsertQuery",
INSERT INTO platform 
    (pname, def_f_cutoff, def_p_cutoff, species) 
VALUES (?, ?, ?, ?)
END_InsertQuery
        undef,
        $self->{_PName},
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
    my $self = shift;

    my $dbh = $self->{_dbh};

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
        $dbh->do( $deleteStatement, undef, $self->{_pid} );
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

    print '<h2>Editing Platform</h2><br /><br />' . "\n";

    #Edit existing platform.
    print $q->start_form(
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
        $q->dt('def_f_cutoff:'),
        $q->dd(
            $q->textfield(
                -name => 'def_f_cutoff',
                -id   => 'def_f_cutoff',
                value => $self->{_def_f_cutoff}
            )
        ),
        $q->dt('def_p_cutoff:'),
        $q->dd(
            $q->textfield(
                -name => 'def_p_cutoff',
                -id   => 'def_p_cutoff',
                value => $self->{_def_p_cutoff}
            )
        ),
        $q->dt('species:'),
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

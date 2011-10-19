#
#===============================================================================
#
#         FILE:  Base.pm
#
#  DESCRIPTION:
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  08/11/2011 11:50:41
#     REVISION:  ---
#===============================================================================

package SGX::Strategy::Base;

use strict;
use warnings;

use URI::Escape qw/uri_escape/;
use Data::Dumper;

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  In Perl, class attributes cannot be inherited, which means we
#                should not use them for anything that is very specific to the
#                problem domain of the given class.
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, %param ) = @_;
    my ( $dbh, $q, $s, $action ) = @param{qw{dbh cgi user_session selector}};

    my $self = {
        _dbh          => $dbh,
        _cgi          => $q,
        _UserSession  => $s,
        _ResourceName => $action,

        _js_src_yui   => [],
        _js_src_code  => [],
        _css_src_yui  => [],
        _css_src_code => [],
        _header       => {},
        _title        => '',

        _permission_level => 'user'
    };

    bless $self, $class;

    $self->register_actions(

        # default action
        '' => { head => 'default_head', body => 'default_body' }

    );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  url
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Simply a wrapper around CGI.pm's $q->url() method.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub url {
    return shift->{_cgi}->url(@_);
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_resource_uri
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_resource_uri {
    my ( $self, %args )   = @_;
    my ( $q,    $action ) = @$self{qw/_cgi _ResourceName/};

    my %overridden = ( a => $action, %args );
    my @components;
    while ( my ( $key, $value ) = each %overridden ) {
        if ( defined $value ) {
            push @components, uri_escape($key) . '=' . uri_escape($value);
        }
    }
    my $ret =
      $q->url( -absolute => 1 )
      . ( (@components) ? '?' . join( '&', @components ) : '' );
    return $ret;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  set_title
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================a
sub set_title {
    my ( $self, $title ) = @_;
    $self->{_title} = $title;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_title
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================a
sub get_title {
    return shift->{_title};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_header
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_header {
    return %{ shift->{_header} };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  set_header
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub set_header {
    my ( $self, %args ) = @_;
    $self->{_header} = \%args;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_body {
    my $body = shift->{_body};
    return if not defined $body;
    return $body;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  set_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub set_body {
    my ( $self, $arg ) = @_;
    $self->{_body} = $arg;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  redirect
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub redirect {
    my $self = shift;
    my $location = shift || '';
    $self->set_header(
        -location => $location,
        -status   => 302          # 302 Found
    );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  request_uri
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub request_uri {
    my $self = shift;
    my $q    = $self->{_cgi};
    return ( defined $q && $q->can('request_uri') )
      ? $q->request_uri()
      : $ENV{REQUEST_URI};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_dispatch_action
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_dispatch_action {
    my $self = shift;
    my $q    = $self->{_cgi};

    my $action = $self->{_ActionName};
    return $action if defined $action;

    # first try to get action name from URL parameters (this will allow us to
    # define certain actions as resources later). If that fails, check POSTed
    # data.
    $action = $q->url_param('b');
    $action = $q->param('b') if not defined $action;
    $action = '' if not defined $action;
    $self->set_action($action);
    return $action;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  _dispatch_by
#   PARAMETERS:  action => method
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _dispatch_by {
    my $self   = shift;
    my $action = shift || '';
    my $hook   = shift;

    my $s = $self->{_UserSession};

    # execute methods that are in the intersection of those found in the
    # requested dispatch table and those which can actually be executed.
    my $dispatch_tables = $self->{_dispatch_tables} || {};
    my $meta = ( $self->{_dispatch_tables} || {} )->{$action} || {};

    my $perm =
      ( defined $meta->{perm} ) ? $meta->{perm} : $self->{_permission_level};

    my $is_auth = $s->is_authorized($perm);
    if ( $is_auth == 1 ) {

        # execute hook
        my $method = $meta->{$hook};
        my @ret =
          ( defined($method) && $self->can($method) ) ? $self->$method(@_)
          : (
            ( ( $hook eq 'head' or $hook eq 'body' ) and $action ne '' )
            ? $self->_dispatch_by( '' => $hook )
            : ()
          );
        return @ret;
    }
    else {

        # For normal requests, 302 Found (with a redirect to login page) should
        # be returned when user is unauthorized -- while AJAX requests should
        # get 401 Authentication Required. Finally, for AJAX requests we do not
        # display body or bother to do further processing.
        if ( $action =~ m/^ajax_/ ) {
            $self->set_body(
'Your user account does not have the necessary privileges to perform this operation'
            );

            $self->set_header(
                -status => 401,    # 401 Unauthorized
                -cookie => undef
            );
            return 1;              # don't show body
        }
        elsif ( $is_auth == 0 ) {

            # redirect to login
            $self->redirect( '?a=profile&b=form_login&destination='
                  . uri_escape( $self->request_uri() ) );
            return 1;              # don't show body
        }
        elsif ( $is_auth == -1 and $hook eq 'head' and $action ) {

            # try default action
            return $self->_dispatch_by( '' => $hook );
        }
        else {

            # redirect to main page
            $self->redirect( $self->url( -absolute => 1 ) );
            return 1;              # don't show body
        }
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
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

    my $action = $self->get_dispatch_action();

    # otherwise we always do one of the three things: (1) dispatch to readall
    # (id not present), (2) dispatch to readrow (id present), (3) redirect if
    # preliminary processing routine (e.g. create request handler) tells us so.
    #

    return if $self->_dispatch_by( $action => 'redirect' );   # do not show body
    return $self->_dispatch_by( $action => 'head' );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  set_action
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub set_action {
    my $self = shift;
    $self->{_ActionName} = shift;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Show body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch {
    my $self = shift;

    my $action = $self->get_dispatch_action();

    # :TRICKY:08/17/2011 13:00:12:es: CGI.pm -nosticky option seems to not be
    # working as intended. See: http://www.perlmonks.org/?node_id=689507. Using
    # delete_all() ensures that param array is cleared and no form field
    # inherits old values.
    my $q = $self->{_cgi};
    $q->delete_all();

    return $self->_dispatch_by( $action => 'body' );    # show body
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  default_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Stub method (to be overridden)
#     SEE ALSO:  n/a
#===============================================================================
sub default_head { return 1; }

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Stub method (to be overridden)
#     SEE ALSO:  n/a
#===============================================================================
sub default_body { return ''; }

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  set_attributes
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub set_attributes {
    my ( $self, %attrs ) = @_;
    while ( my ( $key, $value ) = each(%attrs) ) {
        $self->{$key} = $value;
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  register_actions
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub register_actions {
    my ( $self, %args ) = @_;
    my $dispatch_tables = $self->{_dispatch_tables} || {};
    $self->{_dispatch_tables} = $dispatch_tables;
    while ( my ( $action, $table_slice ) = each %args ) {
        my $action_table = $dispatch_tables->{$action} || {};
        $dispatch_tables->{$action} = $action_table;
        while ( my ( $type, $hook ) = each %$table_slice ) {
            $action_table->{$type} = $hook;
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  view_start_get_form
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Convenience method for startingn HTML form that uses GET
#                request. Such forms should not include URI parameters in the
#                action string because they will be ignored, so we use
#                $q->url(-relative => 1) method.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  view_hidden_resource
#===============================================================================
sub view_start_get_form {
    my $self = shift;
    my $q    = $self->{_cgi};
    return $q->start_form(
        -method  => 'GET',
        -enctype => 'application/x-www-form-urlencoded',
        -action  => $self->url( -absolute => 1 )
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  view_show_messages
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub view_show_messages {
    my $self = shift;
    my $q    = $self->{_cgi};
    return ( map { $q->pre( { -class => 'error_message' }, $_ ) }
          @{ $self->{_error_messages} || [] } ),
      ( map { $q->p( { -class => 'message' }, $_ ) }
          @{ $self->{_messages} || [] } );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  view_show_content
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub view_show_content {
    my $self = shift;

    require SGX::Body;
    my $body = SGX::Body->new($self);    # Body class knows about Strategy::Base
    return $body->get_content();
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  view_hidden_resource
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Required for GET forms (those that use view_start_get_form).
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  view_start_get_form
#===============================================================================
sub view_hidden_resource {
    my $self = shift;
    my $q    = $self->{_cgi};
    return $q->hidden( -name => 'a', -value => $self->{_ResourceName} );
}

1;

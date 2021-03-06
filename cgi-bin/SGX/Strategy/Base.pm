package SGX::Strategy::Base;

use strict;
use warnings;

use SGX::Abstract::Exception ();
use URI::Escape qw/uri_escape/;
require Lingua::EN::Inflect;
require Text::Autoformat;
require SGX::Abstract::JSEmitter;

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  n/a
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, %args ) = @_;

    # copy configuration attributes
    my $self = +{ %{ $args{config} || {} } };

    # start session from cookie or (if no cookie found) a new one
    if ( exists $args{restore_session_from} ) {
        my $s = $self->{_UserSession};
        $s->restore( $args{restore_session_from} ) if defined $s;
    }

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Base
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

    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );
    $self->set_attributes(
        _title            => '',
        _permission_level => 'readonly',

        _js_emitter => $js,
        _js_buffer  => [],
        _js_env     => {},

        _js_src_yui  => ['yahoo-dom-event/yahoo-dom-event.js'],
        _js_src_code => [],

        _css_src_yui  => [],
        _css_src_code => [],

        _header          => {},
        _prepared_header => { -status => 200, -type => 'text/html' }
    );

    # default action is identified simply by empty string
    $self->register_actions(
        '' => { head => 'default_head', body => 'default_body' } );

    return $self;
}

#===  FUNCTION  ================================================================
#         NAME:  format_title
#      PURPOSE:  Text::Autoformat::autoformat leaves blank space at the end of
#                output which needs to be trimmed.
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  capitalize first letters of words in titles
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub format_title {
    my $self = shift;
    my $out = Text::Autoformat::autoformat( shift, { case => 'title' } );
    $out =~ s/\s+$//;
    return $out;
}

#===  FUNCTION  ================================================================
#         NAME:  pluralize_noun
#      PURPOSE:  pluralise English nouns and pronouns
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  PL_N('word', 2) returns 'words'.
#     SEE ALSO:  n/a
#===============================================================================
sub pluralize_noun {
    my $self  = shift;
    my $noun  = shift;
    my $count = shift;
    $count = 2 if not defined $count;
    return Lingua::EN::Inflect::PL_N( $noun, $count );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  Base
#       METHOD:  safe_execute
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub safe_execute {
    my $self    = shift;
    my $lambda  = shift;
    my $message = shift;
    eval {
        $lambda->();
        1;
    } or do {
        my $exception;
        if ( $exception =
            Exception::Class->caught('Exception::Class::DBI::STH') )
        {

            # catch execute exceptions only
            $self->add_message(
                { -class => 'error' },
                sprintf(
                    'DBI Error %d: %s',
                    $exception->err, $exception->errstr
                )
            );
        }
        elsif ( $exception = Exception::Class->caught() ) {
            if ( eval { $exception->can('rethrow') } ) {
                $exception->rethrow();
            }
            else {
                SGX::Exception::Internal->throw( error => "$exception" );
            }
        }
        else {
            SGX::Exception::Internal->throw( error => 'Unknown error' );
        }
    };
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Base
#       METHOD:  add_message
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub add_message {
    my $self = shift;
    push @{ $self->{_messages} }, \@_;
    return 1;
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
    my $self = shift;
    return $self->{_cgi}->url(@_);
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

    my %overridden = (
        a => $action,
        %args
    );
    my @components;
    while ( my ( $key, $value ) = each %overridden ) {
        if ( defined $value and $key ne '#' ) {
            push @components, uri_escape($key) . '=' . uri_escape($value);
        }
    }
    my $hashtag = $overridden{'#'};
    my $ret =
        $q->url( -absolute => 1 )
      . ( (@components) ? '?' . join( '&', @components ) : '' )
      . ( defined $hashtag ? "#$hashtag" : '' );
    return $ret;
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
#===============================================================================
sub get_title {
    my $self = shift;
    return $self->{_title};
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
    my $self    = shift;
    my $q       = $self->{_cgi};
    my $s       = $self->{_UserSession};
    my $cookies = ( defined $s ) ? $s->cookie_array() : [];

    my $prepared_header = $self->{_prepared_header};
    if ( !$self->prepare_head() ) {
        $prepared_header->{-type} = 'text/plain';
    }
    return $q->header(
        %$prepared_header,
        -cookie => $cookies,
        %{ $self->{_header} }
    );
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
    my $self   = shift;
    my $action = $self->{_ActionName};
    return $action if defined $action;

    # first try to get action name from URL parameters (this will allow us to
    # define certain actions as resources later). If that fails, check POSTed
    # data.
    my $q = $self->{_cgi};
    ($action) = $q->param('b');
    ($action) = $q->url_param('b') unless defined $action;
    $action = '' unless defined $action;
    $self->set_action($action);
    return $action;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_volatile
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_volatile {
    my $self  = shift;
    my $field = shift;
    my $s     = $self->{_UserSession};
    return ( defined $s ) ? ( $s->{$field} || {} ) : {};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  is_authorized
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub is_authorized {
    my $self = shift;
    my %args = @_;
    my $perm = $args{level};
    my $s    = $self->{_UserSession};

    if ( defined $s ) {
        return $s->is_authorized( level => $args{level} );
    }
    else {
        require SGX::Session::User;
        return SGX::Session::User::static_auth( undef, $args{level} )
          ? 1
          : 0;
    }
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
    my $action = shift;
    $action = '' if not defined $action;
    my $hook = shift;

    # execute methods that are in the intersection of those found in the
    # requested dispatch table and those which can actually be executed.
    my $dispatch_tables = $self->{_dispatch_tables} || {};
    my $meta = $dispatch_tables->{$action};
    if ( !exists( $dispatch_tables->{$action} ) ) {
        SGX::Exception::HTTP->throw(
            status => 404,
            error =>
              "Don't know how to perform $action on $self->{_ResourceName}"
        );
    }

    my $perm =
      ( defined $meta->{perm} )
      ? $meta->{perm}
      : $self->{_permission_level};

    my $is_auth = $self->is_authorized( level => $perm );
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
    elsif ( $is_auth == 0 ) {

        # redirect to login (unless block prevents infinite loops)
        $self->redirect( '?a=profile&b=form_login&next='
              . uri_escape( $self->request_uri() ) )
          unless $self->{_ResourceName} eq 'profile'
              and $action eq 'form_login';
        return;    # don't show body
    }
    elsif ( $is_auth == -1 and $hook eq 'head' and $action ) {

        # try default action
        return $self->_dispatch_by( '' => $hook );
    }
    else {

        # 403 Unauthorized
        my $show_body = exists( $meta->{show_body} ) ? $meta->{show_body} : 1;
        if ($show_body) {
            return SGX::Exception::HTTP->throw(
                status => 403,
                error  => 'Authorization required'
            );
        }
        else {
            $self->set_header(
                -status => 403,
                -cookie => undef
            );
            $self->add_message( { -class => 'error' },
                'Authorization required' );
            return 1;    ## returning 1 will not show body
        }

        # redirect to main page
        #$self->redirect( $self->url( -absolute => 1 ) )
        #      if $self->{_ResourceName}
        #          or $action;
        #return;    # don't show body
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
    my $self      = shift;
    my $s         = $self->{_UserSession};
    my $show_html = $self->dispatch_js();

    # flush the session data and prepare cookies
    $s->commit() if defined $s;

    return $show_html;
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

    # otherwise we always do one of the three things: (1) dispatch to readall
    # (id not present), (2) dispatch to readrow (id present), (3) redirect if
    # preliminary processing routine (e.g. create request handler) tells us so.

    # do not show body
    return
      if $self->_dispatch_by( $self->get_dispatch_action() => 'redirect' );
    return $self->_dispatch_by( $self->get_dispatch_action() => 'head' );
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

    # :TRICKY:08/17/2011 13:00:12:es: CGI.pm -nosticky option seems to not be
    # working as intended. See: http://www.perlmonks.org/?node_id=689507. Using
    # delete_all() ensures that param array is cleared and no form field
    # inherits old values.
    #
    my $q = $self->{_cgi};
    $q->delete_all();

    # show body
    return $self->_dispatch_by( $self->get_dispatch_action() => 'body' );
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
        -accept_charset => 'ISO-8859-1',
        -method         => 'GET',
        -enctype        => 'application/x-www-form-urlencoded',
        -action         => $self->url( -absolute => 1 )
    );
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

    my $show_html = $self->{_prepared_header}->{-type} eq 'text/html';
    if ($show_html) {
        require SGX::Body;
        my $body =
          SGX::Body->new($self);    # Body class knows about Strategy::Base
        return $body->get_content();
    }
    else {
        return join( "\n",
            map { my $x = shift @$_; ( ref $x eq '' ) ? $x : @$_ }
              @{ $self->{_messages} } );
    }
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

__END__

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



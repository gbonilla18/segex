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

use Data::Dumper;
use URI::Escape;

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
        _title        => ''
    };

    bless $self, $class;

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_uri
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_uri {
    my $self = shift;
    my $q    = $self->{_cgi};
    return $q->url( -absolute => 1 );
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
      . ( ( @components > 0 ) ? '?' . join( '&', @components ) : '' );
    return $ret;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_full_uri
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_full_current_uri {
    my $q = shift->{_cgi};
    return $q->url( -absolute => 1, -query => 1 );
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
#       METHOD:  get_yui_js_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_yui_js_head {
    return @{ shift->{_js_src_yui} };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_js_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_js_head {
    return @{ shift->{_js_src_code} };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_yui_css_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_yui_css_head {
    return @{ shift->{_css_src_yui} };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  get_css_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_css_head {
    return @{ shift->{_css_src_code} };
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
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  require_authorization
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub redirect_unauth {
    my ( $self, $level ) = @_;
    my $s = $self->{_UserSession};

    # Because we are using forms authentication (not HTTP authentication),
    # instead of sending 401 Unauthorized, we redirect to login page.
    if ( !$s->is_authorized($level) ) {
        $self->set_header(
            -status   => 302,                           # 302 Found
            -location => '?a=form_login&destination='
              . uri_escape( $self->get_full_current_uri() )
        );
        return 1;
    }
    return;
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

    # first try to get action name from URL parameters (this will allow us to
    # define certain actions as resources later). If that fails, check POSTed
    # data.
    my $action = $q->url_param('b');
    $action = $q->param('b') if not defined $action;
    $action = ''             if not defined $action;
    $self->{_ActionName} = $action;
    return $action;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  _set_attributes
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _set_attributes {
    my ( $self, %attrs ) = @_;
    while ( my ( $key, $value ) = each(%attrs) ) {
        $self->{$key} = $value;
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  _register_actions
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _register_actions {
    my ( $self, %args ) = @_;
    my $dispatch_tables = $self->{_dispatch_tables};
    while ( my ( $type, $table_slice ) = each(%args) ) {
        my $table =
          ( defined $dispatch_tables->{$type} )
          ? $dispatch_tables->{$type}
          : {};
        $self->{_dispatch_tables}->{$type} = { %$table, %$table_slice };
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  _view_start_get_form
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _view_start_get_form {
    my $self = shift;
    my $q    = $self->{_cgi};
    return $q->start_form(
        -method  => 'GET',
        -enctype => 'application/x-www-form-urlencoded',
        -action  => $self->get_uri()
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::Base
#       METHOD:  _view_hidden_resource
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Required for GET forms (those that use _view_start_get_form)
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _view_hidden_resource {
    my $self = shift;
    my $q    = $self->{_cgi};
    return $q->hidden( -name => 'a', -value => $self->{_ResourceName} );
}

1;

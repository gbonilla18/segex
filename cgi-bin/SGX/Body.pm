#
#===============================================================================
#
#         FILE:  Body.pm
#
#  DESCRIPTION:
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  Motivation:
# To avoid loading all the heavy HTML-generating methods every time a
# request is made, we are putting them in separate class SGX::Body.
#
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  10/15/2011 21:56:29
#     REVISION:  ---
#===============================================================================

package SGX::Body;

use strict;
use warnings;

use SGX::Config;

my $softwareVersion = '0.3.1.1';

my $all_resources = {
    compareExperiments => [
        'Compare Experiments',
        'Compare multiple experiments for significant probes'
    ],
    findProbes => [
        'Find Probes',
        'Search for probes by probe ids, gene symbols, accession numbers'
    ],
    outputData  => ['Output Data'],
    platforms   => ['Manage Platforms'],
    experiments => ['Manage Experiments'],
    studies     => ['Manage Studies'],
    projects    => ['Manage Projects'],
    users       => ['Manage Users'],
    uploadData  => [ 'Upload Data', 'Upload data to a new experiment' ],
    uploadAnnot => [ 'Upload Annotation', 'Upload probe annotations' ],
};

sub make_link_creator {
    my ( $resource_table, $q, $current_action ) = @_;
    my $url_prefix = $q->url( -absolute => 1 );
    return sub {
        my @result;
        foreach my $action (@_) {
            my $val = $resource_table->{$action};
            if ( defined $val ) {
                my ( $label, $title ) = @$val;
                $title = $label if not defined $title;
                my $link_class =
                  ( defined($current_action) && $action eq $current_action )
                  ? 'pressed_link'
                  : '';
                push @result,
                  $q->a(
                    {
                        -class => $link_class,
                        -href  => "$url_prefix?a=$action",
                        -title => $title
                    },
                    $label
                  );
            }
        }
        return \@result;
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Body
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my $class = shift;
    my $self = { _strategy_base => shift, };
    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Body
#       METHOD:  get_content
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_content {
    my $self          = shift;
    my $friend_object = $self->{_strategy_base};
    my $q             = $friend_object->{_cgi};
    return (
        cgi_start_html($friend_object),
        content_header($friend_object),

        # -- do not delete line below -- useful for debugging cookie sessions
        #SGX::Debug::dump_cookies_sent_to_user($s),
        $q->div( { -id => 'content' }, $friend_object->dispatch() ),
        content_footer($friend_object),
        cgi_end_html($friend_object)
    );
}

#######################################################################################
sub cgi_start_html {
    my $obj = shift;
    my ( $q, $js_src_yui, $js_src_code, $css_src_yui, $css_src_code ) =
      @$obj{qw/_cgi _js_src_yui _js_src_code _css_src_yui _css_src_code/};

# to add plain javascript code to the header, add the following to the -script array:
# {-type=>'text/javasccript', -code=>$JSCRIPT}
    my @js;
    foreach (@$js_src_yui) {
        push @js,
          { -type => 'text/javascript', -src => YUI_BUILD_ROOT . '/' . $_ };
    }
    foreach ( { -src => 'form.js' }, @$js_src_code ) {
        $_->{-type} = 'text/javascript';
        if ( defined( $_->{-src} ) ) {
            $_->{-src} = JS_DIR . '/' . $_->{-src};
        }
        push @js, $_;
    }

    my @css;
    foreach ( 'reset-fonts/reset-fonts.css', @$css_src_yui ) {
        push @css, { -type => 'text/css', -src => YUI_BUILD_ROOT . '/' . $_ };
    }
    foreach ( { -src => 'style.css' }, @$css_src_code ) {
        $_->{-type} = 'text/css';
        if ( defined( $_->{-src} ) ) {
            $_->{-src} = CSS_DIR . '/' . $_->{-src};
        }
        push @css, $_;
    }

    return $q->start_html(
        -title  => 'Segex : ' . $obj->get_title(),
        -style  => \@css,
        -script => \@js,
        -class  => 'yui-skin-sam',
        -head   => [
            $q->Link(
                {
                    -type => 'image/x-icon',
                    -href => IMAGES_DIR . '/favicon.ico',
                    -rel  => 'icon'
                }
            ),
            $q->meta(
                {
                    -http_equiv => 'Content-Script-Type',
                    -content    => 'text/javascript'
                }
            ),
            $q->meta(
                {
                    -http_equiv => 'Content-Style-Type',
                    -content    => 'text/css'
                }
            )
        ]
    );
}
#######################################################################################
sub cgi_end_html {
    my $obj = shift;
    my $q   = $obj->{_cgi};
    return $q->end_html;
}
#######################################################################################
sub content_header {
    my $obj = shift;
    my $q   = $obj->{_cgi};
    return $q->div(
        { -id => 'header' },
        $q->h1(
            $q->a(
                {
                    -href  => $q->url( -absolute => 1 ),
                    -title => 'Segex home'
                },
                $q->img(
                    {
                        src    => IMAGES_DIR . '/logo.png',
                        width  => 448,
                        height => 108,
                        alt    => PROJECT_NAME,
                        title  => PROJECT_NAME
                    }
                )
            )
        ),
        $q->ul( { -id => 'sidemenu' }, $q->li( build_sidemenu($obj) ) )
      ),
      build_menu($obj);
}
#######################################################################################
sub content_footer {
    my $obj = shift;
    my $q   = $obj->{_cgi};
    return $q->div(
        { -id => 'footer' },
        $q->ul(
            $q->li(
                $q->a(
                    {
                        -href  => 'http://www.bu.edu/',
                        -title => 'Boston University'
                    },
                    'Boston University'
                )
            ),
            $q->li( 'SEGEX version : ' . $softwareVersion )
        )
    );
}

#===  FUNCTION  ================================================================
#         NAME:  build_side_menu
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_sidemenu {
    my $obj = shift;
    my ( $q, $s ) = @$obj{qw/_cgi _UserSession/};

    my @menu;
    my $url_prefix = $q->url( -absolute => 1 );
    if ( $s->is_authorized('') == 1 ) {

        my $proj_name = $s->{session_cookie}->{proj_name};
        my $curr_proj = $s->{session_cookie}->{curr_proj};
        if ( defined($curr_proj) and $curr_proj ne '' ) {
            $proj_name =
              $q->a( { -href => "$url_prefix?a=projects&id=$curr_proj" },
                $proj_name );
        }
        else {
            $proj_name = '@All Projects';
        }

        # add  options
        push @menu,
          $q->span( { -style => 'color:#999' },
            'Logged in as ' . $s->{session_cookie}->{full_name} );
        push @menu,
          $q->span(
            { -style => 'color:#999' },
            "Current Project: $proj_name ("
              . $q->a( { -href => "$url_prefix?a=profile&b=chooseProject" },
                'change' )
              . ')'
          );
        push @menu,
          $q->a(
            {
                -href  => "$url_prefix?a=profile",
                -title => 'My user profile.'
            },
            'My Profile'
          )
          . $q->span( { -class => 'separator' }, ' / ' )
          . $q->a(
            {
                -href  => "$url_prefix?a=profile&b=logout",
                -title => 'You are signed in as '
                  . $s->{session_stash}->{username}
                  . '. Click on this link to log out.'
            },
            'Log out'
          );
    }
    else {

        # add top options for anonymous users
        push @menu,
          $q->a(
            {
                -href  => "$url_prefix?a=profile&b=form_login",
                -title => 'Log in'
            },
            'Log in'
          )
          . $q->span( { -class => 'separator' }, ' / ' )
          . $q->a(
            {
                -href  => "$url_prefix?a=profile&b=form_registerUser",
                -title => 'Set up a new account'
            },
            'Sign up'
          );
    }
    push @menu,
      $q->a(
        {
            -href  => "$url_prefix?b=about",
            -title => 'About this site'
        },
        'About'
      );
    push @menu,
      $q->a(
        {
            -href   => "$url_prefix?b=help",
            -title  => 'Help pages',
            -target => 'new'
        },
        'Help'
      );
    return \@menu;
}

#===  FUNCTION  ================================================================
#         NAME:  build_menu
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Builds the data structure containing main site links under
#                three different categories.
#
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_menu {
    my $obj = shift;
    my ( $q, $s ) = @$obj{qw/_cgi _UserSession/};
    return '&nbsp' unless 1 == $s->is_authorized('user');

    my $link_creator =
      make_link_creator( $all_resources, $q, $q->url_param('a') );

    my @menu = (
        'Query' =>
          $link_creator->(qw/compareExperiments findProbes outputData/),
        'Manage' =>
          $link_creator->(qw/experiments studies projects platforms users/),
        'Upload' => $link_creator->(qw/uploadData uploadAnnot/)
    );

    my @result;
    while ( my ( $key, $links ) = splice( @menu, 0, 2 ) ) {
        push @result, $q->div( $q->h3($key), $q->ul( $q->li($links) ) );
    }
    return $q->div( { -id => 'menu' }, ( @result > 0 ) ? @result : '&nbsp' );
}

1;

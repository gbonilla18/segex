package SGX::Config;

# This is a module for any debugging or testing subroutines.
# Expect any code you put in here to be removed from the production version.
# Don't forget to put the names of your exported subroutines into the EXPORT array

use strict;
use warnings;
use base qw/Exporter/;

#use lib '/opt/local/lib/perl5/site_perl/5.8.8';
#use lib '/opt/local/lib/perl5/site_perl/5.8.8/darwin-2level';

use File::Basename;
#use DBI;

# CGI::Carp module sends warnings and errors to the browser;
# this is for debugging purposes only -- it will be removed in
# production code.
#BEGIN { 
#	use CGI::Carp qw/carpout fatalsToBrowser warningsToBrowser/;
#	open(LOG, ">>/Users/junior/log/error_log")
#		or die "Unable to append to error_log: $!";
#	carpout(*LOG);
#}

our @EXPORT = qw/max min bounds label_format mysql_connect PROJECT_NAME CGIBIN_PATH HTML_PATH IMAGES_PATH SPECIES/;

sub mysql_connect {
	# connects to the database and returns the handle
	DBI->connect('dbi:mysql:group_2',
		     'group_2_user',
		     'b00g3yk1d')
	or die $DBI::errstr;
}

sub regexp {
	# this subroutine allows one to write a one-liner like this:
	#
	#   $a = regexp($b, 's/text_to_replace/text_to_replace_with/g');
	#
	# instead of the usual two lines:
	#
	#   $a = $b;
	#   $a =~ s/text_to_replace/text_to_replace_with/g;
	#
	my ($var, $pattern) = @_;
	eval "\$var =~ $pattern";
	$var;
}

use constant PROJECT_NAME       => 'SEGEX';
use constant SPECIES		=> 'mouse'; # hardcoding species for now
use constant CGIBIN_PATH	=> dirname($ENV{SCRIPT_NAME});  # current script path
# the regular expression below drops the /cgi-bin prefix from the path
use constant HTML_PATH		=> regexp(CGIBIN_PATH, 's/^\/cgi-bin//');
use constant IMAGES_PATH	=> '/images'.HTML_PATH;

# ===== VARIOUS FUNCTIONS (NOT STRICTLY CONFIGURATION CODE =========================

sub max {
	# returns the greatest value in a list
	my $max = shift;
	foreach (@_) {
		$max = $_ if $_ > $max;
	}
	$max;
}
sub min {
	# returns the smallest value in a list
	my $min = shift;
	foreach (@_) {
		$min = $_ if $_ < $min;
	}
	$min;
}
sub bounds {
	# returns the bounds of an array,
	# assuming undefined values to be zero
	my $a = shift;
	my $mina = (defined($a->[0])) ? $a->[0] : 0;
	my $maxa = $mina;
	for (my $i = 1; $i < @$a; $i++) {
		my $val = (defined($a->[$i])) ? $a->[$i] : 0;
		if ($val < $mina)	{ $mina = $val }
		elsif ($val > $maxa)	{ $maxa = $val }
	}
	return ($mina, $maxa);
}
sub label_format {
	# first rounds the number to only one significant figure,
	# then further rounds the significant figure to 1, 2, 5, or 10
	# (useful for making labels for graphs)
	my $num = shift;
	$num = sprintf('%e', sprintf('%.1g', $num));
	my $fig = substr($num, 0, 1);
	my $remainder = substr($num, 1);

	# choose "nice" numbers:
	if ($fig < 2) {
		# 1 => 1
		# do nothing here
	} elsif ($fig < 4) {
		# 2, 3 => 1
		$fig = 2;
	} elsif ($fig < 8) {
		# 4, 5, 6, 7 => 5
		$fig = 5;
	} else {
		# 8, 9 => 10
		$fig = 10;
	} 
	return $fig.$remainder;
}

1;

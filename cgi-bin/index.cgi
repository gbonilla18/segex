#!/usr/bin/perl -wT

use strict;
use warnings;

use lib qw/./;
use SGX::Config ();
my $app = SGX::Config->new();
$app->run();

# clean exit code is zero
exit(0);

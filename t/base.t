#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 1;
#use Test::More 'no_plan';
use Test::MockModule;

my $CLASS;
BEGIN {
    $CLASS = 'IPC::Simple';
    use_ok $CLASS or die;
}

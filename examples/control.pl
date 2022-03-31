#!/usr/bin/env perl

use warnings;
use strict;
use feature 'say';

use Tesla::Vehicle;

my $car = Tesla::Vehicle->new(auto_wake => 1);

my $cmd=shift @ARGV;
say "$cmd: " . $car->$cmd(@ARGV);

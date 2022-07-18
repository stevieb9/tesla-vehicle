#!/usr/bin/env perl

use warnings;
use strict;
use feature 'say';

use Data::Dumper;
use Tesla::Vehicle;

my $car = Tesla::Vehicle->new(auto_wake => 1);

print Dumper  $car->address;


#!/usr/bin/env perl

use warnings;
use strict;
use feature 'say';

use Data::Dumper;
use Tesla::Vehicle;

my $car = Tesla::Vehicle->new(auto_wake => 1);

my $address = $car->address;

print "\n";

say "road: $address->{road}";

for (sort keys %$address) {
    next if $_ eq 'road';
    next if /ISO3166/;
    say "$_: $address->{$_}";
}

my $gear = $car->gear;
say "gear: $gear";

print "\n";

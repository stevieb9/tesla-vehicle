#!/usr/bin/env perl

use warnings;
use strict;
use feature 'say';

use Data::Dumper;
use Tesla::Vehicle;

my $car = Tesla::Vehicle->new(auto_wake => 1);

my $address = $car->address;
my $id = $car->id;

print "\n";

say "online: " . $car->online;
say "id: $id";

print Dumper $car->charge_history;
exit;

say "road: $address->{road}";

for (sort keys %$address) {
    next if $_ eq 'road';
    next if /ISO3166/;
    say "$_: $address->{$_}";
}

my $gear = $car->gear;
my $charging = $car->charging_state;

say "\n";
say "gear: $gear";
say "charging: $charging";

say "\n";

say $car->latitude;
say $car->longitude;

print "\n";

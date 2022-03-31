#!/usr/bin/env perl

use warnings;
use strict;
use feature 'say';

use Data::Dumper;
use Tesla::Vehicle;

my $x = Tesla::Vehicle->new(auto_wake => 1);

#print Dumper $x->data;

say $x->api_cache_persist(1);

printf(
    "g: %s, s: %d\n",
    $x->gear,
    $x->speed
);

say $x->api_cache_persist(0);


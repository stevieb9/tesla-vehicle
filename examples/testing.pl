use warnings;
use strict;
use feature 'say';

use Data::Dumper;
use Tesla::Vehicle;

my $x = Tesla::Vehicle->new;


say $x->options;

#say $x->trunk_rear_actuate;
#say $x->trunk_rear;
#say "c on: " . $x->climate_on;
#say "c: " . $x->is_climate_on;
#
#say "c off: " . $x->climate_off;
#say "c: " . $x->is_climate_on;
#
#say "du: " . $x->doors_unlock;
#say "d: " . $x->locked;
#say "dl: " . $x->doors_lock;
#say "d: " . $x->locked;


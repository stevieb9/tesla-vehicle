package Tesla::Vehicle;

use warnings;
use strict;

use parent 'Tesla::API';

use Carp qw(croak confess);
use Data::Dumper;

our $VERSION = '0.01';

use constant {
    WAKE_TIMEOUT    => 30,
    WAKE_INTERVAL   => 2,
    WAKE_BACKOFF    => 1.15
};

# Object Related

sub new {
    my ($class, %params) = @_;
    my $self = $class->SUPER::new(%params);

    $self->_id($params{id});
    $self->auto_wake($params{auto_wake});

    return $self;
}
sub auto_wake {
    my ($self, $auto_wake) = @_;

    if (defined $auto_wake) {
        $self->{auto_wake} = $auto_wake;
    }

    return $self->auto_wake // 0;
}

# Vehicle Identification

sub id {
    # Tries to figure out the ID to use in API calls
    my ($self, $id) = @_;

    if (! defined $id) {
        $id = $self->_id;
    }

    if (! $id) {
        confess "Method called that requires an \$id param, but it wasn't sent in";
    }

    return $id;
}
sub list {
    my ($self) = @_;

    return $self->{vehicles} if $self->{vehicles};

    my $vehicles = $self->api('VEHICLE_LIST');

    for (@$vehicles) {
        $self->{data}{vehicles}{$_->{id}} = $_->{display_name};
    }

    return $self->{data}{vehicles};
}
sub name {
    my ($self) = @_;
    return $self->list->{$self->id};
}

# Top Level Data Structures

sub data {
    my ($self) = @_;
    $self->_online_check;
    return $self->api('VEHICLE_DATA', $self->id);
}
sub state {
    my ($self) = @_;
    $self->_online_check;
    return $self->data->{vehicle_state};
}
sub summary {
    return $_[0]->api('VEHICLE_SUMMARY', $_[0]->id);
}
sub charge_state {
    my ($self) = @_;
    $self->_online_check;
    return $self->data->{charge_state};
}

# Vehicle State

sub online {
    my $status = $_[0]->summary->{state};
    return $status eq 'online' ? 1 : 0;
}
sub odometer {
    return $_[0]->data->{vehicle_state}{odometer};
}
sub sentry_mode {
    return $_[0]->data->{vehicle_state}{sentry_mode};
}
sub santa_mode {
    return $_[0]->data->{vehicle_state}{santa_mode};
}

# Charge State

sub battery_level {
    return $_[0]->data->{charge_state}{battery_level};
}
sub charging_state {
    return $_[0]->data->{charge_state}{charging_state};
}
sub charge_amps {
    return $_[0]->data->{charge_state}{charge_amps};
}
sub charge_actual_current {
    return $_[0]->data->{charge_state}{charge_actual_current};
}
sub charge_limit_soc {
    return $_[0]->data->{charge_state}{charge_limit_soc};
}
sub charge_limit_soc_std {
    return $_[0]->data->{charge_state}{charge_limit_soc_std};
}
sub charge_limit_soc_min {
    return $_[0]->data->{charge_state}{charge_limit_soc_min};
}
sub charge_limit_soc_max {
    return $_[0]->data->{charge_state}{charge_limit_soc_max};
}
sub charge_port_color {
    return $_[0]->data->{charge_state}{charge_port_color};
}
sub charger_voltage {
    return $_[0]->data->{charge_state}{charger_voltage};
}
sub minutes_to_full_charge {
    return $_[0]->data->{charge_state}{minutes_to_full_charge};
}

# Command Related

sub wake {
    my ($self) = @_;

    if (! $self->online) {

        $self->api('WAKE_UP', $self->id);

        my $wakeup_called_at = time;
        my $wake_interval = WAKE_INTERVAL;

        while (! $self->online) {
            select(undef, undef, undef, $wake_interval);
            if ($wakeup_called_at + WAKE_TIMEOUT < time) {
                printf(
                    qq~
                        \nVehicle with ID %d couldn't be woken up within %d
                        seconds.\n\n
                    ~,
                    $self->id,
                    WAKE_TIMEOUT
                );

                $wake_interval *= WAKE_BACKOFF;
            }
        }
    }
}

# Private

sub _id {
    my ($self, $id) = @_;

    return $self->{data}{vehicle_id} if $self->{data}{vehicle_id};

    if (defined $id) {
        $self->{data}{vehicle_id} = $id;
    }
    else {
        my @vehicle_ids = keys %{$self->list};
        $self->{data}{vehicle_id} = $vehicle_ids[0];
    }

    return $self->{data}{vehicle_id} || -1;
}
sub _online_check {
    my ($self) = @_;
    if (! $self->online) {
        if ($self->auto_wake) {
            $self->wake;
        }
        printf(
            qq~
                \nVehicle with ID %d is offline. Either wake it up with a call to
                wake(), or set "auto_wake => 1" in your call to new()\n\n"
            ~,
            $self->id
        );
        exit;
    }
}

sub __placeholder{}

1;

=head1 NAME

Tesla::Vehicle - Access information and command Tesla automobiles via the API

=head1 DESCRIPTION

This distribution provides methods for accessing and updating aspects of your
Tesla vehicle. Not all attributes available through Tesla's API have methods
listed here yet, I'm only starting with the ones I use myself; I will add more
as I go.

For now, you can use the L<Tesla::API> distribution to write your own accessors
that aren't complete here. (This distribution uses that module for all Tesla
API access).

=head1 Object Management Methods

sub new(%params)

Instantiates and returns a new L<Tesla::Vehicle> object. We subclass L<Tesla::API>
so there are several things inherited.

B<Parameters>:

All parameters are sent in as a hash. See the documentation for L<Tesla::API>
for further parameters that can be sent into this method.

    id

I<Optional, Integer>: The ID of the vehicle you want to associate this object
with. Most methods require this to be set. You can send it in after
instantiation by using the C<id()> method. If you don't know what the ID is,
you can instantiate the object, and dump the returned hashref from a call to
C<list()>.

As a last case resort, we will try to figure out the ID by ourselves. If we
can't, and no ID has been set, methods that require an ID will C<croak()>.

    auto_wake

I<Optional, Bool>: If set, we will automatically wake up your vehicle on calls
that require the car to be in an online state to retrieve data (via a call to
C<wake()>). If not set and the car is asleep, we will print a warning and exit.
You can set this after instantiation by a call to C<auto_wake()>.

I<Default>: False.

    delay

I<Optional, Integer>: The number of seconds to cache data returned from Tesla's
API.

I<Default>: 2

=head2 auto_wake($bool)

Informs this software if we should automatically wake a vehicle for calls that
require it online, and the vehicle is currently offline.

Send in a true value to allow us to do this.

I<Default>: False

=head1 Vehicle Identification Methods

=head2 id($id)

Sets/gets your primary vehicle ID. If set, we will use this in all API calls
that require it.

B<Parameters>:

    $id

I<Optional, Integer>: The vehicle ID you want to use in all API calls that require
one. This can be set as a parameter in C<new()>. If you attempt an API call that
requires and ID and one isn't set, we C<croak()>.

If you only have a single Tesla vehicle registered under your account, we will
set C<my_vehicle_id()> to that ID when you instantiate the object.

You can also have this auto-populated in C<new()> by sending it in with the
C<< id => $id >> parameter.

If you don't know the ID of the vehicle you want to use, make a call to
C<list()>, and it will return a hash reference where each key is a vehice ID, and
the value is the name you've assigned your vehicle.

=head2 name

Returns the name you associated with your vehicle under your Tesla account.

B<NOTE>:L</id($id)> must have already been set, either through the C<id()>
method, or in C<new()>.

=head2 list

Returns a hash reference of your listed vehicles. The key is the vehicle ID,
and the value is the name you've assigned to that vehicle.

Example:

    {
        1234567891011 => "Dream machine",
        1234567891012 => "Steve's Model S",
    }

=head1 Command Methods

=head2 wake

Wakes up an offline Tesla vehicle.

Most Tesla API calls related to your vehicle require the vehicle to be in an
online state. If C<auto_wake()> isn't set and you attempt to make an API call
that requires the vehicle online, we will print a warning and exit.

Use this method to wake the vehicle up manually.

Default wake timeout is 30 seconds, and is set in the constant C<WAKE_TIMEOUT>.

=head1 Aggregate Data Methods

These methods aggregate all attributes of the vehicle that relate to a specific
aspect of the vehicle. Methods that allow access to individual attributes of
these larger aggregates are listed below. For example, C<charge_state()> will
return the C<battery_level> attribute, but so will C<battery_level()>. By using
the aggregate method, you'll have to fish that attribute out yourself.

=head2 data

Returns a hash reference containing all available API data that Tesla provides
for your vehicles.

C<croak()>s if you haven't specified a vehicle ID through C<new()> or C<id()>,
and we weren't able to figure one out automatically.

This data will be retained and re-used for a period of two (C<2>) seconds to
reduce API calls through the Tesla API. This timing can be overridden in the
C<new()> method by specifying the C<< refresh => $seconds >> parameter, or by
a call to the object's C<delay($seconds)> method.

I<Return>: Hash reference. Contains every attribute Tesla has available through
their API for their vehicles.

The data accessor methods listed below use this data, simply selecting out
individual parts of it.

=head2 summary

Returns an important list of information about your vehicle, and Tesla's API
access.

The most important piece of information is the vehicle's C<state>, which shows
whether the car is online or not. Other information includes C<in_service>,
C<vin>, the C<display_name> etc.

I<Return>: Hash reference.

=head2 state

Returns the C<vehicle_state> section of Tesla's vehicle data. This includes
things like whether the car is locked, whether there is media playing, the
odometer reading, whether sentry mode is enabled or not etc.

I<Return>: Hash reference.

=head2 charge_state

Returns information regarding battery and charging information of your vehicle.

I<Return>: Hash reference.

=head1 Vehicle State Attribute Methods

=head2 odometer

Returns the number of miles the vehicle is traveled since new, as a floating point
number.

=head2 sentry_mode

Returns a bool indicating whether the vehicle is in sentry mode or not.

=head2 santa_mode

Returns a bool whether the vehicle is in "Santa" mode or not.

=head1 Charge State Attribute Methods

=head2 battery_level

Returns an integer of the percent that the battery is charged to.

=head2 charging_state

Returns a string that identifies the state of the vehicle's charger. Eg.
"Disconnected", "Connected" etc.

=head2 charge_amps

Returns a float indicating how many Amps the vehicle is set to draw through the
current charger connection.

=head2 charge_actual_current

Returns a float indicating how many Amps are actually being drawn through the
charger.

=head2 charge_limit_soc

Returns an integer stating what percentage of battery level you've indicated
the charging will be cut off at.

"soc" stands for "State of Charge"

=head2 charge_limit_soc_std

Returns an integer stating Tesla's default B<charge_limit_soc> is set to.

=head2 charge_limit_soc_min

Returns an integer stating what the minimum number you can set as the Charge
Limit SOC (C<charge_limit_soc>).

=head2 charge_limit_soc_max

Returns an integer stating what the maximum number you can set as the Charge
Limit SOC (C<charge_limit_soc>).

=head2 charge_port_color

Returns a string containing the color of the vehicle's charge port (eg. "Green
Flashing" etc).

=head2 charger_voltage

Returns a float containing the actual Voltage level that the charger is connected
through.

=head2 minutes_to_full_charge

Returns an integer containing the estimated number of minutes to fully charge
the batteries, taking into consideration voltage level, Amps requested and
drawn etc.

=head1 AUTHOR

Steve Bertrand, C<< <steveb at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2022 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

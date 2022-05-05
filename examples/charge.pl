#!/usr/bin/env perl
use warnings;
use strict;
use feature 'say';
use POSIX;
use Tesla::Vehicle;

my $TEMPERATURE=23;

my $car;
my $cmd_ran;
sub cmd($@) {
  my($cmd,@args)=@_;
  $cmd_ran=1;
  my $retval=$car->$cmd(@args);
  say "$cmd: $retval";
  return $retval;
}
sub minutes_to_time($) {
  my($minutes)=@_;
  return "none" if !defined $minutes;
  return sprintf "%02d:%02d",$minutes/60,$minutes%60;
}
my $timere=qr/0*(\d+):0*(\d+)/;
sub time_to_minutes($) {
  my($time)=@_;
  return undef if !defined $time;
  my($h,$m)=($time=~/^$timere$/o) or die "$time is not d+:d+";
  die "Hours is not 0..23" if $h<0||$h>23;
  die "Minutes is not 0..59" if $m<0||$m>59;
  return $h*60+$m;
}

my $windows;
sub windows() {
  my $windows_text=join ", ",map {0=>"closed",1=>"venting",2=>"opened"}->{$_},map $car->state->{"${_}_window"},qw(fd fp rd rp);
  $windows=$windows_text=~s/^([^,]+)(?:, \1)+$/all $1/?$car->state->{"fd_window"}:undef;
  say "Windows are $windows_text.";
}
sub doors() {
  my $doors=join ", ",map $_==0?"closed":"open$_",map $car->state->{"${_}"},qw(df pf dr pr);
  $doors=~s/^([^,]+)(?:, \1)+$/all $1/;
  say "Doors are $doors." if $doors ne "all closed";
}
sub state() {
  cmd "charge_limit_soc";
  cmd "charging_state";
  say "scheduled_charging: ".minutes_to_time $car->scheduled_charging;
  say "preconditioning: ".minutes_to_time $car->preconditioning;
  windows;
  doors;
  if ($car->is_climate_on) {
    say "Car conditioning is on.";
    say "Temperature set to ".$car->temperature_setting_driver." != $TEMPERATURE." if $car->temperature_setting_driver!=$TEMPERATURE;
    say "warning: temperature_setting_passenger ".$car->temperature_setting_passenger." != ".$car->temperature_setting_driver." temperature_setting_driver"
      if $car->temperature_setting_passenger!=$car->temperature_setting_driver;
  }
  print "Both conditioning and preconditioning are set!\n" if $car->is_climate_on&&$car->preconditioning;
  say "Car is locked." if $car->locked;
  say "Sentry mode is on." if $car->sentry;
  say "Sentry mode is not available!" if !$car->state->{"sentry_mode_available"};
  print "Sentry mode != car lock.\n" if $car->sentry!=$car->locked;
}

my $battery_want;
my $time_want;
my $minutes_want_from;
my $minutes_want_to;
my $precondition;
my $reset;
my $windows_want;
my $auto_wake=1;
my $battery_direct;
my $conditioning;
my $lock;
my $sentry;
my $dump;
for my $arg (@ARGV) {
  if ($arg=~/^\d+$/&&$arg>=50&&$arg<=120) {
    if (!defined $battery_want) {
      die "battery $arg > 100" if $arg>100;
      $battery_want=$arg;
    } elsif (!defined $time_want) {
      $time_want=$arg;
    } else {
      die "Excessive battery/time: $arg";
    }
  } elsif ($arg=~/^(@?)($timere)$/o) {
    ($1?$minutes_want_from:$minutes_want_to)=time_to_minutes $2;
  } elsif ($arg eq "p") { # precondition
    $precondition=1;
  } elsif ($arg eq "r") {
    $reset=1;
  } elsif ($arg eq "s") { # sleep
    $auto_wake=0;
  } elsif ($arg=~/^b([01])$/) { # battery-on/off
    $battery_direct=$1;
  } elsif ($arg=~/^c([01])$/) { # conditioning-on/off
    $conditioning=$1;
  } elsif ($arg=~/^l([01])$/) { # lock-on/off
    $lock=$1;
  } elsif ($arg=~/^s([01])$/) { # sentry-on/off
    $sentry=$1;
  } elsif ($arg=~/^w([012])$/) { # windows-closed/vent/open
    $windows_want=$1;
  } elsif ($arg eq "dump") {
    $dump=1;
  } else {
    die "Unrecognized arg: $arg";
  }
}
die "No precondition time" if $precondition&&!defined $minutes_want_to;
$car=Tesla::Vehicle->new(auto_wake=>$auto_wake);
say strftime("%T",localtime)." ".$car->name;
cmd "battery_level";
state;
$cmd_ran=0;
use Data::Dumper;$Data::Dumper::Deepcopy=1;$Data::Dumper::Sortkeys=1;print Dumper $car->data if $dump;
my($sec,$min,$hour)=localtime;
my $minutes=$min+$hour*60;
my $battery_done=$car->battery_level>=($battery_want||$car->charge_limit_soc);
$battery_want//=50 if $battery_done;
$battery_want//=$car->charge_limit_soc;
$time_want//=$battery_want;
$minutes_want_to//=$minutes_want_from;
$sentry//=$lock;
$windows_want//=0 if $lock;
my $battery_level=$car->battery_level;
my $charging_state=$car->charging_state;
my $preconditioning=$car->preconditioning;
my $is_climate_on=$car->is_climate_on;
my $scheduled_charging=$car->scheduled_charging;
my $charge_limit_soc=$car->charge_limit_soc;
cmd "temperatures_set",$TEMPERATURE if ($car->temperature_setting_driver!=$TEMPERATURE||$car->temperature_setting_passenger!=$TEMPERATURE)
  &&($precondition||$conditioning||$reset);
if ($precondition) {
  cmd "preconditioning_set",$minutes_want_to if ($preconditioning//-1)!=$minutes_want_to;
  $preconditioning=$minutes_want_to;
} elsif ($reset||$is_climate_on||defined $minutes_want_to) {
  cmd "preconditioning_set",undef if defined $preconditioning;
  $preconditioning=undef;
}
my $battery_minutes=ceil(($time_want-$battery_level)*4.1) if $time_want; # 4.2 is too much
if ($battery_done||$battery_direct||(!defined $minutes_want_to&&($reset||$charging_state eq "Charging"))||($battery_minutes//0)<=0) {
  cmd "scheduled_charging_set",undef if defined $scheduled_charging;
} elsif (defined $minutes_want_to) {
  my $when=$minutes_want_from;
  if (!$when) {
    $when=($minutes_want_to-$battery_minutes)%(24*60);
    my $tolerance=5;
    if (($when-$minutes-$tolerance)%(24*60)>=(24*60-3*60)) {
      $battery_direct=1 if !defined $battery_direct;
      cmd "scheduled_charging_set",undef if defined $scheduled_charging;
      $when=undef;
    }
  }
  if (defined $when) {
    cmd "scheduled_charging_set",$when if ($scheduled_charging//-1)!=$when;
  }
}
print "warning: Car may get charged up to ".($battery_want+3)."%!\n" if $battery_want&&$battery_want>87&&$battery_want<=90;
cmd "charge_limit_set",$battery_want//50 if $battery_want&&$battery_want!=$charge_limit_soc; # charge_limit_set only after scheduled_charging_set!
$windows_want=0 if !defined $windows_want&&($conditioning||(defined $preconditioning&&defined $minutes_want_to&&($minutes_want_to-$minutes)%(24*60)<3*60));
if (($windows//-3)!=($windows_want//$windows//-3)) {
  if (($windows_want//-2)==2) {
    print "There is no way to open windows!\n";
  } else {
    cmd "windows_set",$windows_want;
  }
}
cmd "climate_".($conditioning?"on":"off") if defined $conditioning||($reset&&$is_climate_on);
cmd "charge_" .($battery_direct?"on":"off") if defined $battery_direct;
cmd "doors_".($lock?"lock":"unlock") if defined $lock;
cmd "sentry_".($sentry?"on":"off") if defined $sentry;
state if $cmd_ran;

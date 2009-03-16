#!perl

use Test::More tests => 1;

package foo;
use strict;
no warnings;

use Object::Event;
$Object::Event::ENABLE_METHODS_DEFAULT = $ENV{OE_METHODS_ENABLE};

our @ISA = qw/Object::Event/;

package main;
use strict;
no warnings;

my $f = foo->new;

$f->reg_cb (
   test123 => sub {
      my ($f) = @_;
      $f->{name} = $f->event_name;
   }
);

$f->event ('test123');
is ($f->{name}, 'test123', 'event_name method returns event name');

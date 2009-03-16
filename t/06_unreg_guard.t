#!perl

use Test::More tests => 2;

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

my $called = 0;

my $id = $f->reg_cb (test => sub { $called += $_[1] });

$f->event (test => 10);

is ($called, 10, "first test called once");

$f->unreg_cb ($id);

$f->event (test => 20);

is ($called, 10, "second test still called once");

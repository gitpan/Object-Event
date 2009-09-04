#!perl

use Test::More tests => 7;

package foo;
use common::sense;

use base qw/Object::Event/;

sub test {
   my ($f, $a) = @_;
   $f->{a} += $a;
}

package main;
use common::sense;

my $f  = foo->new (enable_methods => 1);
my $f2 = foo->new (enable_methods => 1);

$f->reg_cb  (test => sub { $_[0]->{a} += 3 });
$f2->reg_cb (test => sub { $_[0]->{a} += 9 });

$f->test (10);
is ($f->{a}, 13, 'first object got event');
is ($f2->{a}, undef, 'second object got no event');

$f2->event (test => 20);
is ($f->{a}, 13, 'first object got no event');
is ($f2->{a}, 29, 'second object got event');

$f->reg_cb (foobar => sub { $_[0]->{b} = 10 });
$f->foobar;
$f2->foobar;
is ($f->{b}, 10, 'first object got method with event callback');
is ($f2->{b}, undef, 'second object doesn\'t have method with event callback');

ok ($f->event ('test'), 'event returns true for methods');

#!perl

use Test::More tests => 4;

package foo;
use strict;
no warnings;

use base qw/Object::Event::Methods/;

sub before_test {
   my ($self, $a, $b) = @_;
   $self->{bef} = $a * $b;
}

sub test {
   my ($self, $a, $b) = @_;
   $self->{res} = $a + $b;
}

sub reset { (shift)->{res} = 0 }

package foo2;
use strict;
no warnings;

use base qw/foo/;

package main;
use strict;
no warnings;

my $f = foo->new;

$f->event (test => 30, 40);

is ($f->{res}, 70, 'calling event() on unregistered event works');
is ($f->{bef}, 30 * 40, 'before_method works');

$f->{bef} = 0;
$f->reg_cb (before_test => sub { (shift)->{bef} = 0 });
$f->event (test => 30, 40);

is ($f->{bef}, 0, 'registering on before_test works');

$f->reg_cb (test2 => sub {
   my ($self, $a) = @_;
   $self->{res2} = $a;
});

$f->test2 (10);

is ($f->{res2}, 10, 'using method syntax for event works');

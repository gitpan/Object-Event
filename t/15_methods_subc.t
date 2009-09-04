#!perl

use Test::More tests => 5;

package first;
use common::sense;

use base qw/Object::Event/;

__PACKAGE__->hand_event_methods_down (qw/test2 test3/);

sub test2 {
   my ($self, $a) = @_;
   push @{$self->{chain}}, 'first::test2';
}

sub test3 {
   my ($self) = @_;
   push @{$self->{chain}}, 'first::test3';
}

package pre;
use common::sense;

use base qw/first/;

__PACKAGE__->inherit_event_methods_from (qw/first/);
__PACKAGE__->hand_event_methods_down_from (qw/first/);

sub test2 {
   my ($self, $a) = @_;
   push @{$self->{chain}}, 'pre::test2';
}

package foo;
use common::sense;

use base qw/Object::Event/;

sub test {
   my ($self, $a, $b) = @_;
   push @{$self->{chain}}, 'foo::test';
}

package bar;
use common::sense;

use base qw/foo pre/;

__PACKAGE__->inherit_event_methods_from (qw/foo pre/);

sub test {
   my ($self, $a, $b) = @_;
   push @{$self->{chain}}, 'bar::test';
}

sub test2 {
   my ($self, $a) = @_;
   push @{$self->{chain}}, 'bar::test2';
}

package main;
use common::sense;

my $f = foo->new (enable_methods => 1);
my $b = bar->new (enable_methods => 1);

$b->test2 (100);
is ((join ",", @{delete $b->{chain}}), 'first::test2,pre::test2,bar::test2', 'bar first class works.');

$b->test3 (200);
is ((join ",", @{delete $b->{chain}}), 'first::test3', 'bar first undecl class works.');

$f->reg_cb (before_test => sub {
   my ($f) = @_;
   push @{$f->{chain}}, 'f::before_test';
});

$b->reg_cb (before_test => sub {
   my ($f) = @_;
   push @{$f->{chain}}, 'b::before_test';
});

$b->reg_cb (test2 => sub {
   my ($f) = @_;
   push @{$f->{chain}}, 'b::test2';
});

$f->test (10, 20);
is ((join ",", @{delete $f->{chain}}), 'f::before_test,foo::test', 'foo class works.');
$b->test (10, 20);
is ((join ",", @{delete $b->{chain}}), 'b::before_test,bar::test', 'bar class works.');
$b->test2 (100);
is ((join ",", @{delete $b->{chain}}), 'first::test2,pre::test2,bar::test2,b::test2', 'bar class works.');

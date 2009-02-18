package Object::Event::Methods;
use strict;
no warnings;

use base qw/Object::Event/;

=head1 NAME

Object::Event::Methods - Syntactic sugar for L<Object::Event>

=head1 SYNOPSIS

   package test;

   use base qw/Object::Event::Methods/;

   sub test_ev {
      my ($self, $a, $b) = @_;
      # ...
   }

   package main;

   my $t = test->new;

   $t->test_ev (1, 2); # will of course still call test_ev
                       # like before

   # this call replaces the test_ev method in the test
   # package with something that invokes the 'test_ev' event,
   # and append a new callback to the call chain.
   $t->reg_cb (test_ev => sub {
      my ($self, $a, $b) = @_;
      # ...
   });

   # and then this will first call the test_ev method in the test
   # package and after that the callback defined above.
   $t->test_ev (1, 2);

   # and that is effectively the same as this:
   $t->event (test_ev => 1, 2);

=head2 DESCRIPTION

This is a syntactic sugar module to L<Object::Event> which:

=over 4

=item 1.

Makes it easier to define default handlers for methods.
Instead of doing this in a package:

   package test;

   use base qw/Object::Event/;

   sub init {
      my ($self) = @_;
      $self->reg_cb (
         test_event => \&test_event,
         after_test_event => \&after_test_event
      );
   }

   sub test_event {
      my ($self, @args) = @_;
      # ...
   }

   sub after_test_event {
      my ($self, @args) = @_;
      # ...
   }

You can just do this:

   package test;

   use base qw/Object::Event::Methods/;

   sub test_event {
      my ($self, @args) = @_;
      # ...
   }
   
   sub after_test_event {
      my ($self, @args) = @_;
      # ...
   }

=item 2.

You can invoke events, if they have either been callbacks
for it registered, or a method defined for, via Perl's usual
method call semantics:

Instead of this:

   $obj->event (test => 1, 2, 3);

You can just use this:

   $obj->test (1, 2, 3);

=back

=head2 METHODS

=over 4

=item B<reg_cb ($eventname1, $cb1, [...])>

This method has the same arguments and return values
as C<reg_cb> of L<Object::Event> has, with the exception that this
method will (re)place methods with C<$eventname> in the package of
C<$self>.

If a method was already defined it will be prepended to the arguments
of C<reg_cb> as event callback.

=cut

sub reg_cb {
   my ($self, @regs) = @_;

   no strict 'refs';

   my @prep_reg;

   my %evs = @regs;

   for my $k (keys %evs) {
      my $evname = $k;

      $evname =~ s/^(?:before_|ext_before_|after_|ext_after_)//;
      my $methname = ref ($self) . '::' . $evname;

      next if $self->{__bsev_events}->{$evname};

      if (*{$methname}{CODE}) {
         unshift @prep_reg, ($evname, *{$methname}{CODE});
      }

      *{$methname} = sub { (shift)->event ($evname, @_) };
   }

   $self->SUPER::reg_cb (@prep_reg)
      if @prep_reg;
   $self->SUPER::reg_cb (@regs)
}

sub _event {
   my ($self, $ev, @args) = @_;

   no strict 'refs';

   if (defined $self->{__bsev_events}->{$ev}) {
      $self->SUPER::_event ($ev, @args);

   } elsif (*{ref ($self) . '::' . $ev}{CODE}) {
      (*{ref ($self) . '::' . $ev}{CODE})->($self, @args);
   }
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;


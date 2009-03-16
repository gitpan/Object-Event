package Object::Event;
use strict;
no warnings;
use Carp qw/croak/;
use AnyEvent::Util qw/guard/;

our $ENABLE_METHODS_DEFAULT = 0;

=head1 NAME

Object::Event - A class that provides an event callback interface

=head1 VERSION

Version 1.0

=cut

our $VERSION = '1.0';

=head1 SYNOPSIS

   package foo;
   use Object::Event;

   our @ISA = qw/Object::Event/;

   package main;
   my $o = foo->new;

   my $regguard = $o->reg_cb (foo => sub {
      print "I got an event, with these args: $_[1], $_[2], $_[3]\n";
   });

   $o->event (foo => 1, 2, 3);

   $o->unreg_cb ($regguard);
   # or just:
   $regguard = undef;


=head1 DESCRIPTION

This module was mainly written for L<Net::XMPP2>, L<Net::IRC3>,
L<AnyEvent::HTTPD> and L<BS> to provide a consistent API for registering and
emitting events.  Even though I originally wrote it for those modules I released
it separately in case anyone may find this module useful.

For more comprehensive event handling see also L<Glib> and L<POE>.

This class provides a simple way to extend a class, by inheriting from
this class, with an event callback interface.

You will be able to register callbacks for events, identified by their names (a
string) and call them later by invoking the C<event> method with the event name
and some arguments. For each invoked event a event object, derived from
L<Object::Event::Event> will be generated, which you can use to influence the
way the event callbacks are called.

=head1 PERFORMANCE

In the first version as presented here no special performance optimisations
have been applied. So take care that it is fast enough for your purposes.  At
least for modules like L<AnyEvent::XMPP> the overhead is probably not
noticeable, as other technologies like XML already waste a lot more CPU cycles.
Also I/O usually introduces _much_ larger/longer overheads than this simple
event interface.

=head1 FUNCTIONS

=over 4

=item Object::Event::register_priority_alias ($alias, $priority)

This package function will add a global priority alias.
If C<$priority> is undef the alias will be removed.

There are 4 predefined aliases:

   before     =>  1000
   ext_before =>   500
   ext_after  =>  -500
   after      => -1000

See also the C<reg_cb> method for more information about aliases.

=cut

our %PRIO_MAP = (
   before     =>  1000,
   ext_before =>   500,
   ext_after  =>  -500,
   after      => -1000
);

sub register_priority_alias {
   my ($alias, $prio) = @_;
   $PRIO_MAP{$alias} = $prio;

   unless (defined $PRIO_MAP{$alias}) {
      delete $PRIO_MAP{$alias} 
   }
}

=back

=head1 METHODS

=over 4

=item Object::Event->new (%args)

=item Your::Subclass::Of::Object::Event->new (%args)

This is the constructor for L<Object::Event>,
it will create a blessed hash reference initialized with C<%args>.

There are these special keys for C<%args>:

=over 4

=item enable_methods => $bool

If C<$bool> is a true value this object will overwrite the methods
in it's package with event emitting methods, and add the method's code
as priority 0 event callback. The replacement will happen whenever
an event callback is registered with C<reg_cb>.

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = {
      enable_methods => $ENABLE_METHODS_DEFAULT,
      @_,
   };
   bless $self, $class;

   if ($self->{enable_methods}) {
      no strict 'refs';
      for my $ev (keys %{"$class\::__OE_INHERITED_METHODS"}) {
         $self->_check_method ($ev)
      }
   }

   return $self
}

=item $obj->set_exception_cb ($cb->($exception, $eventname))

This method installs a callback that will be called when some other
event callback threw an exception. The first argument to C<$cb>
will be the exception and the second the event name.

=cut

sub set_exception_cb {
   my ($self, $cb) = @_;
   $self->{__oe_exception_cb} = $cb;
}

=item $guard = $obj->reg_cb ($eventname => $cb->($obj, @args), ...)

=item $guard = $obj->reg_cb ($eventname => $prio, $cb->($obj, @args), ...)

This method registers a callback C<$cb1> for the event with the
name C<$eventname1>. You can also pass multiple of these eventname => callback
pairs.

The return value will be an ID that represents the set of callbacks you have installed.
Call C<unreg_cb> with that ID to remove those callbacks again.

The first argument for callbacks registered with the C<reg_cb> function will
always be the master object C<$obj>. If you want to have the event object
C<$ev> (which represents an event which was sent by the C<event> method) as
first argument use the C<reg_event_cb> method.

The callbacks will be called in an array context. If a callback doesn't want to
return any value it should return an empty list. All results from the callbacks
will be appended and returned by the C<event> method.

The order of the callbacks in the call chain of the event depends on their
priority. If you didn't specify any priority (see below) they get the default
priority of 0, and are appended to the other priority 0 callbacks.
The higher the priority number, the earlier the callbacks gets called in the chain.

If C<$eventname1> starts with C<'before_'> the callback gets a priority
of 1000, and if it starts with C<'ext_before_'> it gets the priority 500.
C<'after_'> is mapped to the priority -1000 and C<'ext_after_'> to -500.

If you want more fine grained control you can pass an array reference
instead of the event name:

   ($eventname1, $prio) = ('test_abc', 100);
   $obj->reg_cb ([$eventname1, $prio] => sub {
      ...
   });

=cut


sub _register_event_struct {
   my ($self, $event, $prio, $callback) = @_;

   my $reg = ($self->{__oe_events} ||= {});
   my $idx = 0;
   $reg->{$event} ||= [];
   my $evlist = $reg->{$event};

   for my $ev (@$evlist) {
      last if $ev->[1] < $prio;
      $idx++;
   }

   splice @$evlist, $idx, 0, [$event, $prio, $callback]
}

sub reg_cb {
   my ($self, @args) = @_;

   my @cbs;
   while (@args) {
      my ($ev, $sec) = (shift @args, shift @args);

      my ($prio, $cb) = (0, undef);

      if (ref $sec) {
         for my $prefix (keys %PRIO_MAP) {
            if ($ev =~ s/^(\Q$prefix\E)_//) {
               $prio = $PRIO_MAP{$prefix};
               last;
            }
         }

         $cb = $sec;

      } else {
         $prio = $sec;
         $cb   = shift @args;
      }

      $self->_check_method ($ev) if $self->{enable_methods};
      $self->_register_event_struct ($ev, $prio, $cb);
      push @cbs, $cb;
   }

   defined wantarray
      ? \(my $g = guard { $self->unreg_cb ($_) for @cbs })
      : ()
}

=item $obj->unreg_cb ($cb)

Removes the callback C<$cb> from the set of registered callbacks.

=cut

sub unreg_cb {
   my ($self, $cb) = @_;

   if (ref ($cb) eq 'REF') {
      # we've got a guard object
      $$cb = undef;
      return;
   }

   my $evs = $self->{__oe_events};

   for my $reg (values %$evs) {
      @$reg = grep { $_->[2] ne $cb } @$reg;
   }
}

=item $obj->event ($eventname, @args)

Emits the event C<$eventname> and passes the arguments C<@args> to the
callbacks. The return value is an object which is derived from
L<Object::Event::Event>, and acts as handle to this event invocation.

See also the alternate form to call C<event> below.

See also the specification of the before and after events in C<reg_cb> above.

NOTE: Whenever an event is emitted the current set of callbacks registered
to that event will be used. So, if you register another event callback for the
same event that is executed at the moment, it will be called the B<next> time 
when the event is emitted. Example:

   $obj->reg_cb (event_test => sub {
      my ($ev) = @_;

      print "Test1\n";
      $ev->unreg_me;

      $obj->reg_cb (event_test => sub {
         my ($ev) = @_;
         print "Test2\n";
         $ev->unreg_me;
      });
   });

   $obj->event ('event_test'); # prints "Test1"
   $obj->event ('event_test'); # prints "Test2"

=cut

sub _check_method {
   my ($self, $ev) = @_;
   my $pkg = ref ($self);

   no strict 'refs';

   my $add = 0;
   my $repl = 0;
   my $meth;

   if ($meth = ${"$pkg\::__OE_METHODS"}{$ev}) {
      unless ($self->{__oe_added_methods}->{$ev}) {
         $add = $self->{__oe_added_methods}->{$ev} = 1;
      }

   } else {
      $meth = ${"$pkg\::__OE_METHODS"}{$ev} = *{"$pkg\::$ev"}{CODE} || 1;
      $add = $self->{__oe_added_methods}->{$ev} = 1;
      $repl = 1;
   }

   if ($add) {
      if (my $super_meth = ${"$pkg\::__OE_INHERITED_METHODS"}{$ev}) {
         $self->reg_cb ($ev, $_) for @$super_meth;
      }

      $self->reg_cb ($ev, $meth) if ref $meth;
   }

   if ($repl) {
      *{"$pkg\::$ev"} = sub {
         my ($self, @arg) = @_;
         my @cbs = @{$self->{__oe_events}->{$ev}
                     || ${"$pkg\::__OE_INHERITED_METHODS"}{$ev}};
         local $self->{__oe_cbs} = [\@cbs, \@arg, $ev];
         eval {
            $cbs[0]->[2]->($self, @arg), shift @cbs while @cbs
         };
         if ($@) {
            if (not ($self->{__oe_exception_rec}) && $self->{__oe_exception_cb}) {
               local $self->{__oe_exception_rec} = [$ev, $self, @arg];
               $self->{__oe_exception_cb}->($@, $ev);

            } elsif ($self->{__oe_exception_rec}) {
               warn "recursion through exception callback (@{$self->{__oe_exception_rec}}) => ($ev, $self, @arg): $@\n";
            } else {
               warn "unhandled callback exception on event ($ev, $self, @arg): $@\n";
            }
         }
         ()
      };
   }
}

sub event {
   my ($self, $ev, @arg) = @_;

   $self->_check_method ($ev) if $self->{enable_methods};

   my @cbs;

   if (ref ($ev) eq 'ARRAY') {
      @cbs = @$ev;

   } else {
      my $evs = $self->{__oe_events}->{$ev} || [];
      @cbs = @$evs;
   }

   ######################
   # Legacy code start
   ######################
   if ($self->{__oe_forwards}) {
      # we are inserting a forward callback into the callchain.
      # first search the start of the 0 priorities...
      my $idx = 0;
      for my $ev (@cbs) {
         last if $ev->[1] <= 0;
         $idx++;
      }

      # then splice in the stuff
      splice @cbs, $idx, 0, [$ev, 0, sub {
         for my $fw (keys %{$self->{__oe_forwards}}) {
            my $f = $self->{__oe_forwards}->{$fw};
            local $f->[0]->{__oe_forward_stop} = 0;
            eval {
               $f->[1]->($self, $f->[0], $ev, @arg);
            };
            if ($@) {
               if ($self->{__oe_exception_cb}) {
                  $self->{__oe_exception_cb}->($@, $ev);
               } else {
                  warn "unhandled callback exception on forward event ($ev, $self, $f->[0], @arg): $@\n";
               }
            } elsif ($f->[0]->{__oe_forward_stop}) {
               $self->stop_event;
            }
         }
      }]
   }
   ######################
   # Legacy code end
   ######################

   local $self->{__oe_cbs} = [\@cbs, \@arg, $ev];
   eval {
      $cbs[0]->[2]->($self, @arg), shift @cbs while @cbs;
   };
   if ($@) {
      if (not ($self->{__oe_exception_rec}) && $self->{__oe_exception_cb}) {
         local $self->{__oe_exception_rec} = [$ev, $self, @arg];
         $self->{__oe_exception_cb}->($@, $ev);

      } elsif ($self->{__oe_exception_rec}) {
         warn "recursion through exception callback (@{$self->{__oe_exception_rec}}) => ($ev, $self, @arg): $@\n";
      } else {
         warn "unhandled callback exception on event ($ev, $self, @arg): $@\n";
      }
   }

   ()
}

=item $obj->event_name

Returns the name of the currently executed event.

=cut

sub event_name {
   my ($self) = @_;
   return unless $self->{__oe_cbs};
   $self->{__oe_cbs}->[2]
}

=item $obj->unreg_me

Unregisters the currently executed callback.

=cut

sub unreg_me {
   my ($self) = @_;
   return unless $self->{__oe_cbs} && @{$self->{__oe_cbs}->[0]};
   $self->unreg_cb ($self->{__oe_cbs}->[0]->[0]->[2])
}

=item $continue_cb = $obj->stop_event

This method stops the execution of callbacks of the current
event, and returns (in non-void context) a callback that will
let you continue the execution.

=cut

sub stop_event {
   my ($self) = @_;

   return unless $self->{__oe_cbs} && @{$self->{__oe_cbs}->[0]};

   my $r;

   if (defined wantarray) {
      my @ev = ([@{$self->{__oe_cbs}->[0]}], @{$self->{__oe_cbs}->[1]});
      shift @{$ev[0]}; # shift away current cb
      $r = sub { $self->event (@ev) }
   }

   # XXX: Old legacy code for forwards!
   $self->{__oe_forward_stop} = 1;

   @{$self->{__oe_cbs}->[0]} = ();
   
   $r
}

=item $obj->add_forward ($obj, $cb)

B<DEPRECATED: Don't use it!> Just for backward compatibility for L<AnyEvent::XMPP>
version 0.4.

=cut

sub add_forward {
   my ($self, $obj, $cb) = @_;
   $self->{__oe_forwards}->{$obj} = [$obj, $cb];
}

=item $obj->remove_forward ($obj)

B<DEPRECATED: Don't use it!> Just for backward compatibility for L<AnyEvent::XMPP>
version 0.4.

=cut

sub remove_forward {
   my ($self, $obj) = @_;
   delete $self->{__oe_forwards}->{$obj};
   if (scalar (keys %{$self->{__oe_forwards}}) <= 0) {
      delete $self->{__oe_forwards};
   }
}

sub _event {
   my $self = shift;
   $self->event (@_)
}

=item $obj->remove_all_callbacks ()

This method removes all registered event callbacks from this object.

=cut

sub remove_all_callbacks {
   my ($self) = @_;
   $self->{__oe_events} = {};
   delete $self->{__oe_exception_cb};
}

=item $obj->events_as_string_dump ()

This method returns a string dump of all registered event callbacks.
This method is only for debugging purposes.

=cut

sub events_as_string_dump {
   my ($self) = @_;
   my $str = '';
   for my $ev (keys %{$self->{__oe_events}}) {
      my $evr = $self->{__oe_events}->{$ev};
      $str .= "$ev: " . join (',', map { "(@$_)" } @$evr) . "\n";
   }
   $str
}

=item __PACKAGE__->hand_event_methods_down ($eventname, ...);

B<NOTE:> This is only of interest to you if you enabled C<enable_methods>.

If you want to build up a class hierarchy of L<Object::Event>
classes which pass down the defined event methods for events, you need
to call this package method. It will pack up all given C<$eventname>s
for subclasses, which can 'inherit' these with the C<inherit_event_methods_from>
package method (see below).

Because the event methods of a package are global with regard to the
object instances they need to be added to, you need to register them
for the subclasses.

B<NOTE>: If you want to hand down event methods from super-classes make sure
you call C<inherit_event_methods_from> B<BEFORE> C<hand_event_methods_down>!

B<NOTE>: For an example about how to use this see the test case C<t/15_methods_subc.t>.

=cut

sub hand_event_methods_down {
   my ($pkg, @evs) = @_;

   no strict 'refs';

   for my $ev (@evs) {
      for my $meth (@{${"$pkg\::__OE_INHERITED_METHODS"}{$ev} || []}) {
         push @{${"$pkg\::__OE_HANDED_METHODS"}{$ev}}, $meth;
      }

      my $meth = ${"$pkg\::__OE_METHODS"}{$ev};
      $meth = *{"$pkg\::$ev"}{CODE} unless $meth;
      push @{${"$pkg\::__OE_HANDED_METHODS"}{$ev}}, $meth if ref $meth;
   }
}

=item __PACKAGE__->hand_event_methods_down_from ($package, ...);

B<NOTE:> This is only of interest to you if you enabled C<enable_methods>.

This is a sugar method for C<hand_event_methods_down>, which will
hand down all event methods of the packages in the argument list,
along with the in the current package overridden event method.

B<NOTE>: For an example about how to use this see the test case C<t/15_methods_subc.t>.

=cut

sub hand_event_methods_down_from {
   my ($pkg, @pkgs) = @_;

   no strict 'refs';
   $pkg->hand_event_methods_down (keys %{"$pkg\::__OE_INHERITED_METHODS"});
}

=item __PACKAGE__->inherit_event_methods_from ('SUPER_PKG1', 'OTHER_SUPER', ...)

B<NOTE:> This is only of interest to you if you enabled C<enable_methods>.

Call this package method if you want to inherit event methods from super
packages, which you have to give as argument list.

B<NOTE>: For an example about how to use this see the test case C<t/15_methods_subc.t>.

=cut

sub inherit_event_methods_from {
   my ($pkg, @suppkgs) = @_;

   no strict 'refs';

   for my $suppkg (@suppkgs) {
      for my $ev (keys %{"$suppkg\::__OE_HANDED_METHODS"}) {
         push @{${"$pkg\::__OE_INHERITED_METHODS"}{$ev}},
            @{${"$suppkg\::__OE_HANDED_METHODS"}{$ev}};
      }
   }
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Object::Event

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Object-Event>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Object-Event>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Object-Event>

=item * Search CPAN

L<http://search.cpan.org/dist/Object-Event>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

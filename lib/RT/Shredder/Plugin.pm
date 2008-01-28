# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2007 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/copyleft/gpl.html.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
package RT::Shredder::Plugin;

use strict;
use warnings FATAL => 'all';
use File::Spec ();

=head1 name

RT::Shredder::Plugin - interface to access shredder plugins

=head1 SYNOPSIS

  use RT::Shredder::Plugin;

  # get list of the plugins
  my %plugins = RT::Shredder::Plugin->list;

  # load plugin by name
  my $plugin = RT::Shredder::Plugin->new;
  my( $status, $msg ) = $plugin->load_by_name( 'Tickets' );
  unless( $status ) {
      print STDERR "Couldn't load plugin 'Tickets': $msg\n";
      exit(1);
  }

  # load plugin by preformatted string
  my $plugin = RT::Shredder::Plugin->new;
  my( $status, $msg ) = $plugin->load_by_string( 'Tickets=status,deleted' );
  unless( $status ) {
      print STDERR "Couldn't load plugin: $msg\n";
      exit(1);
  }

=head1 METHODS

=head2 new

Object constructor, returns new object. Takes optional hash
as arguments, it's not required and this class doesn't use it,
but plugins could define some arguments and can handle them
after your've load it.

=cut

sub new
{
    my $proto = shift;
    my $self = bless( {}, ref $proto || $proto );
    $self->_init( @_ );
    return $self;
}

sub _init
{
    my $self = shift;
    my %args = ( @_ );
    $self->{'opt'} = \%args;
}

=head2 List

Returns hash with names of the available plugins as keys and path to
library files as values. Method has no arguments. Can be used as class
method too.

Takes optional argument C<type> and leaves in the result hash only
plugins of that type.

=cut

sub List
{
    my $self = shift;
    my $type = shift;

    my @files;
    foreach my $root( @INC ) {
        my $mask = File::Spec->catfile( $root, qw(RT Shredder Plugin *.pm) );
        push @files, glob $mask;
    }

    my %res = map { $_ =~ m/([^\\\/]+)\.pm$/; $1 => $_ } reverse @files;

    return %res unless $type;

    delete $res{'Base'};
    foreach my $name( keys %res ) {
        my $class = join '::', qw(RT Shredder Plugin), $name;
        unless( eval "require $class" ) {
            delete $res{ $name };
            next;
        }
        next if lc $class->type eq lc $type;
        delete $res{ $name };
    }

    return %res;
}

=head2 load_by_name

Takes name of the plugin as first argument, loads plugin,
creates new plugin object and reblesses self into plugin
if all steps were successfuly finished, then you don't need to
create new object for the plugin.

Other arguments are sent to the constructor of the plugin
(method new.)

Returns C<$status> and C<$message>. On errors status
is C<false> value.

=cut

sub load_by_name
{
    my $self = shift;
    my $name = shift or return (0, "name not specified");

    local $@;
    my $plugin = "RT::Shredder::Plugin::$name";
    eval "require $plugin" or return( 0, $@ );
    return( 0, "Plugin '$plugin' has no method new") unless $plugin->can('new');

    my $obj = eval { $plugin->new( @_ ) };
    return( 0, $@ ) if $@;
    return( 0, 'constructor returned empty object' ) unless $obj;

    $self->rebless( $obj );
    return( 1, "successfuly load plugin" );
}

=head2 LoadByString

Takes formatted string as first argument and which is used to
load plugin. The format of the string is

  <plugin name>[=<arg>,<val>[;<arg>,<val>]...]

exactly like in the L<rt-shredder> script. All other
arguments are sent to the plugins constructor.

Method does the same things as C<load_by_name>, but also
checks if the plugin supports arguments and values are correct,
so you can C<Run> specified plugin immediatly.

Returns list with C<$status> and C<$message>. On errors status
is C<false>.

=cut

sub loadByString
{
    my $self = shift;
    my ($plugin, $args) = split /=/, ( shift || '' ), 2;

    my ($status, $msg) = $self->load_by_name( $plugin, @_ );
    return( $status, $msg ) unless $status;

    my %args;
    foreach( split /\s*;\s*/, ( $args || '' ) ) {
        my( $k,$v ) = split /\s*,\s*/, ( $_ || '' ), 2;
        unless( $args{$k} ) {
            $args{$k} = $v;
            next;
        }

        $args{$k} = [ $args{$k} ] unless UNIVERSAL::isa( $args{ $k }, 'ARRAY');
        push @{ $args{$k} }, $v;
    }

    ($status, $msg) = $self->has_support_for_args( keys %args );
    return( $status, $msg ) unless $status;

    ($status, $msg) = $self->test_args( %args );
    return( $status, $msg ) unless $status;

    return( 1, "successfuly load plugin" );
}

=head2 Rebless

Instance method that takes one object as argument and rebless
the current object into into class of the argument and copy data
of the former. Returns nothing.

Method is used by C<Load*> methods to automaticaly rebless
C<RT::Shredder::Plugin> object into class of the loaded
plugin.

=cut

sub Rebless
{
    my( $self, $obj ) = @_;
    bless( $self, ref $obj );
    %{$self} = %{$obj};
    return;
}

1;

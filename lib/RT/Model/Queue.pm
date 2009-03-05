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

=head1 NAME

RT::Model::Queue - an RT queue object

=head1 METHODS

=cut

use warnings;
use strict;

package RT::Model::Queue;

use RT::Model::GroupCollection;
use RT::Model::ACECollection;
use RT::Interface::Email;
use RT::StatusSchema;

use base qw/RT::Record/;

sub table {'Queues'}

use Jifty::DBI::Schema;
use Jifty::DBI::Record schema {

    column name => max_length is 200, type is 'varchar(200)', is mandatory, is distinct;
    column
        description => max_length is 255,
        type is 'varchar(255)', default is '';
    column
        correspond_address => max_length is 120,
        type is 'varchar(120)';
    column
        comment_address => max_length is 120,
        type is 'varchar(120)';
    column
        status_schema => max_length is 120,
        type is 'varchar(120)',
        default is 'default',
        is mandatory;
    column initial_priority => max_length is 11, type is 'int',      default is '0';
    column final_priority   => max_length is 11, type is 'int',      default is '0';
    column default_due_in   => max_length is 11, type is 'int',      default is '0';
    column disabled         => max_length is 6, type is 'smallint', is mandatory, default is '0';
};
use Jifty::Plugin::ActorMetadata::Mixin::Model::ActorMetadata 
no_user_refs => 1,
map => {
    created_by => 'creator',
    created_on => 'created',
    updated_by => 'last_updated_by',
    updated_on => 'last_updated'
};

our @DEFAULT_ACTIVE_STATUS   = qw(new open stalled);
our @DEFAULT_INACTIVE_STATUS = qw(resolved rejected deleted);

# _('new'); # For the string extractor to get a string to localize
# _('open'); # For the string extractor to get a string to localize
# _('stalled'); # For the string extractor to get a string to localize
# _('resolved'); # For the string extractor to get a string to localize
# _('rejected'); # For the string extractor to get a string to localize
# _('deleted'); # For the string extractor to get a string to localize

our $RIGHTS = {
    SeeQueue            => 'Can this principal see this queue',         # loc_pair
    AdminQueue          => 'Create, delete and modify queues',          # loc_pair
    ShowACL             => 'Display Access Control List',               # loc_pair
    ModifyACL           => 'Modify Access Control List',                # loc_pair
    ModifyQueueWatchers => 'Modify the queue watchers',                 # loc_pair
    AssignCustomFields  => 'Assign and remove custom fields',           # loc_pair
    ModifyTemplate      => 'Modify Scrip templates for this queue',     # loc_pair
    ShowTemplate        => 'Display Scrip templates for this queue',    # loc_pair

    ModifyScrips => 'Modify Scrips for this queue',                     # loc_pair
    ShowScrips   => 'Display Scrips for this queue',                    # loc_pair

    ShowTicket         => 'See ticket summaries',                                       # loc_pair
    ShowTicketcomments => 'See ticket private commentary',                              # loc_pair
    ShowOutgoingEmail  => 'See exact outgoing email messages and their recipeients',    # loc_pair

    Watch           => 'Sign up as a ticket Requestor or ticket or queue Cc',           # loc_pair
    WatchAsAdminCc  => 'Sign up as a ticket or queue AdminCc',                          # loc_pair
    CreateTicket    => 'Create tickets in this queue',                                  # loc_pair
    ReplyToTicket   => 'Reply to tickets',                                              # loc_pair
    CommentOnTicket => 'comment on tickets',                                            # loc_pair
    OwnTicket       => 'Own tickets',                                                   # loc_pair
    ModifyTicket    => 'Modify tickets',                                                # loc_pair
    DeleteTicket    => 'Delete tickets',                                                # loc_pair
    TakeTicket      => 'Take tickets',                                                  # loc_pair
    StealTicket     => 'Steal tickets',                                                 # loc_pair

    ForwardMessage => 'Forward messages to third person(s)',                            # loc_pair

};

# Tell RT::Model::ACE that this sort of object can get acls granted
$RT::Model::ACE::OBJECT_TYPES{'RT::Model::Queue'} = 1;

# TODO: This should be refactored out into an RT::Model::ACECollectionedobject or something
# stuff the rights into a hash of rights that can exist.

foreach my $right ( keys %{$RIGHTS} ) {
    $RT::Model::ACE::LOWERCASERIGHTNAMES{ lc $right } = $right;
}

sub add_link {
    my $self = shift;
    my %args = (
        target => '',
        base   => '',
        type   => '',
        silent => undef,
        @_
    );

    unless ( $self->current_user_has_right('ModifyQueue') ) {
        return ( 0, _("Permission Denied") );
    }

    return $self->SUPER::_add_link(%args);
}

sub delete_link {
    my $self = shift;
    my %args = (
        base   => undef,
        target => undef,
        type   => undef,
        @_
    );

    #check acls
    unless ( $self->current_user_has_right('ModifyQueue') ) {
        Jifty->log->debug("No permission to delete links");
        return ( 0, _('Permission Denied') );
    }

    return $self->SUPER::_delete_link(%args);
}

=head2 available_rights

Returns a hash of available rights for this object. The keys are the right names and the values are a description of what the rights do

=cut

sub available_rights {
    my $self = shift;
    return ($RIGHTS);
}


=head2 create(ARGS)

Arguments: ARGS is a hash of named parameters.  Valid parameters are:

  name (required)
  description
  correspond_address
  comment_address
  initial_priority
  final_priority
  default_due_in
 
If you pass the ACL check, it creates the queue and returns its queue id.


=cut

sub create {
    my $self = shift;
    my %args = (
        name               => undef,
        correspond_address => '',
        description        => '',
        comment_address    => '',
        subject_tag        => '',
        initial_priority   => 0,
        final_priority     => 0,
        default_due_in     => 0,
        sign               => undef,
        encrypt            => undef,
        @_
    );

    unless (
        $self->current_user->has_right(
            right  => 'AdminQueue',
            object => RT->system
        )
        )
    {    #Check them ACLs
        return ( 0, _("No permission to create queues") );
    }

    my $sign = delete $args{'sign'};
    my $encrypt = delete $args{'encrypt'};

    #TODO better input validation
    Jifty->handle->begin_transaction();
    my $id = $self->SUPER::create( %args );
    unless ($id) {
        Jifty->handle->rollback();
        return ( 0, _('Queue could not be created') );
    }

    my $create_ret = $self->_create_role_groups();
    unless ($create_ret) {
        Jifty->handle->rollback();
        return ( 0, _('Queue could not be created') );
    }
    Jifty->handle->commit;

    if ( defined $sign ) {
        my ( $status, $msg ) = $self->set_sign( $args{'sign'} );
        Jifty->log->error("Couldn't set attribute 'sign': $msg")
            unless $status;
    }
    if ( defined $encrypt ) {
        my ( $status, $msg ) = $self->set_encrypt( $args{'encrypt'} );
        Jifty->log->error("Couldn't set attribute 'encrypt': $msg")
            unless $status;
    }

    return ( $id, _("Queue Created") );
}



sub delete {
    my $self = shift;
    return ( 0, _('Deleting this object would break referential integrity') );
}



=head2 set_disabled

Takes a boolean.
1 will cause this queue to no longer be available for tickets.
0 will re-enable this queue.

=cut



=head2 load

Takes either a numerical id or a textual name and loads the specified queue.

=cut

sub load {
    my $self       = shift;
    my $identifier = shift;
    if ( !$identifier ) {
        return (undef);
    }

    if ( $identifier =~ /^(\d+)$/ ) {
        $self->load_by_cols( id => $identifier );
    } else {
        $self->load_by_cols( name => $identifier );
    }

    return ( $self->id );
}

=head2 status_schema

=cut

sub status_schema {
    my $self = shift;
    my $res = RT::StatusSchema->load(
        (ref $self && $self->id) ? $self->__value('status_schema') : ''
    );
    Jifty->log->error("Status schema doesn't exist") unless $res;
    return $res;
}

=head2 set_sign

=cut

sub sign {
    my $self  = shift;
    my $value = shift;

    return undef unless $self->current_user_has_right('SeeQueue');
    my $attr = $self->first_attribute('sign') or return 0;
    return $attr->content;
}

sub set_sign {
    my $self  = shift;
    my $value = shift;

    return ( 0, _('Permission Denied') )
        unless $self->current_user_has_right('AdminQueue');

    my ( $status, $msg ) = $self->set_attribute(
        name        => 'sign',
        description => 'Sign outgoing messages by default',
        content     => $value,
    );
    return ( $status, $msg ) unless $status;
    return ( $status, _('Signing enabled') ) if $value;
    return ( $status, _('Signing disabled') );
}

sub encrypt {
    my $self  = shift;
    my $value = shift;

    return undef unless $self->current_user_has_right('SeeQueue');
    my $attr = $self->first_attribute('encrypt') or return 0;
    return $attr->content;
}

sub set_encrypt {
    my $self  = shift;
    my $value = shift;

    return ( 0, _('Permission Denied') )
        unless $self->current_user_has_right('AdminQueue');

    my ( $status, $msg ) = $self->set_attribute(
        name        => 'encrypt',
        description => 'Encrypt outgoing messages by default',
        content     => $value,
    );
    return ( $status, $msg ) unless $status;
    return ( $status, _('Encrypting enabled') ) if $value;
    return ( $status, _('Encrypting disabled') );
}

=head2 templates

Returns an RT::Model::TemplateCollection object of all of this queue's templates.

=cut


sub templates {
    my $self = shift;

    my $templates = RT::Model::TemplateCollection->new;

    if ( $self->current_user_has_right('ShowTemplate') ) {
        $templates->limit_to_queue( $self->id );
    }

    return ($templates);
}

sub subject_tag {
    my $self = shift;
    return RT->system->subject_tag($self);
}

sub set_subject_tag {
    my $self  = shift;
    my $value = shift;

    return ( 0, _('Permission Denied') )
      unless $self->current_user_has_right('AdminQueue');

    my $attr = RT->system->first_attribute('BrandedSubjectTag');
    my $map = $attr ? $attr->content : {};
    if ( defined $value && length $value ) {
        $map->{ $self->id } = $value;
    }
    else {
        delete $map->{ $self->id };
    }

    my ( $status, $msg ) = RT->system->set_attribute(
        name        => 'BrandedSubjectTag',
        description => 'Queue id => subject tag map',
        content     => $map,
    );
    return ( $status, $msg ) unless $status;
    return (
        $status,
        _(
            "SubjectTag changed to %1",
            ( defined $value && length $value )
            ? $value
            : _("(no value)")
        )
    );
}

=head2 custom_field name

Load the queue-specific custom field named name

=cut

sub custom_field {
    my $self = shift;
    my $name = shift;
    my $cf   = RT::Model::CustomField->new;
    $cf->load_by_name_and_queue( name => $name, queue => $self->id );
    return ($cf);
}


=head2 ticket_custom_fields

Returns an L<RT::Model::CustomFieldCollection> object containing all global and
queue-specific B<ticket> custom fields.

=cut

sub ticket_custom_fields {
    my $self = shift;

    my $cfs = RT::Model::CustomFieldCollection->new;
    if ( $self->current_user_has_right('SeeQueue') ) {
        $cfs->limit_to_global_or_object_id( $self->id );
        $cfs->limit_to_lookup_type('RT::Model::Queue-RT::Model::Ticket');
    }
    return ($cfs);
}



=head2 ticket_transaction_custom_fields

Returns an L<RT::Model::CustomFieldCollection> object containing all global and
queue-specific B<transaction> custom fields.

=cut

sub ticket_transaction_custom_fields {
    my $self = shift;

    my $cfs = RT::Model::CustomFieldCollection->new;
    if ( $self->current_user_has_right('SeeQueue') ) {
        $cfs->limit_to_global_or_object_id( $self->id );
        $cfs->limit_to_lookup_type('RT::Model::Queue-RT::Model::Ticket-RT::Model::Transaction');
    }
    return ($cfs);
}



=head2 _create_queue_groups

Create the ticket groups and links for this ticket. 
This routine expects to be called from Ticket->create _inside of a transaction_

It will create four groups for this ticket: Requestor, Cc, AdminCc and owner.

It will return true on success and undef on failure.

=cut

sub roles {qw(requestor cc admin_cc)}

sub _create_role_groups {
    my $self = shift;

    my @types = ( 'owner', $self->roles );

    foreach my $type (@types) {
        my $type_obj = RT::Model::Group->new;
        my ( $id, $msg ) = $type_obj->create_role_group(
            instance => $self->id,
            type     => $type,
            domain   => 'RT::Model::Queue-Role'
        );
        unless ($id) {
            Jifty->log->error( "Couldn't create a queue group of type '$type' for ticket " . $self->id . ": " . $msg );
            return (undef);
        }
    }
    return (1);

}

=head2 add_watcher

AddWatcher takes a parameter hash. The keys are as follows:

Type        One of Requestor, Cc, AdminCc

PrinicpalId The RT::Model::Principal id of the user or group that's being added as a watcher
Email       The email address of the new watcher. If a user with this 
            email address can't be found, a new nonprivileged user will be Created.

If the watcher you\'re trying to set has an RT account, set the owner paremeter to their User Id. Otherwise, set the Email parameter to their Email address.

Returns a tuple of (status/id, message).

=cut

sub add_watcher {
    my $self = shift;
    my %args = (
        type         => undef,
        principal_id => undef,
        email        => undef,
        @_
    );

    return ( 0, "No principal specified" )
      unless $args{'email'}
          or $args{'principal_id'};

    if ( !$args{'principal_id'} && $args{'email'} ) {
        my $user = RT::Model::User->new;
        $user->load_by_email( $args{'email'} );
        $args{'principal_id'} = $user->principal_id if $user->id;
    }

    # {{{ Check ACLS
    return ( $self->_add_watcher(%args) )
      if $self->current_user_has_right('ModifyQueueWatchers');

    #If the watcher we're trying to add is for the current user
    if ( defined $args{'principal_id'}
        && $self->current_user->id eq $args{'principal_id'} )
    {

        #  If it's an AdminCc and they don't have
        #   'WatchAsAdminCc' or 'ModifyTicket', bail
        if ( defined $args{'type'} && ( $args{'type'} eq 'admin_cc' ) ) {
            return ( $self->_add_watcher(%args) )
              if $self->current_user_has_right('WatchAsAdminCc');
        }

        #  If it's a Requestor or Cc and they don't have
        #   'Watch' or 'ModifyTicket', bail
        elsif ( $args{'type'} eq 'cc' or $args{'type'} eq 'requestor' ) {
            return ( $self->_add_watcher(%args) )
              if $self->current_user_has_right('Watch');
        } else {
            Jifty->log->warn("$self -> add_watcher got passed a bogus type");
            return ( 0, _('Error in parameters to Queue->add_watcher') );
        }
    }

    return ( 0, _("Permission Denied") );
}

#This contains the meat of AddWatcher. but can be called from a routine like
# Create, which doesn't need the additional acl check
sub _add_watcher {
    my $self = shift;
    my %args = (
        type         => undef,
        silent       => undef,
        principal_id => undef,
        email        => undef,
        @_
    );

    my $principal = RT::Model::Principal->new;
    if ( $args{'principal_id'} ) {
        $principal->load( $args{'principal_id'} );
    } elsif ( $args{'email'} ) {
        my $user = RT::Model::User->new;
        $user->load_by_email( $args{'email'} );
        $user->load( $args{'email'} )
          unless $user->id;

        if ( $user->id ) {    # If the user exists
            $principal->load( $user->principal_id );
        } else {

            # if the user doesn't exist, we need to create a new user
            my $new_user = RT::Model::User->new( current_user => RT->system_user );

            my ( $Address, $name ) = RT::Interface::Email::parse_address_from_header( $args{'email'} );

            my ( $Val, $Message ) = $new_user->create(
                name       => $Address,
                email      => $Address,
                real_name  => $name,
                privileged => 0,
                comments   => 'AutoCreated when added as a watcher'
            );
            unless ($Val) {
                Jifty->log->error( "Failed to create user " . $args{'email'} . ": " . $Message );

                # Deal with the race condition of two account creations at once
                $new_user->load_by_email( $args{'email'} );
            }
            $principal->load( $new_user->principal_id );
        }
    }

    # If we can't find this watcher, we need to bail.
    unless ( $principal->id ) {
        return ( 0, _("Could not find or create that user") );
    }

    my $group = RT::Model::Group->new;
    $group->create_role_group( # XXX: error checks 
        object => $self,
        type   => $args{'type'},
    );

    if ( $group->has_member($principal) ) {
        return ( 0, _( 'That principal is already a %1 for this queue', $args{'type'} ) );
    }

    my ( $m_id, $m_msg ) = $group->_add_member( principal_id => $principal->id );
    unless ($m_id) {
        Jifty->log->error( "Failed to add "
              . $principal->id
              . " as a member of group "
              . $group->id . ": "
              . $m_msg );

        return ( 0, _( 'Could not make that principal a %1 for this queue', $args{'type'} ) );
    }
    return ( 1, _( 'Added principal as a %1 for this queue', $args{'type'} ) );
}



=head2 delete_watcher { type => TYPE, principal_id => PRINCIPAL_ID }


Deletes a queue  watcher.  Takes two arguments:

Type  (one of Requestor,Cc,AdminCc)

and one of

principal_id (an RT::Model::Principal id of the watcher you want to remove)
    OR
Email (the email address of an existing wathcer)


=cut

sub delete_watcher {
    my $self = shift;

    my %args = (
        type         => undef,
        principal_id => undef,
        email       => undef,
        @_
    );

    unless ( $args{'principal_id'} || $args{'email'} ) {
        return ( 0, _("No principal specified") );
    }

    if ( !$args{principal_id} and $args{email} ) {
        my $user = RT::Model::User->new;
        my ( $rv, $msg ) = $user->load_by_email( $args{email} );
        $args{principal_id} = $user->principal_id if $rv;
    }

    my $principal = RT::Model::Principal->new;
    if ( $args{'principal_id'} ) {
        $principal->load( $args{'principal_id'} );
    }
    else {
        my $user = RT::Model::User->new;
        $user->load_by_email( $args{'email'} );
        $principal->load( $user->id );
    }

    # If we can't find this watcher, we need to bail.
    unless ( $principal->id ) {
        return ( 0, _("Could not find that principal") );
    }

    my $can_modify_queue = $self->current_user_has_right('ModifyQueueWatchers');

    # {{{ Check ACLS
    #If the watcher we're trying to add is for the current user
    if ( defined $args{'principal_id'}
        and $self->current_user->principal->id eq $args{'principal_id'} )
    {

        #  If it's an AdminCc and they don't have
        #   'WatchAsAdminCc' or 'ModifyQueue', bail
        if ( $args{'type'} eq 'admin_cc' ) {
            unless ( $can_modify_queue
                or $self->current_user_has_right('WatchAsAdminCc') )
            {
                return ( 0, _('Permission Denied') );
            }
        }

        #  If it's a Requestor or Cc and they don't have
        #   'Watch' or 'ModifyQueue', bail
        elsif (( $args{'type'} eq 'cc' ) or ( $args{'type'} eq 'requestor' ) ) {

            unless ( $can_modify_queue
                or $self->current_user_has_right('Watch') )
            {
                return ( 0, _('Permission Denied') );
            }
        } else {
            Jifty->log->warn("$self -> delete_watcher got passed a bogus type");
            return ( 0, _('Error in parameters to Queue->delete_watcher') );
        }
    }

    # If the watcher isn't the current user
    # and the current user  doesn't have 'ModifyQueueWathcers' bail
    else {
        unless ($can_modify_queue) {
            return ( 0, _("Permission Denied") );
        }
    }

    # }}}

    # see if this user is already a watcher.

    my $group = RT::Model::Group->new;
    $group->load_role_group(
        object => $self,
        type   => $args{'type'},
    );
    unless ( $group->id ) {
        return ( 0, _( 'That principal is not a %1 for this queue', $args{'type'} ) );
    }
    unless ( $group->has_member($principal) ) {
        return ( 0, _( 'That principal is not a %1 for this queue', $args{'type'} ) );
    }

    my ( $m_id, $m_msg ) = $group->_delete_member( $principal->id );
    unless ($m_id) {
        Jifty->log->error( "Failed to delete "
              . $principal->id
              . " as a member of group "
              . $group->id . ": "
              . $m_msg );

        return ( 0, _( 'Could not remove that principal as a %1 for this queue', $args{'type'} ) );
    }

    return ( 1, _( "%1 is no longer a %2 for this queue.", $principal->object->name, $args{'type'} ) );
}


=head2 role_group $role

Returns an RT::Model::Group object.
If the user doesn't have "ShowQueue" permission, returns an empty group

=cut

sub role_group {
    my $self  = shift;
    my $role  = shift;
    my $group = RT::Model::Group->new;
    if ( $self->current_user_has_right('SeeQueue') ) {
        $group->load_role_group( type => $role, object => $self );
    }
    return ($group);
}


# a generic routine to be called by IsRequestor, IsCc and is_admin_cc

=head2 is_watcher { type => TYPE, principal_id => PRINCIPAL_ID }

Takes a param hash with the attributes type and principal_id

Type is one of Requestor, Cc, AdminCc and owner

principal_id is an RT::Model::Principal id 

Returns true if that principal is a member of the group type for this queue


=cut

sub is_watcher {
    my $self = shift;

    my %args = (
        type         => 'cc',
        principal_id => undef,
        @_
    );

    # Load the relevant group.
    my $group = RT::Model::Group->new;
    $group->load_role_group(
        object => $self,
        type   => $args{'type'},
    );
    return 0 unless $group->id;

    # Ask if it has the member in question

    my $principal = RT::Model::Principal->new;
    $principal->load( $args{'principal_id'} );
    unless ( $principal->id ) {
        return (undef);
    }

    return ( $group->has_member_recursively($principal) );
}





sub _set {
    my $self = shift;

    unless ( $self->current_user_has_right('AdminQueue') ) {
        return ( 0, _('Permission Denied') );
    }
    return ( $self->SUPER::_set(@_) );
}



sub _value {
    my $self = shift;

    unless ( $self->current_user_has_right('SeeQueue') ) {
        return (undef);
    }

    return ( $self->__value(@_) );
}



=head2 current_user_has_right

Takes one argument. A textual string with the name of the right
we want to check. Returns true if the current user has that right
for this queue. Returns undef otherwise. If this queue is
not loaded then check is done on the system level.

See also </has_right>.


=cut

sub current_user_has_right {
    my $self  = shift;
    my $right = shift;

    return $self->has_right(
        @_,
        principal => $self->current_user,
        right     => $right,
    );
}

=head2 has_right

Takes a param hash with the fields 'right' and 'principal'.
Principal defaults to the current user.

Returns true if the principal has that right for this queue.
Returns false otherwise. If this queue is not loaded then
check is done on the system level.

See also </current_user_has_right>.

=cut

sub has_right {
    my $self = shift;
    my %args = (
        right     => undef,
        principal => undef,
        @_
    );
    my $principal = delete( $args{'principal'} ) || $self->current_user;
    unless ($principal) {
        Jifty->log->error("Principal undefined in Queue::has_right");
        return undef;
    }

    return $principal->has_right( %args, object => ( $self->id ? $self : RT->system ), );
}

1;

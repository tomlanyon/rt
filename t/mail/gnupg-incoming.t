#!/usr/bin/perl
use strict;
use RT::Test; use Test::More tests => 46;
use File::Temp;

use Cwd 'getcwd';
use String::ShellQuote 'shell_quote';
use IPC::Run3 'run3';

my $homedir = File::Spec->catdir( getcwd(), qw(lib t data crypt-gnupg) );

# catch any outgoing emails
RT::Test->fetch_caught_mails;

sub capture_mail {
    my $MIME = shift;

    open my $handle, '>>', 't/mailbox'
        or die "Unable to open t/mailbox for appending: $!";

    $MIME->print($handle);
    print $handle "%% split me! %%\n";
    close $handle;
}


RT->config->set( LogToScreen => 'debug' );
RT->config->set( 'GnuPG',
                 Enable => 1,
                 OutgoingMessagesFormat => 'RFC' );

RT->config->set( 'GnuPGOptions',
                 homedir => $homedir,
                 'no-permission-warning' => undef);
RT->config->set( MailCommand => \&capture_mail);

RT->config->set( 'MailPlugins' => 'Auth::MailFrom', 'Auth::GnuPG' );

my ($baseurl, $m) = RT::Test->started_ok;

# configure key for General queue
$m->login();
$m->content_like(qr/Logout/, 'we did log in');
$m->get( $baseurl.'/Admin/Queues/');
$m->follow_link_ok( {text => 'General'} );
$m->submit_form( form_number => 3,
		 fields      => { correspond_address => 'general@example.com' } );
$m->content_like(qr/general\@example.com.* - never/, 'has key info.');

ok(my $user = RT::Model::User->new(current_user => RT->system_user));
ok($user->load('root'), "Loaded user 'root'");
$user->set_email('recipient@example.com');

# test simple mail.  supposedly this should fail when
# 1. the queue requires signature
# 2. the from is not what the key is associated with
my $mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<EOF;
From: recipient\@example.com
To: general\@$RT::rtname
Subject: This is a test of new ticket creation as root

Blah!
Foob!
EOF
RT::Test->close_mailgate_ok($mail);

{
    my $tick = get_latest_ticket_ok();
    is( $tick->subject,
        'This is a test of new ticket creation as root',
        "Created the ticket"
    );
    my $txn = $tick->transactions->first;
    like(
        $txn->attachments->first->headers,
        qr/^X-RT-Incoming-Encryption: Not encrypted/m,
        'recorded incoming mail that is not encrypted'
    );
    like( $txn->attachments->first->content, qr'Blah');
}

# test for signed mail
my $buf = '';

run3(
    shell_quote(
        qw(gpg --armor --sign),
        '--default-key' => 'recipient@example.com',
        '--homedir'     => $homedir,
        '--passphrase'  => 'recipient',
    ),
    \"fnord\r\n",
    \$buf,
    \*STDOUT
);

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<"EOF";
From: recipient\@example.com
To: general\@$RT::rtname
Subject: signed message for queue

$buf
EOF
RT::Test->close_mailgate_ok($mail);

{
    my $tick = get_latest_ticket_ok();
    is( $tick->subject, 'signed message for queue',
        "Created the ticket"
    );

    my $txn = $tick->transactions->first;
    my ($msg, $attach) = @{$txn->attachments->items_array_ref};

    is( $msg->get_header('X-RT-Incoming-Encryption'),
        'Not encrypted',
        'recorded incoming mail that is encrypted'
    );
    # test for some kind of PGP-Signed-By: Header
    like( $attach->content, qr'fnord');
}

# test for clear-signed mail
$buf = '';

run3(
    shell_quote(
        qw(gpg --armor --sign --clearsign),
        '--default-key' => 'recipient@example.com',
        '--homedir'     => $homedir,
        '--passphrase'  => 'recipient',
    ),
    \"clearfnord\r\n",
    \$buf,
    \*STDOUT
);

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<"EOF";
From: recipient\@example.com
To: general\@$RT::rtname
Subject: signed message for queue

$buf
EOF
RT::Test->close_mailgate_ok($mail);

{
    my $tick = get_latest_ticket_ok();
    is( $tick->subject, 'signed message for queue',
        "Created the ticket"
    );

    my $txn = $tick->transactions->first;
    my ($msg, $attach) = @{$txn->attachments->items_array_ref};
    is( $msg->get_header('X-RT-Incoming-Encryption'),
        'Not encrypted',
        'recorded incoming mail that is encrypted'
    );
    # test for some kind of PGP-Signed-By: Header
    like( $attach->content, qr'clearfnord');
}

# test for signed and encrypted mail
$buf = '';

run3(
    shell_quote(
        qw(gpg --encrypt --armor --sign),
        '--recipient'   => 'general@example.com',
        '--default-key' => 'recipient@example.com',
        '--homedir'     => $homedir,
        '--passphrase'  => 'recipient',
    ),
    \"orzzzzzz\r\n",
    \$buf,
    \*STDOUT
);

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<"EOF";
From: recipient\@example.com
To: general\@$RT::rtname
Subject: Encrypted message for queue

$buf
EOF
RT::Test->close_mailgate_ok($mail);

{
    my $tick = get_latest_ticket_ok();
    is( $tick->subject, 'Encrypted message for queue',
        "Created the ticket"
    );

    my $txn = $tick->transactions->first;
    my ($msg, $attach, $orig) = @{$txn->attachments->items_array_ref};

    is( $msg->get_header('X-RT-Incoming-Encryption'),
        'Success',
        'recorded incoming mail that is encrypted'
    );
    is( $msg->get_header('X-RT-Privacy'),
        'PGP',
        'recorded incoming mail that is encrypted'
    );
    like( $attach->content, qr'orz');

    is( $orig->get_header('Content-Type'), 'application/x-rt-original-message');
    ok(index($orig->content, $buf) != -1, 'found original msg');
}

# test for signed mail by other key
$buf = '';

run3(
    shell_quote(
        qw(gpg --armor --sign),
        '--default-key' => 'rt@example.com',
        '--homedir'     => $homedir,
        '--passphrase'  => 'test',
    ),
    \"alright\r\n",
    \$buf,
    \*STDOUT
);

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<"EOF";
From: recipient\@example.com
To: general\@$RT::rtname
Subject: encrypted message for queue

$buf
EOF
RT::Test->close_mailgate_ok($mail);

{
    my $tick = get_latest_ticket_ok();
    my $txn = $tick->transactions->first;
    my ($msg, $attach) = @{$txn->attachments->items_array_ref};
    # XXX: in this case, which credential should we be using?
    is( $msg->get_header('X-RT-Incoming-Signature'),
        'Test User <rt@example.com>',
        'recorded incoming mail signed by others'
    );
}

# test for encrypted mail with key not associated to the queue
$buf = '';

run3(
    shell_quote(
        qw(gpg --armor --encrypt),
        '--recipient'   => 'random@localhost',
        '--homedir'     => $homedir,
    ),
    \"should not be there either\r\n",
    \$buf,
    \*STDOUT
);

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<"EOF";
From: recipient\@example.com
To: general\@$RT::rtname
Subject: encrypted message for queue

$buf
EOF
RT::Test->close_mailgate_ok($mail);

{
    my $tick = get_latest_ticket_ok();
    my $txn = $tick->transactions->first;
    my ($msg, $attach) = @{$txn->attachments->items_array_ref};
    
    TODO:
    {
        local $TODO = "this test requires keys associated with queues";
        unlike( $attach->content, qr'should not be there either');
    }
}

# test for badly encrypted mail
{
$buf = '';

run3(
    shell_quote(
        qw(gpg --armor --encrypt),
        '--recipient'   => 'rt@example.com',
        '--homedir'     => $homedir,
    ),
    \"really should not be there either\r\n",
    \$buf,
    \*STDOUT
);

$buf =~ s/PGP MESSAGE/SCREWED UP/g;

unlink 't/mailbox';
$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<"EOF";
From: recipient\@example.com
To: general\@$RT::rtname
Subject: encrypted message for queue

$buf
EOF
RT::Test->close_mailgate_ok($mail);
my $mails = file_content_unlink('t/mailbox');
my @mail = grep {/\S/} split /%% split me! %%/, $mails;
is(@mail, 1, 'caught outgoing mail.');
}

{
    my $tick = get_latest_ticket_ok();
    my $txn = $tick->transactions->first;
    my ($msg, $attach) = @{$txn->attachments->items_array_ref};
    unlike( ($attach ? $attach->content : ''), qr'really should not be there either');
}

sub get_latest_ticket_ok {
    my $tickets = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tickets->order_by( column => 'id', order => 'DESC' );
    $tickets->limit( column => 'id', operator => '>', value => '0' );
    my $tick = $tickets->first();
    ok( $tick->id, "found ticket " . $tick->id );
    return $tick;
}

sub file_content_unlink
{
    my $path = shift;
    diag "reading content of '$path'" if $ENV{'TEST_VERBOSE'};
    open my $fh, "<:raw", $path or die "couldn't open file '$path': $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    unlink $path;
    return $content;
}

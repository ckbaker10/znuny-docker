#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Kernel::System::ObjectManager;

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $Backend = $Kernel::OM->Get('Kernel::System::Ticket::Article::Backend::Internal');
my $Title = 'Synthetic migration acceptance ticket';
my $Content = "synthetic attachment\n" . pack('C*', 0..255);
my $Mode = shift @ARGV // 'verify';
if ($Mode eq 'create') {
    my $ID = $Ticket->TicketCreate(
        Title => $Title, Queue => 'Raw', Lock => 'unlock', Priority => '3 normal',
        State => 'new', CustomerNo => 'migration', CustomerUser => 'fixture@example.invalid',
        OwnerID => 1, UserID => 1,
    ) or die "TicketCreate failed\n";
    my $ArticleID = $Backend->ArticleCreate(
        TicketID => $ID, SenderType => 'agent', IsVisibleForCustomer => 1, UserID => 1,
        From => 'Fixture <fixture@example.invalid>', To => 'fixture@example.invalid',
        Subject => 'Synthetic article', Body => 'Synthetic migration body',
        ContentType => 'text/plain; charset=utf-8', HistoryType => 'AddNote',
        HistoryComment => 'Synthetic fixture', NoAgentNotify => 1,
        Attachment => [{ Content => $Content, ContentType => 'application/octet-stream',
            Filename => 'synthetic.bin' }],
    ) or die "ArticleCreate failed\n";
}
my @IDs = $Ticket->TicketSearch(Result => 'ARRAY', Title => $Title, UserID => 1);
die "Expected exactly one fixture ticket\n" unless @IDs == 1;
my @Articles = $Kernel::OM->Get('Kernel::System::Ticket::Article')->ArticleList(TicketID => $IDs[0]);
my $Found;
for my $Article (@Articles) {
    my %Data = $Backend->ArticleGet(TicketID => $IDs[0], ArticleID => $Article->{ArticleID});
    next unless ($Data{Subject} // '') eq 'Synthetic article';
    die "Article body changed\n" unless $Data{Body} eq 'Synthetic migration body';
    my %Index = $Backend->ArticleAttachmentIndex(ArticleID => $Article->{ArticleID});
    for my $FileID (keys %Index) {
        my %Attachment = $Backend->ArticleAttachment(ArticleID => $Article->{ArticleID}, FileID => $FileID);
        next unless ($Attachment{Filename} // '') eq 'synthetic.bin';
        die "Attachment changed\n" unless $Attachment{Content} eq $Content;
        $Found = { ticket_id => $IDs[0], article_id => $Article->{ArticleID},
            attachment_sha256 => sha256_hex($Attachment{Content}),
            storage_backend => $Backend->{ArticleStorageModule} };
    }
}
die "Fixture attachment missing\n" unless $Found;
print encode_json($Found), "\n";

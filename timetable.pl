use strict;
use warnings;
use utf8;
use DBI;
use Data::Dumper;
use Encode;
use JSON;
use feature 'say';

my $dbh = DBI->connect("dbi:SQLite:dbname=timetable.db", "", "", {
    sqlite_unicode => 1,
    RaiseError => 1,
}) or die $DBI::errstr;

my $sth = $dbh->prepare("SELECT * FROM timetable order by start_at asc");
$sth->execute;

while (my $row = $sth->fetchrow_hashref) {
    say '-' x 80;
    for my $key (keys %$row) {
        say encode_utf8 "$key:\n\t$row->{$key}";
    }
    say encode_json $row;
}



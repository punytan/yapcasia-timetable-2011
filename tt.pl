use strict;
use warnings;
use utf8;
use feature 'say';
use Encode;
use Data::Dumper;
use LWP::Simple;
use Web::Scraper;
use URI;
use DBI;
use SQL::Abstract;
use Time::Piece;

my $dbname = 'timetable.db';
unlink $dbname if -f $dbname;

my $dbh = DBI->connect("dbi:SQLite:dbname=$dbname", "", "", {
    sqlite_unicode => 1,
    RaiseError => 1,
}) or die $DBI::errstr;

$dbh->do(<<EOS);
create table if not exists timetable (
    id        int primary key,
    title     text not null,
    place     text not null,
    status    text not null,
    start_at  datetime not null,
    end_at    datetime not null,
    presenter text not null,
    duration  text not null,
    language  text not null,
    summary   text not null,
    genre     text not null,
    target    text not null
)
EOS

my $con = get 'http://yapcasia.org/2011/timetable.html';

for my $id ($con =~ m{/2011/talk/(\d+)}g) {
    my $res = (scraper {
        process 'h3', title => 'TEXT';
        process '.talk_view tr', 'about[]' => scraper {
            process 'td:first-child', 'name'  => 'text';
            process 'td:last-child',  'value' => 'text';
        };
    })->scrape(URI->new("http://yapcasia.org/2011/talk/$id"));

    my $x = Dumper $res; $x =~ s/\\x{([0-9a-z]+)}/chr(hex($1))/ge;
    #say encode_utf8 $x;

    my $sql = SQL::Abstract->new;
    my $table_map = {
        '会場'     => 'place',
        '状態'     => 'status',
        '開始時間' => 'start_at',
        '発表者'   => 'presenter',
        '発表時間' => 'duration',
        '発表言語' => 'language',
        '概要'     => 'summary',
        'ジャンル' => 'genre',
        '対象オーディエンス' => 'target',
    };

    my $fields = {
        id    => $id,
        title => $res->{title},
    };

    for my $item (@{$res->{about}}) {
        my $col = $table_map->{$item->{name}};
        $fields->{$col} = $item->{value};
    }

    $fields->{duration} = ($fields->{duration} =~ /(\d+)/) ? $1 : 5;

    $fields->{end_at} = (localtime->strptime($fields->{start_at}, '%Y-%m-%d %H:%M:%S') +  60 * $fields->{duration})
        ->strftime("%Y-%m-%d %H:%M:%S");

    my ($stmt, @bind) = $sql->insert("timetable", $fields);
    my $sth = $dbh->prepare($stmt);
    $sth->execute(@bind);

    print Dumper [$stmt, @bind];
    sleep 1;
}

exit;

__END__



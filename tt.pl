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
use Text::Xslate;
use Data::Section::Simple;

my $dbname = 'timetable.db';

main();exit;

sub main {
    fetch_timetable() unless -f $dbname;
    render_all();
}

sub render_all {
    my $dbh = get_dbh();
    my $tx = Text::Xslate->new(
        path => [ Data::Section::Simple->new->get_data_section ],
    );

    my $sth = $dbh->prepare("SELECT * FROM timetable ORDER BY start_at ASC");
    $sth->execute;

    my @talks;
    while (my $row = $sth->fetchrow_hashref) {
        $row->{start_at} = Time::Piece->strptime($row->{start_at}, '%Y-%m-%d %H:%M:%S');
        push @talks, $row;
    }

    say encode_utf8 $tx->render("index.tx", {talks => \@talks});
}

sub get_dbh {
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbname", "", "", {
        sqlite_unicode => 1,
        RaiseError => 1,
    }) or die $DBI::errstr;
}

sub fetch_timetable {
    my $dbh = get_dbh();
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
        $fields->{genre}    = $fields->{genre} // 'undefined'; # NOTE: some talks doesn't have this attr.

        $fields->{end_at} = (localtime->strptime($fields->{start_at}, '%Y-%m-%d %H:%M:%S') +  60 * $fields->{duration})
            ->strftime("%Y-%m-%d %H:%M:%S");

        warn encode_utf8 "$fields->{id}: $fields->{title} ($fields->{genre})";

        my ($stmt, @bind) = SQL::Abstract->new->insert("timetable", $fields);
        my $sth = $dbh->prepare($stmt);
        $sth->execute(@bind);


        sleep 1;
    }
}

__DATA__

@@ index.tx

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8" />
    <title>YAPC::Asia 2011 - Timetable Viewer #yapcasia</title>

    <meta name="viewport" content="initial-scale = 1.0,maximum-scale = 1.0" />
    <meta name="format-detection" content="telephone=no" />
    <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1/jquery.min.js"></script>

    <link rel="stylesheet/less" type="text/css" href="style.less">
    <script type="text/javascript" src="http://lesscss.googlecode.com/files/less-1.1.3.min.js"></script>

    <script type="text/javascript">
        var _gaq = _gaq || []; _gaq.push(['_setAccount', 'UA-13133548-2']); _gaq.push(['_trackPageview']);
        (function() {
            var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
            ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
            var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
        })();
    </script>

    <script>
        $(function () {
            var select_day = 12 < (new Date).getDate() && (new Date).getDate() < 16
                ? (new Date).getDate() : 13;

            var show_place_list = function () {
                $(".place-list a").each(function () {
                    $(this).attr('class').match(new RegExp(select_day))
                        ? $(this).parent().show() : $(this).parent().hide();
                });
            };

            $(".day" + select_day).show();
            show_place_list();

            $(".day-list a").click(function () {
                select_day = $(this).attr("class");
                $(".talk").hide();
                $(".day" + select_day).show();
                show_place_list();
            });

            $(".place-list a").click(function () {
                var select_place = $(this).text();
                $(".talk").hide();
                $(".day" + select_day).each(function () {
                    var _place_text = $(this).find("span.place").text();
                    if(_place_text.match(new RegExp(select_place))) {
                        $(this).show();
                    } else if (select_place == "All Talk") {
                        $(this).show();
                    }
                });
            });

            $(".talk-meta").click(function () {
                var selector = "#" + $(this).parent().parent().attr('id') + " li.talk-summary";
                $(selector).css("display") == 'block'
                    ? $(selector).hide() : $(selector).show();
            });
        });
    </script>

</head>
<body>
    <div id="header">
        <div id="logo">YAPC::Asia 2011</div>
        <ul class="day-list">
            <li><a href="#" class="13">Oct 13</a></li>
            <li><a href="#" class="14">Oct 14</a></li>
            <li><a href="#" class="15">Oct 15</a></li>
        </ul>
        <ul class="place-list">
            <li><a href="#" class="13 14 15">All Talk</a></li>
            <li><a href="#" class="13">RejectConf</a></li>
            <li><a href="#" class="14 15">70周年記念講堂</a></li>
            <li><a href="#" class="14 15">フェライト会議室 100年記念館</a></li>
            <li><a href="#" class="14">ディジタル多目的ホール</a></li>
            <li><a href="#" class="15">蔵前会館 ロイヤルブルーホール</a></li>
            <li><a href="#" class="14 15">スイーツエリア</a></li>
        </ul>
    </div>

    <div id="contents">
        : for $talks -> $talk {
        <div class="talk day<: $talk.start_at.mday() :>" id="talk-<: $talk.id :>" style="display:none;">
            <ul>
                <li class="talk-meta">
                    <div class="start_at"><span><: $talk.start_at :> (<: $talk.duration :>min.)</span></div>
                    <div class="title">
                        <div><: $talk.title :></div>
                        <div><: $talk.presenter :></div>
                    </div>

                    <div style="text-align:right;">
                        <span>in <: $talk.language :>, at <span class="place"><: $talk.place :></span></span>
                    </div>
                </li>
                <li class="talk-summary" style="display:none;">
                    <div class="summary"><: $talk.summary :></div>
                </li>
            </ul>
        </div>
        : }

    </div>

    <div id="footer">
        <ul class="place-list">
            <li><a href="#" class="13 14 15">All Talk</a></li>
            <li><a href="#" class="13">RejectConf</a></li>
            <li><a href="#" class="14 15">70周年記念講堂</a></li>
            <li><a href="#" class="14 15">フェライト会議室 100年記念館</a></li>
            <li><a href="#" class="14">ディジタル多目的ホール</a></li>
            <li><a href="#" class="15">蔵前会館 ロイヤルブルーホール</a></li>
            <li><a href="#" class="14 15">スイーツエリア</a></li>
        </ul>
        <ul class="day-list">
            <li><a href="#" class="13">Oct 13</a></li>
            <li><a href="#" class="14">Oct 14</a></li>
            <li><a href="#" class="15">Oct 15</a></li>
        </ul>
        <div class="credit">
            <div>by <a href="https://github.com/punytan">@punytan</a></div>
            <div><a href="https://github.com/punytan/yapcasia-timetable-2011">Fork me on github!</a></div>
        </div>
    </div>

</body>
</html>

__END__


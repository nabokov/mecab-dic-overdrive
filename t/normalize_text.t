use strict;
use Test::More qw(no_plan);
use MecabTrainer::NormalizeText;


my $t;
$t = MecabTrainer::NormalizeText->new(['none']);
is($t->normalize(source2internal("<br>あいう&gt;\n〜　１Ａ1A")),
                 source2internal("<br>あいう&gt;\n〜　１Ａ1A"));

$t = MecabTrainer::NormalizeText->new(['decode_entities']);
is($t->normalize(source2internal("<br>あいう&gt;&hearts;&#0070;&#13102;&#x3312;&nonexistententity;\n〜　１Ａ1A")),
                  source2internal("<br>あいう>♥F㌮㌒&nonexistententity;\n〜　１Ａ1A"));

$t = MecabTrainer::NormalizeText->new(['strip_html']);
is($t->normalize(source2internal("<br><a href=\"abc\" alt=\"<abc>\">あいう</a>&gt;\n〜　１Ａ1A")),
                     source2internal("\nあいう\n〜　１Ａ1A"));

$t = MecabTrainer::NormalizeText->new(['strip_nl']);
is($t->normalize(source2internal("<br>あいう&gt;\n〜　１Ａ1A\n\n\n\n")),
                 source2internal("<br>あいう&gt;〜　１Ａ1A"));

$t = MecabTrainer::NormalizeText->new(['strip_single_nl']);
is($t->normalize(source2internal("<br>あいう&gt;\n〜　１Ａ1A\n\n\n\n")),
                 source2internal("<br>あいう&gt;〜　１Ａ1A\n"));

$t = MecabTrainer::NormalizeText->new(['decode_entities', 'wavetilde2long']);
is($t->normalize(source2internal("&#x301C;&#xFF5E;−ー")),
                 source2internal("ーー−ー"));

$t = MecabTrainer::NormalizeText->new(['decode_entities', 'wave2tilde']);
is($t->normalize(source2internal("&#x301C;&#xFF5E;−ー")),
                 chr(hex("FF5E")).chr(hex("FF5E")).source2internal("−ー"));

$t = MecabTrainer::NormalizeText->new(['decode_entities', 'nfkc']);
is($t->normalize(source2internal("か").chr(hex("3099")).source2internal("&#x301C;&#xFF5E;㉞㍘㎯㍖")),
                 source2internal("が").chr(hex("301C")).source2internal("~340点rad").chr(hex("2215")).source2internal("s2レントゲン") );


1;

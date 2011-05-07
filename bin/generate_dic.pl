#!/usr/bin/perl

#
# ユーザ辞書作成の手順
#
# 1.元データを用意
#   Wikipediaクラス使用の場合: jawiki-*-pages-articles.xml.bz2 をdbにロードしたもの
#   WikipediaFileクラス使用の場合: jawiki-*-pages-articles.xml.bz2 ファイル自体
#   Kaomojiクラス使用の場合: 顔文字辞書をtsvにしたファイル
#   SimpleListクラス使用の場合: 単語を列挙したテキストファイル
#
# 2.generate_dic.pl --target=クラス名[ wikipedia|wikipedia_file|kaomoji|simple_list ... ] でdicファイル書き出し
#
# 3.~/.mecabrcのuserdicや、MeCabインスタンスを呼ぶときのuserdicオプションに、ここで書き出されたdicファイルを指定
#

use strict;
use Encode;
use Encode::JP;
use Getopt::Long;

use FindBin;
use lib "$FindBin::Bin/../lib";

use MecabTrainer::Config;
use MecabTrainer::Utils qw(:all);

my $logger = init_logger(MecabTrainer::Config->new->{log_conf});

my %opts;
$opts{compile} = 1;
&GetOptions(\%opts, 'target=s', 'compile!');

my $gen_dic_class = $opts{target};
$gen_dic_class =~ s/(^|_|-)(.)/uc($2)/eg;
$gen_dic_class = "MecabTrainer::GenDic::".$gen_dic_class;

eval "require $gen_dic_class";
if ($@) {
    print <<EOS;
usage:
  generate_dic.pl --target=(plugin classname = wikipedia | kaomoji | simple_list ...) [ --nocompile ]
  see etc/config.pl and lib/MecabTrainer/GenDic/*.pm for details.
EOS
    exit;
}

my $gen_dic = $gen_dic_class->new;

$gen_dic->prepare_costs;
$gen_dic->write_csv;
$gen_dic->compile_dic if ($opts{compile});

exit;

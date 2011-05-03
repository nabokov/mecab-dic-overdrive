package MecabTrainer::GenDic::Wikipedia;

#
# Wikipedia の page テーブルの語を dic 化する用
# 名詞/固有名詞 固定。
# page テーブルへのロードは別途やっておく必要あり
#

use base qw(MecabTrainer::GenDic);
use strict;
use DBI;
use DBD::mysql;

use MecabTrainer::Config;
use MecabTrainer::Utils qw(:all);

my $conf = MecabTrainer::Config->new;
my $logger = init_logger($conf->{log_conf});

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    $self->{db} = init_db($self->{datasource});

    $self->{sth_get_titles} = $self->{db}->prepare(q{
select page_id, page_title from }.$self->{wikipedia_schema_prefix}.q{.page
  where page_namespace = 0
}) or db_error;
    $self->{sth_get_titles}->execute or db_error;

    return $self;
}

sub defaults {
    my $class = shift;
    return +{
        %{$class->SUPER::defaults},

        datasource => [ 'dbi:mysql:database=wikipedia_db;host=localhost', '', '' ],
        wikipedia_schema_prefix => 'wikipedia',

        to_file => $conf->{dic_aux_files_dir} . '/wikipedia.csv',
        dic_file => $conf->{dic_aux_files_dir} . '/wikipedia.dic',
        morphs => [ { feature => source2internal('名詞,固有名詞,一般,*,*,*,*') } ],
    };
}

sub read_next_line {
    my $self = shift;

    if (my ($id, $title) = $self->{sth_get_titles}->fetchrow_array) {
        $title = db2internal($title);
        return {
            word => $self->normalize_title($title),
            additional_feature => { wikipedia_id => $id },
            default_morph => $self->{morphs}->[0]
        }
    }

    else {
        return undef;
    }
}

sub DESTROY {
    my $self = shift;

    $self->{sth_get_titles}->finish;
#    $self->{db}->disconnect or db_error;
}

sub normalize_title {
    my ($self, $title) = @_;

    # http://ja.wikipedia.org/wiki/Wikipedia:記事名の付け方

    $title = $1 if ($title =~ /(.*)_\(.*\)/);
    $title =~ s/_/ /g;

    return $title;
}

1;

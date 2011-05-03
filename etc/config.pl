$HOME = '/home/user1/mecab-dic-overdrive'; ### 最初に設定すること

+{
    home_dir => $HOME,
    log_conf => $HOME.'/etc/log.conf',

    # デフォルトの正規化規則
    default_normalize_opts => [qw(decode_entities strip_single_nl wavetilde2long fullminus2long dashes2long drawing_lines2long unify_long_repeats nfkc lc)],

    # 辞書生成関連
    dic_aux_files_dir => $HOME.'/misc/dic', # デフォルトのipadicに対するパッチとか追加辞書データとかをおいておくところ

    idfile_kanji_code => 'utf-8', # idfileの漢字コード=dic_src_dirにあるソースのエンコーディング
    out_kanji_code => 'utf-8', # CSV出力時のエンコーディング(mecab-dict-indexが読み込む)
    dic_kanji_code => 'utf-8', # 辞書バイナリのエンコーディング(mecabが読み込む)

    dicdir => "/usr/local/lib/mecab/dic/ipadic-utf8", # インストール済のmecab用dicdir (mecabの引数として渡す用)
    mecab_dict_index => "/usr/local/libexec/mecab/mecab-dict-index",

    # Text::MeCabがデフォルトで使う追加辞書
    mecab_default_userdic => "$HOME/misc/dic/kaomoji.dic,$HOME/misc/dic/wikipedia.dic",

}


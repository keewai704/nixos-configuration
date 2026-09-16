---
name: nixos-validation
description: この nixos-configuration リポジトリの変更を最小限の確認で検証し、変更後のエラーを調査する。正常時の全ホストビルドや評価値の前後比較を避ける。別リポジトリの作業には使わない。
---

# NixOS 設定の検証

ホスト確認、作業の分離、コミット、ローカル適用は [AGENTS.md](../../../AGENTS.md) に従う。
このスキルは、このリポジトリとその worktree の検証範囲を選ぶために使う。

## 通常の変更

- 編集前の Git コミットを一度記録する。変更前の Nix 評価や設定のスナップショットは取らない。
- 整形・構文確認は変更したファイルに絞る。文書・リポジトリ専用スキルだけの変更では、
  空白、リンク、指示の整合性、スキルの frontmatter を確認し、Nix の評価・ビルドは行わない。
- 現在のホストに影響する変更は、適用時の `nixos-rebuild test` に含まれる評価・ビルドを使う。
  同じ出力の事前ビルドや個別評価を重ねない。
- 別ホストだけの設定は、変更した属性だけをローカルで評価する。
  パッケージの実装やビルド処理を変えた場合は対象出力のビルドで兼ねる。
  共通設定でも、他ホスト固有の分岐を変えていなければ全ホストをビルドしない。
- `nix flake check`、全設定の評価、期待値一覧、前後比較を一律の完了条件にしない。
  上流の標準ビルドに含まれるテストと、必要な構文・依存関係の確認は維持する。
  独自の固定値テストや上流テストの追加実行は増やさず、成功済みの確認は繰り返さない。

## 変更後にエラーが出た場合

失敗したコマンドとログから原因を絞る。設定値の変化を調べる必要がある場合だけ、
関係する同じ属性を変更前のコミットと現在の作業ツリーで評価し、差分だけを読む。
`repo` は作業中のチェックアウトの絶対パス、`before` は記録したコミット、
`attribute` は原因に関係する小さな JSON 化可能な属性とする。

JSON と標準エラーは `mktemp -d` で作った `comparison_dir` に保存し、全文をツール出力に返さない。
次の評価は一方ずつ実行して終了コードを確認し、両方成功した場合だけ比較へ進む。

```sh
nix eval --json --no-write-lock-file "git+file://$repo?rev=$before#$attribute" \
  >"$comparison_dir/before.raw.json" 2>"$comparison_dir/before.stderr"
nix eval --json --no-write-lock-file "$repo#$attribute" \
  >"$comparison_dir/after.raw.json" 2>"$comparison_dir/after.stderr"
```

`jq -S .` などでキーを整列し、複数行に整形してからファイル同士を比較する。
配列の順序と値は保持する。長い文字列は整形後も一行になり得るため、行数だけで表示量を制限しない。

```sh
jq -S . "$comparison_dir/before.raw.json" >"$comparison_dir/before.json" &&
  jq -S . "$comparison_dir/after.raw.json" >"$comparison_dir/after.json"
```

整形も成功した場合だけ `diff` を実行する。

```sh
diff_status=0
diff -u --label before --label after "$comparison_dir/before.json" "$comparison_dir/after.json" \
  >"$comparison_dir/values.diff" || diff_status=$?
printf 'diff exit=%s\n' "$diff_status"
```

`diff` の終了コードは 0 が一致、1 が差分あり、2 以上が比較エラー。
一致ならその旨だけ返す。差分がある場合は `rtk diff -` で表示を短縮する。

```sh
rtk diff - <"$comparison_dir/values.diff" >"$comparison_dir/summary"
wc -c <"$comparison_dir/summary"
head -c 8192 "$comparison_dir/summary"
```

rtk が使えなければ元の diff に同じ表示上限を使う。要約も 8 KiB を超える場合は省略ありと明示し、
属性をさらに絞るか、一時ファイルを `rg` で検索して必要な範囲だけ読む。追加表示にもバイト数の上限を付ける。
rtk は表示だけに使い、要約同士やキーだけの JSON を比較して一致と判定しない。
正確な値や周辺情報が必要なら、保存した元の diff の該当箇所を確認する。

たとえば SSH の設定なら `nixosConfigurations.citrus.config.services.openssh.settings` を選ぶ。
ホストと属性は実際の変更箇所から決め、全設定を JSON 化しない。
新規ファイルは評価前にステージする。編集前から未コミットの変更があった場合は、
その状態を Git コミットとの比較で再現できるとは扱わない。

評価が失敗した側は保存した標準エラーを `rtk log` や `rg` で絞り、同じ表示上限で読む。
評価失敗や比較エラーを空の値や一致と扱わない。rtk の表示処理の成功も、元のコマンドの成功とは扱わない。
値が同じでも、ビルドや実行時の動作が正しい証拠にはしない。
修正後は失敗した確認をやり直し、原因調査に必要な場合か明示的な依頼がある場合だけ、
追加ホストのビルドや `nix flake check --no-write-lock-file` に広げる。

比較にはその場のコマンドを使い、リポジトリにスクリプト、恒久的なテスト集、比較用ファイルを追加しない。
調査が終わったら、今回作った一時ディレクトリを削除する。

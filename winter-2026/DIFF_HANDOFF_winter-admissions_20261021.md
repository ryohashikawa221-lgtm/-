# DIFF_HANDOFF: 冬期講習2026 申込・定員管理（採用版）

- ブランチ: `ryohashikawa221-lgtm/sundai_portal` の `cc/winter-admissions-20261021`（push 済み、PR 未作成）
- 基準: `origin/production` 490bf3c（本番の最新 migration `20261020190000` を含む）
- コミット: 343406e（Codex v3 の取り込み）→ 0501b14（公開前の修正と画面の作り直し）
- 本番 DB・Render・メール・公開には一切触れていません。本番は migration 一覧の読み取りのみ。
- 保存先について: Handoff Vault（`~/dev/Sundai_Handoff_Vault`）はこのクラウド環境から届かないため、このファイルを `-` リポジトリに置いています。Vault へのコピーと commit は手元で行ってください。

## 目的

保護者がポータルから冬期講習（サンクスギビング＋冬期）を申し込み、職員が講座ごとの定員・締切・料金確認を管理できるようにする。比較監査で採用した Codex v3 に、公開前に必須の修正と UI の作り直しを加えたもの。

## 設計と実装の対照

| 要件 | 実装 |
| --- | --- |
| 講座情報は時間割が正本 | `seasonal_plans.published_body` をそのまま使用。申込側は `seasonal_course_admission`（定員・締切・倍率・料金確認）だけを持つ |
| 定員（集団12・個別3）、手動締切と満席を別に | `seasonal_course_admission.capacity` / `manual_closed`。`winter_capacity_guard` トリガーで保存時に確認 |
| 同時申込で定員超過しない | 講習の行を `for update` でロックしてから判定（申込・職員操作とも同じ順） |
| 締切後も保持者は再保存できる | トリガーが保存済みの選択と比べ、新規追加だけを拒否 |
| 料金（個別1.4・2コマ1.6・講座数割引・きょうだい割引） | `winter_mode_quote` / `winter_apply_sibling`（SQL）と `lib/winter-admissions.ts`（画面）。PDF の24セル・必須例すべて一致 |
| 標準外講座は確認まで受け付けない | `winter_pricing_reviewed`。時間割の日時・換算数・形式が変わると確認は無効 |
| 確認→送信→受付番号 | `portal_seasonal_submit` が保存成功後に受付番号を発行。同じ操作IDの再送は同じ結果を返す |
| 職員の操作履歴 | 既存の `seasonal_audit`（追記のみ）に記録 |

## 今回の変更（0501b14）

1. 英語ラベルを日本語に（COURSE TIMETABLE / YOUR PLAN / 請求状態 issued・draft）。
2. 職員が料金倍率・料金確認を変えても、保護者の未保存の選択を消さない（金額だけ計算し直し、確認画面を閉じる）。別画面での申込更新・受付終了は従来どおり再読込。
3. 受付番号を `W26-XXXX-XXXX` に短縮（SQL で発行、`parseWinterReceipt` も更新）。
4. 職員用の一覧取得 `portal_winter_admissions_board` に各講座の `sessions`・`teacherLabel` を追加（保護者側の取得は変更なし）。
5. 保護者画面の作り直し: 手順表示、お子さんカード（講座数・金額）、スマホはカード一覧が既定（カードから直接選択）、残席の色分け、最小13px、確認・受付画面の日付表記、印刷用スタイル。
6. 職員画面の作り直し: 件数タイル、絞り込み、棒グラフ付きの表、画面内確認つきの締切・再開、行内編集、日程・担当の表示と CSV 出力。

## 変更ファイル（production との差分 34 ファイル）

- migration: `supabase/migrations/20261020200709_winter_admissions_reviewed.sql`（新規・本番未適用）
- 保護者画面: `app/guardian/seasonal/`（SeasonalRegistration, WinterTimetable, WinterSubmission, WinterPriceBreakdown, page と CSS）
- 職員画面: `app/portal/seasonal/admissions/`（新規）、`app/portal/seasonal/page.tsx`, `SeasonalGuide.tsx`
- 共通: `app/ui/SeasonalGuidePrices.tsx`, `SeasonalInvoiceSnapshot.tsx`, `SeasonalPriceSummary.tsx`
- lib: `winter-admissions.ts`, `winter-receipt.ts`, `winter-timetable.ts`, `seasonal-pricing.ts`, `seasonal-api-handlers.ts`
- テスト: `lib/__tests__/winter-*.test.ts`, `winter-admissions-fixture.ts`, `seasonal-api.test.ts`, `scripts/test-winter-admissions.mjs`
- CI: `.github/workflows/portal-quality.yml`（`test:winter-admissions` を追加）、`package.json`
- 資料: `docs/WINTER_2026_ADMISSIONS_REVIEW.md`, `docs/WINTER_2026_AUDIT_RESPONSE.md`、画像 `public/winter/`
- 請求エンジン（`lib/billing-engine/`）・通常授業・夏のシートは変更なし。

## migration

- `20261020200709_winter_admissions_reviewed.sql`: 表 `seasonal_course_admission` の追加、トリガー `winter_capacity_and_overlap`、関数の追加と `seasonal_snapshot` / `portal_seasonal_submit` / `seasonal_finance_courses` / `portal_seasonal_guardian_board` の置き換え（旧関数は `winter_guardian_board_legacy` に改名）。
- 版番号の確認: 本番の最新 `20261020190000` より新しい。origin の全ブランチに同じ版なし（2026-10-21 時点）。
- Codex v2 の旧候補 `20261020152612` は含めていません。**旧候補を適用した環境には適用しないこと**（その場合は別の前進 migration が必要）。

## 検証（このブランチで実行）

| コマンド | 結果 |
| --- | --- |
| `npm run test:all-lib` | 2,959件 合格 |
| `npm run test:winter-admissions`（PGlite、出席・請求・入金配賦の migration を含む統合 fixture） | 合格（追加テスト：職員一覧の日程・担当、短い受付番号） |
| `npm run typecheck` | 合格 |
| `npm run lint` と変更ファイルの `npx eslint --max-warnings=0` | 合格 |
| `npx next build` | 合格 |
| 実 PostgreSQL 16・別接続の同時実行（定員3に20家庭、同一操作ID×10、締切と申込の同時、締切後の保持・再保存・取消、定員の下げ過ぎ、満席での取消＋申込、古い料金画面、全体の一括拒否、締切と保持者の再保存の同時） | 全項目合格（統合 fixture。v3 監査時に3回、今回の変更後に1回） |
| 料金: PDF 24セル・$216/$224/$397/$418・SQL と画面の900通り | 一致（v3 監査時。今回の変更は料金計算に触れていない） |
| 画面: 390px / 1440px で、選択→詳細→確認→申し込む→受付番号→変更、職員の設定・締切 | 動作・横はみ出しなし（模擬 API） |
| `test:seasonal-timetable-ui` などの旧 UI シナリオ | 未実行。v2 以前の画面文言（「現在の選択で申込を保存」）を前提にしており、v3 の時点で既に合わない。CI には入っていない |
| staging・本番ログイン環境での確認 | 未確認 |

## リスク

- 既存関数（申込保存・保護者一覧・請求スナップショット・入金配賦）を置き換える。統合 fixture では既存の出席トリガー・請求ガード・入金配賦と合わせて試験済みだが、本番の全トリガー・権限との照合は未実施。
- 1回・2回だけの講座は「1講座分」以外の料金を表せない。学校の決定まで準備中にしておく運用が前提。
- 受付中に職員が料金を変えると、保護者は確認画面からやり直しになる（選択は残る）。
- 権限は既存の `timetable.manage` を共用。

## 復旧手順

- アプリ: Render で直前のデプロイに戻す（`production` の直前コミットで Deploy）。
- DB: 適用後に問題があれば、前進 migration で `winter_capacity_and_overlap` トリガーを外し、置き換えた4関数を置き換え前の定義（production にある各関数の最新の migration の定義）で作り直し、`winter_guardian_board_legacy` を `portal_seasonal_guardian_board` に戻す。`seasonal_course_admission` は残してよい（参照されなくなるだけ）。既存の申込データ（`seasonal_family_selections`）は変更しない。
- 公開ゲート `publication_enabled` を false に戻せば、保護者の申込は止まる。

## 監査に回す

Astra（Codex、`codex exec -s read-only -C <worktree>`）→ Fable 最終監査 → Ryo の GO。

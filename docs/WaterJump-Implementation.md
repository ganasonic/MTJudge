# ウォータージャンプ・リモート録画／自動転送

実装日: 2026-09-20。通常モードとウォータージャンプモードは分離しています。

## 調査で確認した既存構造

|項目|実装|
|---|---|
|カメラ／動画出力|`VideoRecorder`の`setupCamera`、既存のAVCaptureSession、AVCaptureMovieFileOutput|
|録画開始・停止|`VideoRecorder.startRecording` / `stopRecording`。今回の`RecordingController`を各入力の入口に追加|
|録画完了|`captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:` → 必要なら骨格線合成 → `VideoRecordingViewController.videoRecorder:didFinishRecordingToOutputFileURL:error:`|
|手動保存|`TagSelectionViewController` → `FileSaver.saveVideo:selections:error:`。選択済みダウンロードフォルダへコピーし、`.mov.tags.json`保存。UUIDで同名上書き防止|
|再生用コピー|`Application Support/CameraRecordings`。`LatestCameraRecordingPath`で最新を記憶|
|タグ|`TagManager`、`Tag`、`TagItem`、`TagSelectionViewController`。`Documents/tags.data`にカテゴリと子タグを保存|
|再生|カメラ画面のAVPlayer、速度変更・シーク・停止・再生用動画削除|
|Network / Watch|作業開始時にはなし|
|Scheme|MTJudge（既存）。今回MTJudgeWatchターゲットを追加してiPhoneアプリへ同梱|
|Bundle ID|既存`ganasonic.tool.app.MTJudge`を維持。新Watchのみ`ganasonic.tool.app.MTJudge.watchkitapp`|
|署名|既存Automatic / UM9N74S758 / Apple Developmentを維持。新Watchも同じチーム・開発署名|
|Deployment Target|既存アプリ12.0、プロジェクト14.1を変更せず維持。Xcode 27ビルドはコマンドで`IPHONEOS_DEPLOYMENT_TARGET=15.0`を指定。追加の転送機能はiOS 13以降、WatchアプリはwatchOS 10以降|

**保存先の相違:** 指示書の「現在Documents/Recordings」は現ソースと異なります。以前の要望で通常保存はダウンロードへ変更済みでした。通常保存を維持し、今回の自動録画と受信動画に`Documents/Recordings`を使用します。既存動画の移動・削除はしません。

## 操作方法

### iPad側の初回準備

1. MTJudgeのSetting → 「ウォータージャンプ / リモート録画」。Cameraのアンテナアイコンからも開けます。
2. 「この端末で受信待機」をON。ローカルネットワーク権限を許可。
3. 「この端末の登録コード」をコピー、または撮影用iPhoneへ入力するため確認。
4. MTJudgeを前景にしたままにします。受信モードでは画面の自動ロックを抑止します。

### 撮影用iPhone側の初回準備

1. iPadと同じWi-Fiへ接続。設定でウォータージャンプモード、必要なRemote Camera / Apple Watch Remote、録画後自動転送をON。
2. 検出されたiPadを選び、そのiPadの登録コードを入力。コードにはUUIDとランダム32バイト鍵が含まれます。手入力登録も可能。
3. 転送先は記憶されます。Bonjourで再検出し、実際の転送接続でTLS認証します。「検出済み」はまだ認証済み接続という意味ではありません。
4. 録画時間は10 / 15 / 20 / 30 / 45 / 60秒、初期値20秒。
5. 設定を閉じ、Camera画面に戻ります。カメラ・マイク権限を許可します。

### START / STOP

- 通常モードの本体REC: 従来通り手動停止 → タグ選択 → ダウンロード保存。
- ウォータージャンプモードの本体REC: 指定時間 → 自動停止 → タグなし自動保存 → 転送（ON時）。
- Web: iPhoneの設定に出るURLを別端末のSafari/Chromeで開く。専用アプリ不要。START / STOPと状態を表示。
- Watch: iPhoneにペアリングしたWatchへ同梱アプリ「MTJudge Remote」をインストール。REC / STOP、接続状態、状態更新ボタン。iPhoneでApple Watch RemoteをONにし、Cameraを前景に。
- タイマーは撮影用iPhone内で実際の録画開始通知から動作。リモコン切断やブラウザ終了によって取り消されません。
- 設定中、再生中、手動録画の未保存動画がある時、録画・保存処理中はSTARTを拒否します。
- 二重START、二重STOPは録画APIを重複呼び出ししません。

### 受信・再送

- iPadは受信中の進捗、検証、登録後に最新動画を自動再生します。
- 新しい動画を受信したら自動プレイヤーを更新します。複数動画は設定の「保存・受信した練習動画を見る」から選択できます。
- 転送失敗でも撮影用iPhoneの動画を保持。「転送を再送」で再試行。前景では30秒間隔と端末検出時にも再試行します。
- キューは撮影順。先頭の失敗中は後続を保留しますが、次の録画・保存は可能です。
- キュー投入時の転送先に固定するため、後から別iPadを登録しても既存待ち動画を勝手に別端末へ送りません。
- 転送待ち動画の削除は無効化。受信済み／転送済み動画の削除は確認後、この端末だけに作用します。

## 通信・ファイル形式

- Webリモコン: Network.frameworkのNWListener、HTTP/1.1、動的ポート、セッショントークン。URLフラグメントからブラウザ内でトークンを取り込みます。START/STOPはPOSTと認証ヘッダが必須。Origin確認、CORS不許可、ヘッダ8KB上限、同時接続8、5秒タイムアウト。STATUSは1秒間隔。
- Webは平文HTTPです。インターネットサーバーは使用しません。専用・信頼できるWi-Fiで利用し、接続URLを公開しないでください。WebのURLは待受再起動で更新。
- Apple間動画転送: Bonjour `_mtjudge-wj._tcp` + Network.frameworkのTCP/TLS 1.2 PSK（AES-128-GCM-SHA256）。Keychainに共有鍵を保存。Private API、AirDrop操作、独自OS制限回避は不使用。
- プロトコル: 4バイト長 + 最大16KB JSON → READY → 指定サイズの動画バイト列 → 検証・永続化 → UUID付きTRANSFERRED ACK。
- 64KB単位で読み書き。動画全体をメモリへ読み込みません。上限8GB。受信側は作業用コピーを含む必要空き容量を確認。
- `.Incoming/<UUID>.mov`で受信。検証後に`<ID>.mov`として登録。切断時の今回の一時ファイルは削除します。強制終了時の残った作業ファイルを自動で大量削除することはしません。
- `.mov.wj.json`: UUID、サイズ、SHA-256、作成時刻、動画仕様、タグ、転送要求／完了等。
- `.mov.tags.json`: 既存形式のカテゴリ・タグID・タグ名。リモート自動録画はタグなし`[]`。
- `Application Support/WaterJumpTransferQueue.json`: キュー記録。各動画の`.wj.json`からも未完了分を復元するため、保存直後のアプリ終了にも対応。
- ACKを受信して初めて送信完了を記録。ACKの喪失による再送でもUUIDとハッシュで二重登録・上書きを防止。

## 状態

録画と転送は別々に管理。録画側はREADY → RECORDING → STOPPING → SAVING → SAVED / ERROR。転送側はIDLE、WAITING_TRANSFER、TRANSFERRING、TRANSFERRED、TRANSFER_FAILED、受信はRECEIVING / COMPLETE / ERROR。Web/Watch向けには保存・転送完了をCOMPLETEとして表示。状態JSONにはrecordingStateも含めます。

転送中も録画が可能。骨格合成・保存中は安全のため次の録画を開始しません。アプリが背景へ移ると録画停止要求と通信停止を行い、前景復帰後に再送します。ロック中のカメラ継続やバックグラウンド常駐を保証しません。

## 画質

既存AVCaptureSession、MovieFileOutput、骨格合成のexport設定を使用し、追加機能から解像度・fps・codec・bitrateを変更していません。元実装には固定ビットレートや固定fpsの明示設定がなく、端末・capture format・骨格合成に依存します。

保存した各動画の`.wj.json`に`width`、`height`、`fps`、`codec`、`bitrate`、`size`、`duration`を記録。アプリの一覧にも主要値を表示します。実機測定値は別の検証記録を参照してください。

## 追加権限・Framework

- `NSLocalNetworkUsageDescription`と`NSBonjourServices = [_mtjudge-wj._tcp]`をInfo.plistへ追加。
- 空欄だった既存カメラ・マイク説明文を日本語で補完。
- Network、WatchConnectivity、Security、CryptoKit、AVKit。既存AVFoundationを継続。
- Swift標準のモジュール自動リンクを利用。新たな広域ネットワークentitlement、マルチキャストentitlement、バックグラウンドモード、ATS全面解除は追加していません。

## ビルド

`bash scripts/build_waterjump.sh phase10`

一時ディレクトリへソースをコピーして、Dropboxのファイル調整待ちを避けます。動画データはコピーしません。既存Schemeを使用し、上記Deployment Targetをコマンドで指定して未署名ビルド。

署名付きの場合は同じ`xcodebuild`で`CODE_SIGNING_ALLOWED=NO`を省略し、必要に応じて`-allowProvisioningUpdates`。`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`を指定。

既存テストターゲットがプロジェクトの古いDistribution設定を継承するため、実機テストではコマンドに`CODE_SIGN_IDENTITY='Apple Development'`を指定。既存テストターゲットのプロジェクト設定は変更していません。

## 実機テスト表

|番号|操作|確認内容|
|---|---|---|
|1|通常モードで本体REC、STOP、タグ／タグなし保存|従来のダウンロード保存、骨格線、再生、同名回避|
|2|Watch REC、20秒待つ|iPhoneのみで自動停止、Watch状態更新。途中でWatch通信を切っても停止|
|3|Android ChromeからSTART|20秒録画、STOP、STATUS、ブラウザを閉じても停止|
|4|別iPhone SafariからSTART|同上、画面のリロード後も操作できる|
|5|iPhone自動保存→iPad受信|進捗、ACK、受信動画の自動再生、サイズ・ハッシュ一致|
|6|動画転送中にWi-Fiを切断|TRANSFER_FAILED、iPhone元動画を保持。iPadに未完動画を登録しない|
|7|Wi-Fi再接続・再送|最後まで再送、1件だけ登録、ACK後に完了|
|8|2本連続撮影|転送中でも2本目を録画、撮影順転送、iPad一覧に両方|
|9|連打・複数リモコンで二重START/STOP|録画APIの二重呼出しなし、保存中START拒否|
|10|5 / 10 / 20 / 30 / 50mで測定|下記を記録。距離をコードで保証しない|

追加: マイク／カメラ／ローカルネットワーク拒否、未登録コード、誤った鍵、空き容量不足、アプリ強制終了後の再送、骨格ON/OFF、既存タグ階層の再起動後保持、画面ロック、iPad待受OFF。

## 50m環境テスト

各距離で少なくとも3本。Wi-Fiルーター／AP位置、SSID、周波数帯、遮蔽物・水面・人の配置、端末の向き、START応答時間、STOP時刻、保存時間、転送開始からACKまでの時間、動画サイズ、失敗・再送回数を記録します。APのクライアント分離・Bonjour遮断に注意。インターネット接続は不要ですが端末間の通信は必要です。WatchがiPhoneに届かない場合は同一Wi-Fi経由の到達性を確認し、Webリモコンでも比較してください。

## 既知の制限

- 実機のWatch、Android Chrome、別iPhone Safari、iPhone→iPadの組合せ、実際の50m試験は実機テスト表に従って別途確認が必要です。Mac上のTLSテストはそれらの代わりではありません。
- Watchアプリは新規Bundle IDのプロビジョニング／インストールが必要。Apple Watchの実機は未確認。
- iPadは既存のiPhone互換表示を維持。以前取り消した全面的な画面サイズ変更は再導入していません。
- 転送は中断位置からの再開ではなくファイル先頭から再送。
- 自動保存はタグなし。通常モードの既存タグ選択・保存を維持。
- ダウンロード・端末間の動画削除同期なし。
- 受信待受を許可した端末の共有鍵を持つ相手は送信可能。登録コードを他人へ公開しないこと。
- 動画保存／骨格合成中は次の録画を保留。画質を落として処理を早める変更は不実施。
- アプリ強制終了で残った受信一時ファイルは一覧に表示しませんが、残留する場合があります。
- SDKのAVAsset同期読み取り等の非推奨警告は既存Deployment Targetとの互換性のため残っています。ビルドエラーではありません。

// Natsumi Browser 6.12.1 does not provide a localization API and constructs
// its UI from hard-coded English strings. Translate those strings only when
// Firefox itself is running in Japanese. Product and style names stay intact.

const appLocale = Services.locale.appLocaleAsLangTag;

if (appLocale === "ja" || appLocale.startsWith("ja-")) {
  const cleanupKey = Symbol.for("sine.natsumiJapaneseLocalization.cleanup");
  window[cleanupKey]?.();

  const translations = new Map([
    // Natsumi navigation and common controls.
    ["Customize Natsumi", "Natsumiをカスタマイズ"],
    ["Keyboard Shortcuts", "キーボードショートカット"],
    ["Customize Keyboard Shortcuts", "キーボードショートカットをカスタマイズ"],
    ["About Natsumi", "Natsumiについて"],
    ["Settings", "設定"],
    ["Reset", "リセット"],
    ["Confirm", "確認"],
    ["Import", "インポート"],
    ["Export", "エクスポート"],
    ["Source code", "ソースコード"],
    ["Website", "ウェブサイト"],
    ["Check for updates", "更新を確認"],
    ["Checking for updates...", "更新を確認しています…"],
    ["You're up to date!", "最新の状態です"],
    ["Update check failed.", "更新の確認に失敗しました。"],
    ["Updater is unavailable", "アップデーターを利用できません"],
    ["Updates are disabled or externally managed", "更新は無効化されているか、外部で管理されています"],
    ["Open settings", "設定を開く"],
    ["Hide these warnings", "これらの警告を隠す"],
    ["Not assigned", "未割り当て"],
    ["This keybind cannot be used!", "このキー割り当ては使用できません"],
    ["Unregister this shortcut", "このショートカットの割り当てを解除"],
    ["No file selected.", "ファイルが選択されていません。"],
    ["User aborted import.", "インポートがキャンセルされました。"],
    ["Import timed out.", "インポートがタイムアウトしました。"],
    ["Could not import shortcuts.", "ショートカットをインポートできませんでした。"],
    ["The shortcuts handler rejected the imported data. Your old shortcuts are unchanged.", "インポートしたデータを処理できませんでした。既存のショートカットは変更されていません。"],
    ["Something went wrong.", "問題が発生しました。"],
    ["Your shortcuts could not be imported due to an unexpected error.", "予期しないエラーによりショートカットをインポートできませんでした。"],
    ["Shortcuts imported successfully!", "ショートカットをインポートしました"],
    ["Shortcuts exported successfully!", "ショートカットをエクスポートしました"],

    // First-run experience and browser notifications.
    ["Welcome to your", "ようこそ、あなただけの"],
    ["personal", "自分らしい"],
    ["internet.", "インターネットへ。"],
    ["Skip setup", "セットアップをスキップ"],
    ["Welcome to Natsumi", "Natsumiへようこそ"],
    ["Drumroll please...", "ドラムロールをどうぞ…"],
    ["Preparing for liftoff...", "起動の準備中…"],
    ["Warming up...", "準備運動中…"],
    ["Ready to browse?", "ブラウジングの準備はできましたか？"],
    ["Natsumi is ready to rock and roll. Have fun browsing!", "Natsumiの準備ができました。ブラウジングをお楽しみください！"],
    ["Let's go!", "始める"],
    ["Welcome to Natsumi!", "Natsumiへようこそ！"],
    ["You can always customize Natsumi to your likings in the preferences page.", "Natsumiは設定ページからいつでも好みに合わせて変更できます。"],
    ["Heads up: your tab style was reset to Proton.", "タブスタイルをProtonに戻しました。"],
    ["If you want to use other tab styles, simply enable the Classic tab design in settings.", "ほかのタブスタイルを使う場合は、設定でクラシックタブデザインを有効にしてください。"],
    ["Choose your layout", "レイアウトを選択"],
    ["You can choose between Multiple Toolbars for utility or Single Toolbar for simplicity.", "機能性を重視する複数ツールバーと、シンプルな単一ツールバーから選べます。"],
    ["Heads up: using Single Toolbar will enable vertical tabs.", "単一ツールバーを選ぶと縦型タブが有効になります。"],
    ["Select your accent color", "アクセントカラーを選択"],
    ["The accent color will be used throughout Natsumi. You can use your Firefox theme's colors if you want, too.", "アクセントカラーはNatsumi全体で使用されます。Firefoxテーマの色を使うこともできます。"],
    ["Paint your browser", "ブラウザーを彩る"],
    ["Choose a theme that you like. It'll be used as the browser's background.", "好みのテーマを選んでください。ブラウザーの背景として使用されます。"],
    ["You can also build your own theme in your browser's preferences page after setup.", "セットアップ後に設定ページから独自テーマを作成することもできます。"],
    ["Choose your icons", "アイコンを選択"],
    ["Choose the icon pack you want to use. Please note that some icons may not be changed regardless of icon pack.", "使用するアイコンパックを選んでください。アイコンパックによっては変更されないアイコンもあります。"],
    ["Fresh look for your tabs", "タブを新しい見た目に"],
    ["You can choose from a variety of tab designs to suit your style.", "好みに合わせてさまざまなタブデザインから選べます。"],
    ["Floating or not floating?", "URLバーを浮かせますか？"],
    ["You can choose to make your URL bar float or keep the original design.", "URLバーをフローティング表示にするか、従来の配置を維持するか選べます。"],
    ["Configuring your browser", "ブラウザーを設定しています"],
    ["We're configuring your browser to get Natsumi set up and working.", "Natsumiを利用できるようブラウザーを設定しています。"],
    ["Your browser will restart automatically once ready.", "準備ができるとブラウザーは自動的に再起動します。"],
    ["This browser isn't compatible", "このブラウザーには対応していません"],
    ["Acknowledge and restart browser", "確認してブラウザーを再起動"],
    ["Your browser is outdated", "ブラウザーが古くなっています"],
    ["Please update your browser or uninstall Natsumi.", "ブラウザーを更新するか、Natsumiをアンインストールしてください。"],

    // Choice names and descriptions.
    ["Multiple Toolbars", "複数ツールバー"],
    ["Single Toolbar", "単一ツールバー"],
    ["Iconic utilitarian design", "機能性を重視した象徴的なデザイン"],
    ["More space for web content", "ウェブコンテンツをより広く表示"],
    ["Default", "既定"],
    ["Just the default look", "標準の見た目"],
    ["Gradient", "グラデーション"],
    ["Light and simple", "明るくシンプル"],
    ["Complementary", "補色"],
    ["Combo of two opposites", "対照的な2色の組み合わせ"],
    ["Colorful", "カラフル"],
    ["Straightforward yet colorful", "素直でカラフル"],
    ["Playful", "遊び心"],
    ["Vibrant, popping colors", "鮮やかで弾ける色彩"],
    ["Lucid", "ルーシッド"],
    ["Dreamy and serene", "幻想的で穏やか"],
    ["Bright and nostalgic", "明るく懐かしい"],
    ["Black and white", "白と黒"],
    ["Browsing with pride 🏳️‍🌈", "誇りを持ってブラウジング 🏳️‍🌈"],
    ["Trans rights 🏳️‍⚧️", "トランスジェンダーの権利を支持 🏳️‍⚧️"],
    ["Custom", "カスタム"],
    ["Build your own", "独自テーマを作成"],
    ["Automatic", "自動"],
    ["Sidebar", "サイドバー"],
    ["Titlebar", "タイトルバー"],
    ["Haze", "ヘイズ"],
    ["Tinted Haze", "色付きヘイズ"],
    ["Light Green", "ライトグリーン"],
    ["Sky Blue", "スカイブルー"],
    ["Turquoise", "ターコイズ"],
    ["Yellow", "イエロー"],
    ["Peach Orange", "ピーチオレンジ"],
    ["Warmer Pink", "ウォームピンク"],
    ["Beige", "ベージュ"],
    ["Light Red", "ライトレッド"],
    ["Muted Pink", "くすみピンク"],
    ["Pink", "ピンク"],
    ["Lavender Purple", "ラベンダーパープル"],
    ["Silver", "シルバー"],
    ["System Accent", "システムのアクセント"],
    ["Standard Firefox icons", "Firefox標準アイコン"],
    ["Based on Lucide", "Lucideベース"],
    ["Based on Microsoft Fluent UI", "Microsoft Fluent UIベース"],
    ["Hide both", "両方を隠す"],
    ["Hide toolbar", "ツールバーを隠す"],
    ["Hide sidebar", "サイドバーを隠す"],
    ["Hold click", "長押し"],
    ["Modern, sleek and dynamic", "モダンで洗練された動的デザイン"],
    ["Box-like design", "ボックス型デザイン"],
    ["Curve-like design", "曲線型デザイン"],
    ["'Combines' tab and web content", "タブとウェブコンテンツを一体化"],
    ["Solid colors", "単色デザイン"],
    ["Inspired by Floorp's logo", "Floorpのロゴから着想"],
    ["Glassmorphism for tabs", "タブにグラスモーフィズムを適用"],
    ["Playful and interactive", "遊び心のあるインタラクティブなデザイン"],
    ["Proton design for Nova", "Nova向けProtonデザイン"],
    ["Standard Firefox tabs", "Firefox標準タブ"],
    ["Dynamic", "ダイナミック"],
    ["Sleek and adjustable", "洗練された調整可能なデザイン"],
    ["Proton-style pinned tabs", "Proton風のピン留めタブ"],
    ["Standard Firefox pinned tabs", "Firefox標準のピン留めタブ"],
    ["Floating", "フローティング"],
    ["Floats on web content", "ウェブコンテンツ上に表示"],
    ["Classic", "クラシック"],
    ["Anchored to navigation bar", "ナビゲーションバーに固定"],
    ["Stacked", "縦並び"],
    ["List-like layout", "リスト型レイアウト"],
    ["Side-by-side", "横並び"],
    ["Scrollable compact layout", "スクロール可能なコンパクトレイアウト"],
    ["Disabled", "無効"],
    ["Simple", "シンプル"],
    ["Nostalgic", "ノスタルジック"],
    ["None", "なし"],
    ["System font", "システムフォント"],

    // Natsumi settings groups.
    ["Browser Appearance", "ブラウザーの外観"],
    ["Customize your overall browser look and feel.", "ブラウザー全体の見た目をカスタマイズします。"],
    ["Text & Iconography", "テキストとアイコン"],
    ["Tweak how text and icons appear on the browser.", "ブラウザーのテキストとアイコン表示を調整します。"],
    ["Sidebar & Buttons", "サイドバーとボタン"],
    ["Tweak your sidebar and buttons.", "サイドバーとボタンを調整します。"],
    ["Tabs", "タブ"],
    ["Tweak how your tabs look and behave.", "タブの見た目と動作を調整します。"],
    ["Compact Mode", "コンパクトモード"],
    ["Compact Mode lets you have more space for web content.", "コンパクトモードではウェブコンテンツをより広く表示できます。"],
    ["Quickly preview links with a floating overlay.", "フローティング表示でリンク先をすばやくプレビューします。"],
    ["Miniplayer", "ミニプレーヤー"],
    ["Quickly control media from the navigation bar or sidebar.", "ナビゲーションバーやサイドバーからメディアをすばやく操作します。"],
    ["Picture-in-Picture", "ピクチャーインピクチャー"],
    ["Customize your Picture-in-Picture window.", "ピクチャーインピクチャーウィンドウをカスタマイズします。"],
    ["PDF Viewer", "PDFビューアー"],
    ["Natsumi gives your browser's PDF viewer a redesign for a more modern and organized feel.", "ブラウザーのPDFビューアーを、よりモダンで整理されたデザインに変更します。"],
    ["URL Bar", "URLバー"],
    ["Tweak how you want your URL bar to look.", "URLバーの見た目を調整します。"],
    ["Startup", "起動"],
    ["Open your browser in style!", "スタイリッシュにブラウザーを起動します。"],
    ["Miscellaneous", "その他"],
    ["All other settings you may need.", "その他の設定です。"],
    ["Layout", "レイアウト"],
    ["Appearance", "外観"],
    ["Behavior", "動作"],
    ["Accessibility", "アクセシビリティ"],
    ["Style", "スタイル"],
    ["Material", "マテリアル"],
    ["Preferences", "設定画面"],
    ["Panels", "パネル"],
    ["Shortcuts", "ショートカット"],
    ["Interactions", "操作"],
    ["Buttons", "ボタン"],
    ["Font", "フォント"],
    ["Icons", "アイコン"],
    ["Accent Color", "アクセントカラー"],
    ["Background Theme", "背景テーマ"],
    ["Tab design", "タブデザイン"],
    ["Pinned tabs", "ピン留めタブ"],
    ["Activation method", "起動方法"],
    ["Layout and Appearance", "レイアウトと外観"],
    ["Toolbar autohide", "ツールバーの自動非表示"],
    ["Animation", "アニメーション"],
    ["Startup sound", "起動音"],
    ["Window material", "ウィンドウのマテリアル"],

    // Browser appearance options.
    ["Choose the layout you want for your browser.", "ブラウザーで使用するレイアウトを選びます。"],
    ["Browser Separation", "ブラウザーの間隔"],
    ["Change the separation of the web page", "ウェブページ周囲の間隔を変更します"],
    ["Enable Islands view", "Islands表示を有効にする"],
    ["This will change the layout to look closer to the Firefox Nova design.", "レイアウトをFirefox Novaに近いデザインへ変更します。"],
    ["Use Nova theme gradient for navigation bar", "ナビゲーションバーにNovaテーマのグラデーションを使用"],
    ["Use Haze for Islands view", "Islands表示にヘイズを使用"],
    ["Apply Haze to web content container", "ウェブコンテンツ領域にヘイズを適用"],
    ["This may significantly impact performance.", "パフォーマンスに大きく影響する場合があります。"],
    ["Remove web content border radius", "ウェブコンテンツの角丸をなくす"],
    ["Remove browser separation where possible", "可能な箇所のブラウザー間隔をなくす"],
    ["Show Menu button", "メニューボタンを表示"],
    ["Show Extensions button", "拡張機能ボタンを表示"],
    ["Show Bookmarks on hover", "ホバー時にブックマークを表示"],
    ["When the Bookmarks bar is expanded, the bar will stay hidden until hovered.", "ブックマークバーを展開している場合でも、ポインターを重ねるまで非表示にします。"],
    ["Display window controls on the sidebar in Single Toolbar", "単一ツールバーではウィンドウ操作ボタンをサイドバーに表示"],
    ["You need to enable Vertical Tabs to customize these settings.", "これらを設定するには縦型タブを有効にしてください。"],
    ["Choose the type of background you want for your browser.", "ブラウザーで使用する背景の種類を選びます。"],
    ["Enable translucency effect", "半透明効果を有効にする"],
    ["This may not work as intended if your Desktop Environment does not support translucency.", "デスクトップ環境が半透明表示に対応していない場合、正しく動作しないことがあります。"],
    ["Add a soft glow to your web page", "ウェブページに柔らかな光彩を追加"],
    ["Gray out background when the browser window is inactive", "ブラウザーが非アクティブなとき背景をグレー表示"],
    ["Pride mode activated!", "Prideモードを有効にしました"],
    ["Pride mode deactivated!", "Prideモードを無効にしました"],
    ["You can click the LGBTQ+ theme 5 times in a row to disable this again.", "LGBTQ+テーマを5回連続でクリックすると無効にできます。"],
    ["You can click the LGBTQ+ theme 5 times in a row to enable this again.", "LGBTQ+テーマを5回連続でクリックすると有効にできます。"],
    ["Choose the accent color you want to use. This will be applied throughout your browser.", "使用するアクセントカラーを選びます。ブラウザー全体に適用されます。"],
    ["Use your Firefox theme's accent color where possible", "可能な箇所でFirefoxテーマのアクセントカラーを使用"],
    ["Normalize Firefox theme accent color", "Firefoxテーマのアクセントカラーを正規化"],
    ["This will keep saturation and brightness consistent with other Natsumi accent colors.", "彩度と明るさをほかのNatsumiアクセントカラーと揃えます。"],
    ["Choose the icon pack you want to use.", "使用するアイコンパックを選びます。"],
    ["Use alternative Back/Forward icons", "別デザインの戻る／進むアイコンを使用"],
    ["Show icons in context menu", "コンテキストメニューにアイコンを表示"],
    ["This may not show for some operating systems.", "OSによっては表示されない場合があります。"],
    ["Choose the font you want to use.", "使用するフォントを選びます。"],

    // Sidebar and tab options.
    ["Tweak how the sidebar looks.", "サイドバーの見た目を調整します。"],
    ["Display Pinned Toolbar above pinned tabs", "ピン留めツールバーをピン留めタブの上に表示"],
    ["Top toolbar", "上部ツールバー"],
    ["Creates a new top toolbar in the sidebar.", "サイドバーに新しい上部ツールバーを作成します。"],
    ["Show Sidebar controls", "サイドバー操作を表示"],
    ["This will disable the bottom toolbar.", "下部ツールバーは無効になります。"],
    ["Hide Bottom Toolbar when empty", "空の下部ツールバーを隠す"],
    ["Tweak the buttons visible in the sidebar.", "サイドバーに表示するボタンを調整します。"],
    ["Show clear unpinned tabs button", "ピン留めされていないタブを閉じるボタンを表示"],
    ["Clear your unpinned tabs all in one go.", "ピン留めされていないタブをまとめて閉じます。"],
    ["Keep selected tabs on clear", "消去時に選択中のタブを残す"],
    ["Any selected tabs will be kept when using the clear unpinned tabs button.", "未ピン留めタブを閉じる際、選択中のタブは残します。"],
    ["Open new tab on clear", "消去時に新しいタブを開く"],
    ["This will open a new tab if all tabs have been cleared.", "すべてのタブを閉じた場合は新しいタブを開きます。"],
    ["Show New Tab button", "新しいタブボタンを表示"],
    ["Move the New Tab button to the top", "新しいタブボタンを上部へ移動"],
    ["Choose the design you want for your tabs.", "タブのデザインを選びます。"],
    ["Tab font size offset", "タブのフォントサイズ補正"],
    ["Use legacy Blade highlight color", "従来のBlade強調色を使用"],
    ["My desktop environment can't scale properly", "デスクトップ環境で正しく拡大縮小できない"],
    ["Applies a 0.5px offset to Blade highlight to account for scaling issues.", "拡大縮小の問題を補うためBladeの強調表示を0.5pxずらします。"],
    ["Use absolute font size", "固定フォントサイズを使用"],
    ["Sets font size to use 12px instead of (global font size) + 1px.", "フォントサイズを「全体のサイズ＋1px」ではなく12pxにします。"],
    ["Enable Fusion tab highlight", "Fusionタブの強調表示を有効にする"],
    ["This will add a Photon (Firefox Quantum)-like highlight to Fusion.", "FusionにPhoton（Firefox Quantum）風の強調表示を追加します。"],
    ["Use alternative design for Material tabs", "Materialタブに別デザインを使用"],
    ["This will make tabs have a similar design to toolbar buttons.", "タブをツールバーボタンに近いデザインにします。"],
    ["Gray out unloaded tabs", "未読み込みのタブをグレー表示"],
    ["Cross out labels for unloaded tabs", "未読み込みタブのラベルに取り消し線を表示"],
    ["Pinned tab minimum width", "ピン留めタブの最小幅"],
    ["Tweak how you want tabs to behave.", "タブの動作を調整します。"],
    ["Replace New Tab", "新しいタブを置き換える"],
    ["This will let you open new tabs through the URL bar instead. Warning: This will override browser.urlbar.openintab.", "新しいタブをURLバーから開けるようにします。browser.urlbar.openintabの設定は上書きされます。"],
    ["Only use unpinned tabs for tab switching keyboard shortcuts", "キーボードでのタブ切り替え対象を未ピン留めタブだけにする"],

    // Compact mode, Glimpse and media.
    ["Customize how Compact Mode should look.", "コンパクトモードの見た目を調整します。"],
    ["Make sidebar and toolbar translucent in Compact Mode", "コンパクトモードでサイドバーとツールバーを半透明にする"],
    ["This adds a blur effect to the sidebar and toolbar when in Compact Mode.", "コンパクトモード時にサイドバーとツールバーへぼかし効果を追加します。"],
    ["Use accent color for sidebar and toolbar", "サイドバーとツールバーにアクセントカラーを使用"],
    ["This will revert the sidebar and toolbar background to the old accent color instead of the background gradient.", "サイドバーとツールバーの背景をグラデーションではなく従来のアクセントカラーに戻します。"],
    ["Marginless Compact Mode", "余白なしコンパクトモード"],
    ["Removes the borders around the website content when in Compact Mode.", "コンパクトモード時にウェブコンテンツ周囲の余白をなくします。"],
    ["Smaller compact sidebar", "小さいコンパクトサイドバー"],
    ["Reduces the height of the sidebar when in compact mode.", "コンパクトモード時のサイドバーの高さを小さくします。"],
    ["You need to use Multiple Toolbars layout to change which elements Compact Mode hides.", "コンパクトモードで隠す要素を変更するには複数ツールバーを使用してください。"],
    ["Tweak how you want Compact Mode to behave.", "コンパクトモードの動作を調整します。"],
    ["Enable Compact Mode by default", "既定でコンパクトモードを有効にする"],
    ["If enabled, new windows will open with Compact Mode active.", "有効にすると、新しいウィンドウはコンパクトモードで開きます。"],
    ["Display sidebar/toolbar for longer on hover", "ホバー時にサイドバー／ツールバーを長めに表示"],
    ["Tweak how you want Glimpse to behave.", "Glimpseの動作を調整します。"],
    ["Enable Glimpse", "Glimpseを有効にする"],
    ["Allow Multi Glimpse", "複数のGlimpseを許可"],
    ["This will let you open multiple Glimpse tabs at once for one tab.", "1つのタブから複数のGlimpseタブを同時に開けるようにします。"],
    ["Move Glimpse controls to the right", "Glimpseの操作ボタンを右へ移動"],
    ["Click on parent web content to close Glimpse tab", "元のウェブコンテンツをクリックしてGlimpseタブを閉じる"],
    ["Choose how Glimpse should be activated.", "Glimpseの起動方法を選びます。"],
    ["Tweak Glimpse to make it easier to use.", "Glimpseを使いやすく調整します。"],
    ["Show Glimpse indicator above content", "コンテンツ上にGlimpseインジケーターを表示"],
    ["Use an alternate border color for Glimpse", "Glimpseに別の境界線色を使用"],
    ["This may help as a quick way to identify Glimpse tabs.", "Glimpseタブをすばやく識別しやすくなります。"],
    ["Tweak how you want Natsumi's Miniplayer to behave.", "Natsumiミニプレーヤーの動作を調整します。"],
    ["Enable Miniplayer", "ミニプレーヤーを有効にする"],
    ["Pin Miniplayers by default", "既定でミニプレーヤーを固定"],
    ["Choose the layout and look you want for the Miniplayers.", "ミニプレーヤーのレイアウトと見た目を選びます。"],
    ["Show media thumbnail/artwork as Miniplayer background", "メディアのサムネイル／アートワークを背景に表示"],
    ["Use artwork to determine Miniplayer's accent color", "アートワークからミニプレーヤーのアクセントカラーを決定"],
    ["Scroll title and author text on overflow", "タイトルや作者名が長い場合にスクロール表示"],
    ["You need to enable Vertical Tabs to change the Miniplayer layout.", "ミニプレーヤーのレイアウトを変更するには縦型タブを有効にしてください。"],

    // Picture-in-Picture, PDF and URL bar.
    ["Choose the material to use for the controls and scrubber.", "操作ボタンとシークバーに使用するマテリアルを選びます。"],
    ["Tweak how you want Natsumi's Picture-in-Picture window to behave.", "Natsumiのピクチャーインピクチャーウィンドウの動作を調整します。"],
    ["Scroll-to-move", "スクロール移動"],
    ["Scroll-to-move allows you to move and resize the Picture-in-Picture window with mouse/trackpad scrolling.", "マウスやトラックパッドでスクロールして、ピクチャーインピクチャーウィンドウを移動・拡大縮小できます。"],
    ["Keep PiP window centered relative to original position on resize", "サイズ変更時もPiPウィンドウを元の位置を基準に中央へ保つ"],
    ["Use legacy design for Picture-in-Picture controls", "ピクチャーインピクチャーの操作ボタンに従来のデザインを使用"],
    ["This will merge Picture-in-Picture controls into one 'island' rather than having separate 'islands'.", "分かれているピクチャーインピクチャーの操作ボタンを1つの「島」にまとめます。"],
    ["Choose the material to use for the sidebar and toolbar.", "サイドバーとツールバーに使用するマテリアルを選びます。"],
    ["Toolbar autohide lets you focus on the document at hand by hiding the sidebar and toolbar when you don't need it.", "不要なときにサイドバーとツールバーを隠し、文書へ集中しやすくします。"],
    ["Enable Toolbar autohide", "ツールバーの自動非表示を有効にする"],
    ["Dynamic autohide", "動的な自動非表示"],
    ["Toolbar autohide will automatically disable if the sidebar is open.", "サイドバーを開いている間はツールバーの自動非表示を無効にします。"],
    ["Choose the layout to use for Natsumi's URL bar when opened.", "NatsumiのURLバーを開いたときのレイアウトを選びます。"],
    ["Tweak how you want Natsumi's URL bar to behave.", "NatsumiのURLバーの動作を調整します。"],
    ["Shrink URL bar width when not focused", "フォーカスされていないURLバーの幅を縮める"],
    ["Show actions buttons on hover when Single Toolbar is active", "単一ツールバー使用時、ホバーでアクションボタンを表示"],
    ["Show Kit on trust panel", "信頼パネルにKitを表示"],
    ["Because the cute mascot deserves more visibility and the shield icons don't do them justice.", "かわいいマスコットをもっと目立たせます。盾アイコンだけではもったいありません。"],

    // Startup and miscellaneous options.
    ["Choose the startup animation you want to be played when you open your browser.", "ブラウザーを開いたときに再生する起動アニメーションを選びます。"],
    ["Choose the sound to play for startup.", "起動時に再生する音を選びます。"],
    ["Tweak how you want the preferences page to look.", "設定ページの見た目を調整します。"],
    ["Revert to classic preferences look", "従来の設定画面に戻す"],
    ["If you don't like Natsumi's custom preferences design, you can enable this to disable it.", "Natsumi独自の設定画面を使わない場合は有効にしてください。"],
    ["Hide subcategories list", "サブカテゴリー一覧を隠す"],
    ["Choose which material to use for the window background.", "ウィンドウ背景に使用するマテリアルを選びます。"],
    ["Starlight Design 2 is an extension to Starlight Design aimed at enhancing visuals and contrast.", "Starlight Design 2は、見た目とコントラストを強化するStarlight Designの拡張です。"],
    ["Enable Starlight Design 2 (SDL2)", "Starlight Design 2（SDL2）を有効にする"],
    ["Enable web content backdrop", "ウェブコンテンツの背景効果を有効にする"],
    ["This does not affect browser.tabs.allow_transparent_browser.", "browser.tabs.allow_transparent_browserには影響しません。"],
    ["Tweak how you want panels or popups to look.", "パネルやポップアップの見た目を調整します。"],
    ["Compact Extensions panel", "拡張機能パネルをコンパクトにする"],
    ["Tweak how you want some shortcuts to behave.", "一部のショートカット動作を調整します。"],
    ["Copy clean URL with shortcut where possible", "可能な場合はショートカットで追跡情報を除いたURLをコピー"],
    ["Tweak how you want some interactions to behave.", "一部の操作方法を調整します。"],
    ["Invert scroll direction", "スクロール方向を反転"],
    ["This will invert the scroll direction for some Natsumi features. This does NOT affect web content.", "一部のNatsumi機能でスクロール方向を反転します。ウェブコンテンツには影響しません。"],

    // Shortcut conflicts, theme editing, and dynamic notifications.
    ["When shortcuts conflict, Natsumi should:", "ショートカットが競合した場合の動作:"],
    ["Prefer browser", "ブラウザーを優先"],
    ["When shortcuts conflict, the browser (or Natsumi) wins.", "競合時はブラウザー（またはNatsumi）の操作を優先します。"],
    ["Prefer website", "ウェブサイトを優先"],
    ["When shortcuts conflict, the website wins.", "競合時はウェブサイトの操作を優先します。"],
    ["Use both", "両方を使用"],
    ["When shortcuts conflict, both the browser's and website's shortcuts are used.", "競合時もブラウザーとウェブサイトの両方のショートカットを使用します。"],
    ["Use double tap", "2回押しを使用"],
    ["Press once for the website's shortcut, twice for the browser's shortcut.", "1回押すとウェブサイト、2回押すとブラウザーのショートカットを実行します。"],
    ["Edit Theme", "テーマを編集"],
    ["Theme saved!", "テーマを保存しました"],
    ["You can't use tools here!", "ここではツールを使用できません"],
    ["Advanced theme customization is available in settings.", "詳細なテーマ設定は設定ページから利用できます。"],
    ["Preset", "プリセット"],
    ["Color positions", "色の位置"],
    ["Managed", "自動配置"],
    ["Reset theme layer", "テーマレイヤーをリセット"],
    ["Open tools", "ツールを開く"],
    ["Click anywhere on the grid to add a color.", "グリッド上をクリックして色を追加します。"],
    ["Right-click on a color to remove it.", "色を右クリックすると削除できます。"],
    ["HEX code input", "HEXカラーコード入力"],
    ["HEX code (e.g. #ff0000)", "HEXカラーコード（例: #ff0000）"],
    ["Grain", "粒状感"],
    ["Image", "画像"],
    ["Image blur", "画像のぼかし"],
    ["Light", "弱"],
    ["Medium", "中"],
    ["Strong", "強"],
    ["Text and icon color", "文字とアイコンの色"],
    ["Freeform", "自由配置"],
    ["Split", "分割補色"],
    ["Analogous", "類似色"],
    ["Triadic", "三色配色"],
    ["Double", "二重補色"],
    ["Tetradic", "四色配色"],
    ["Pentagonal", "五角形"],
    ["Hexagonal", "六角形"],
    ["Linear", "線形"],
    ["Radial (cs)", "放射状（近い辺）"],
    ["Radial (cc)", "放射状（近い角）"],
    ["Radial (fs)", "放射状（遠い辺）"],
    ["Radial (fc)", "放射状（遠い角）"],
    ["Conic", "円錐"],
    ["Hybrid", "ハイブリッド"],
    ["No image uploaded", "画像はアップロードされていません"],
    ["No image selected", "画像が選択されていません"],
    ["No audio selected", "音声が選択されていません"],
    ["Please enter a valid HEX code.", "有効なHEXカラーコードを入力してください。"],
    ["Invalid HEX code.", "HEXカラーコードが無効です。"],
    ["This is not a valid HEX code.", "有効なHEXカラーコードではありません。"],
    ["Theme import failed.", "テーマのインポートに失敗しました。"],
    ["Either the theme is corrupted or something went wrong with the import process.", "テーマが破損しているか、インポート処理中に問題が発生しました。"],
    ["Theme imported successfully!", "テーマをインポートしました"],
    ["Theme exported successfully!", "テーマをエクスポートしました"],
    ["Dismiss", "閉じる"],
    ["Copied URL to clipboard!", "URLをクリップボードにコピーしました"],
    ["Copied URL as Markdown to clipboard!", "URLをMarkdown形式でクリップボードにコピーしました"],
    ["Your toolbar got an upgrade!", "ツールバーをアップグレードしました"],
    ["Your status bar items were moved to the new Natsumi Bottom Toolbar, so your status bar is free for more!", "ステータスバーの項目を新しいNatsumi下部ツールバーへ移動しました。"],
    ["You can't use this tab style!", "このタブスタイルは使用できません"],
    ["We've reverted your tab style to Proton. To use other tab styles, switch to the Classic tab design in settings.", "タブスタイルをProtonへ戻しました。ほかのスタイルを使うには、設定でクラシックタブデザインへ切り替えてください。"],
    ["Open in Glimpse...", "Glimpseで開く…"],
    ["You are viewing this tab in Glimpse mode.", "このタブをGlimpseモードで表示しています。"],
    ["Glimpse Chain!", "Glimpseチェーン"],
    ["Unknown site", "不明なサイト"],
    ["Unknown", "不明"],
    ["Unknown artist", "不明なアーティスト"],
    ["LIVE", "ライブ"],
    ["Clear", "消去"],

    // Startup messages and recovery UI.
    ["when the natsumi is browser", "Natsumiこそブラウザー"],
    ["Have you riced your browser today?", "今日はブラウザーをカスタマイズしましたか？"],
    ["nya :3", "にゃー :3"],
    ["stay hydrated!!!1", "水分補給を忘れずに！！！1"],
    ["quotes? in my browser???", "ブラウザーに名言？？？"],
    ["Eat ice cream for a huge buff.", "アイスクリームを食べると大幅パワーアップ。"],
    ["Natsumi is your browser mod. Good choice.", "NatsumiはあなたのブラウザーModです。いい選択ですね。"],
    ["Something went wrong", "問題が発生しました"],
    ["Accept the risks and continue", "リスクを承知して続行"],
    ["Restart and clear startup cache", "再起動して起動時キャッシュを消去"],
    ["Your browser could not load Natsumi's CSS properly. A lot of things (possibly everything) may not work as expected.", "ブラウザーでNatsumiのCSSを正しく読み込めませんでした。多くの機能（場合によってはすべて）が正常に動作しない可能性があります。"],
    ["Please check if Natsumi has been installed correctly.", "Natsumiが正しくインストールされているか確認してください。"],
    ["Restart to use Natsumi", "Natsumiを使用するため再起動"],
    ["Your browser had custom CSS disabled, so Natsumi enabled it automatically.", "カスタムCSSが無効だったため、Natsumiが自動的に有効化しました。"],
    ["Please restart your browser to use Natsumi.", "Natsumiを使用するにはブラウザーを再起動してください。"],
    ["Natsumi's CSS seems to have loaded but doesn't seem to have completed loading. You can ignore this warning, but some things may not work as expected.", "NatsumiのCSSは読み込まれたようですが、完了していない可能性があります。この警告は無視できますが、一部が正常に動作しないことがあります。"],
    ["why would you do that", "なぜそんなことを…"],
    ["did you seriously open a browser window INSIDE A BROWSER WINDOW??????", "本当にブラウザーの中でブラウザーウィンドウを開いたのですか？？？？？？"],
    ["just...close this tab and don't reopen it so you don't mess anything up", "このタブを閉じて、問題が起きないよう再度開かないでください"],

    // Installed mod descriptions and preference labels.
    ["Make your zen music bar better.", "Zenのミュージックバーを使いやすくします。"],
    ["Make popups UI menu transparent with custom settings.", "ポップアップUIを好みに合わせて透明化します。"],
    ["Improve your context menu by adding icons, folding redundant menu items, and more", "コンテキストメニューへアイコンや折りたたみ機能などを追加します。"],
    ["Customizable URL bar with animations.", "アニメーション付きのカスタマイズ可能なURLバーです。"],
    ["Cleans up popup panels & extensions with optional dividers, compact buttons, and customizable hover colors. Supports using Zen Browser’s primary color or manual light/dark hover colors with conditional preferences.", "区切り線、コンパクトなボタン、ホバー色の設定でポップアップと拡張機能パネルを整理します。"],
    ["Welcome to your personal internet.", "自分らしいインターネットへようこそ。"],
    ["Enable/Disable Feature", "機能を有効／無効にする"],
    ["Always Extend Music Bar", "ミュージックバーを常に展開"],
    ["Hide Music Info", "楽曲情報を隠す"],
    ["Hide Progress Bar", "進行バーを隠す"],
    ["Hide Control Bar", "操作バーを隠す"],
    ["Hide Particles", "パーティクルを隠す"],
    ["Custom Background Color", "カスタム背景色"],
    ["Enable/Disable Transparent Mode", "透明モードを有効／無効にする"],
    ["Use default Zen Browser Color (Will override the custom color below)", "Zen Browserの既定色を使用（下のカスタム色より優先）"],
    ["Custom color for the component (should be on srgb format)", "コンポーネントのカスタム色（sRGB形式）"],
    ["Custom blur for the component", "コンポーネントのぼかし"],
    ["Custom transparent percentage", "透明度"],
    ["Custom left sidebar height percentage (default zen is 100%)", "左サイドバーの高さ（Zenの既定値は100%）"],
    ["Implement custom height only on collapsed sidebar (recommended)", "折りたたみ時だけカスタム高さを適用（推奨）"],
    ["Scale animation (put 1 to disable scaling, recommended: 0.98)", "拡大縮小アニメーション（1で無効、推奨: 0.98）"],
    ["Custom Background Blur (put 0px to disable blur)", "背景のぼかし（0pxで無効）"],
    ["Custom Background Brightness (put 1 to disable brightness)", "背景の明るさ（1で補正なし）"],
    ["Custom Border Radius", "角丸の大きさ"],
    ["Enable/Disable Tidy Popup", "Tidy Popupを有効／無効にする"],
    ["Keep divider lines", "区切り線を残す"],
    ["Enable/Disable custom hover color", "カスタムホバー色を有効／無効にする"],
    ["Use color from Zen Browser (will override the custom hover color below)", "Zen Browserの色を使用（下のカスタムホバー色より優先）"],
    ["Button color when hovered (Light mode)", "ホバー時のボタン色（ライトモード）"],
    ["Button color when hovered (Dark mode)", "ホバー時のボタン色（ダークモード）"],
    ["Enable/Disable Tidy Extension", "Tidy Extensionを有効／無効にする"],
    ["Enable/Disable Center Bookmark Bar", "ブックマークバーの中央寄せを有効／無効にする"],

    // Context Menu Icons preferences.
    ["⚙️ Context Menu Icons (CMI) Settings", "⚙️ Context Menu Icons（CMI）の設定"],
    ["📚 Switch Icon package", "📚 アイコンパッケージを切り替える"],
    ["Disable icons", "アイコンを無効にする"],
    ["Default (FluentUI)", "既定（FluentUI）"],
    ["📚 Are you using Firefox?", "📚 使用中のブラウザー"],
    ["📄 Menu Style", "📄 メニュースタイル"],
    ["✨ Disable Better-Context-Menu", "✨ Better-Context-Menuを無効にする"],
    ["✨ Disable Hover Activates Gradient Effect of Better-Context-Menu", "✨ Better-Context-Menuのホバーグラデーションを無効にする"],
    ["✨ Enable CMI fold menu JS. (This will enable you to easily fold the menu items you don't want by hotkey. See github for more function guide)", "✨ CMIのメニュー折りたたみJavaScriptを有効にする（不要な項目をホットキーで隠せます。詳細はGitHubを参照）"],
    ["🛠️ Add/Remove/Sort the folded menu items", "🛠️ 折りたたむメニュー項目の追加／削除／並べ替え"],
    ["Can use hotkeys to adding quikly id.", "ホットキーでIDをすばやく追加できます。"],
    ["✂️ Hide the inactive items in tab-Context-Menu (Enabling to make menu more concise)", "✂️ タブのコンテキストメニューで無効な項目を隠す"],
    ["✂️ Hide the inactive items in ContentArea-Context-Menu (BETA)", "✂️ コンテンツ領域のコンテキストメニューで無効な項目を隠す（ベータ）"],
    ["💡 Add grayscale filter to extensions icons of context-menu", "💡 コンテキストメニューの拡張機能アイコンをグレースケール表示"],
    ["Opacity of menu separator (Value range: 0~1, default: 0.5)", "メニュー区切り線の不透明度（0～1、既定値: 0.5）"],
    ["🔖 Bookmark bar style", "🔖 ブックマークバーのスタイル"],
    ["📏 Center bookmark toolbar items", "📏 ブックマークツールバーの項目を中央揃え"],
    ["📁 Hidden bookmark folder icons (Enable to make bookmark toolbar more concise)", "📁 ブックマークフォルダーのアイコンを隠す"],
    ["👁️ Hide the other elements of the bookmark toolbar", "👁️ ブックマークツールバーのほかの要素を隠す"],
    ["👁️ Hidden 'Open All in Tabs' item in Bookmark page (Enable to improve the bookmark page. This menu item is rarely used and is not available in most browsers. You can safely enable it. )", "👁️ ブックマークページの「すべてのタブで開く」を隠す（通常は安全に有効化できます）"],
    ["No change", "変更しない"],
    ["Hide Favcons", "ファビコンを隠す"],
    ["Hide Bookmark Names", "ブックマーク名を隠す"],
    ["Hide All (not suggest)", "すべて隠す（非推奨）"],
    ["✨ Automatically hide the bookmark bar", "✨ ブックマークバーを自動的に隠す"],
    ["Disable", "無効"],
    ["Display while hover the toolbar", "ツールバーのホバー中に表示"],
    ["Display while search", "検索中に表示"],
    ["Display in both cases", "どちらの場合も表示"],
    ["✨ Use JS to improve the auto-hide bookmark bar feature ( Recommended, Support drag link event and touch )", "✨ JavaScriptでブックマークバーの自動非表示を改善（推奨。リンクのドラッグとタッチ操作に対応）"],
    ["🧩 Other Preferences", "🧩 その他の設定"],
    ["🔍 Restore the button located on the right side of the address bar that is used to initiate the search function ( It's hidden by default Zen. Enable it if you need it. )", "🔍 アドレスバー右側の検索開始ボタンを復元する"],
    ["⚙️ Customize the margin of the context menu", "⚙️ コンテキストメニューの余白を調整"],
    ["⚠️: 1. Please modify the following settings with caution, as they may affect the normal operation of CMI. 2. These settings are only for self-correction when your context menu displays any abnormality due to CMI. 3. To restore or view default settings, clear the corresponding text input box.", "⚠️: 1. 以下の設定はCMIの動作へ影響するため慎重に変更してください。2. CMIによってコンテキストメニューに問題が起きた場合の調整専用です。3. 既定値へ戻す、または確認するには対応する入力欄を空にしてください。"],
    ["Global", "全体"],
    ["[Global]The left margin of the text in the Menu of Container-Tabs", "［全体］コンテナータブのメニュー文字列の左余白"],
    ["FluentUl", "FluentUI"],
    ["The left margin of the checkmark icon in normal circumstances", "通常時のチェックアイコンの左余白"],
    ["The left margin of the checkmark icon after the menu item is checked", "選択時のチェックアイコンの左余白"],
    ["The right margin of the checkmark icon in normal circumstances", "通常時のチェックアイコンの右余白"],
    ["The right margin of the checkmark icon after the menu item is checked", "選択時のチェックアイコンの右余白"],
    ["When a checkmark item is selected among the context menu items, the margins of the other unselected menu items will be adjusted accordingly.", "チェック項目を選択したとき、未選択項目の余白も合わせて調整します。"],
    ["☑️ Optional: Advanced customization - The left margin of icons from browser extension in context menu", "☑️ 任意の詳細設定: コンテキストメニューにある拡張機能アイコンの左余白"],
    ["☑️ Optional: Advanced customization - The left margin of menu text in context menu(This will simultaneously modify the margin rules that have already been in effect for CMI. You can re-adjust the margin rules of CMI)", "☑️ 任意の詳細設定: コンテキストメニュー文字列の左余白（CMIで適用済みの余白規則も同時に変更します）"],
    ["☑️ Optional: Advanced customization - The left margin of FluentUI icons in context menu", "☑️ 任意の詳細設定: コンテキストメニューにあるFluentUIアイコンの左余白"],
    ["☑️ Optional: Advanced customization - The left margin of FluentUI menu text in context menu", "☑️ 任意の詳細設定: コンテキストメニューにあるFluentUI文字列の左余白"],
    ["☑️ Optional: Advanced customization - The left margin of ZenUI icons in context menu", "☑️ 任意の詳細設定: コンテキストメニューにあるZenUIアイコンの左余白"],
    ["☑️ Optional: Advanced customization - The left margin of ZenUI menu text in context menu", "☑️ 任意の詳細設定: コンテキストメニューにあるZenUI文字列の左余白"],
    ["default: 30px", "既定値: 30px"],
    ["default: 24px", "既定値: 24px"],
    ["default: 12px", "既定値: 12px"],
    ["default: 10px", "既定値: 10px"],
    ["default: 8px", "既定値: 8px"],
    ["default: 6px", "既定値: 6px"],
    ["default: 0px(Disbale)", "既定値: 0px（無効）"],
    ["( ✅ This option is merely verifies dependency configuration. Keep it enabled if you want to use CMI normally. )", "（✅ 依存設定の確認用です。CMIを正常に使うには有効のままにしてください）"],

    // Shortcut categories and actions.
    ["Toggle Compact Mode", "コンパクトモードを切り替え"],
    ["Toggle Compact Sidebar", "コンパクトサイドバーを切り替え"],
    ["Toggle Compact Navbar", "コンパクトナビゲーションバーを切り替え"],
    ["Close Glimpse Tab", "Glimpseタブを閉じる"],
    ["Expand Glimpse Tab", "Glimpseタブを展開"],
    ["Next Glimpse Tab", "次のGlimpseタブ"],
    ["Previous Glimpse Tab", "前のGlimpseタブ"],
    ["Toggle Glimpse Chaining", "Glimpseチェーンを切り替え"],
    ["Initiate Glimpse Chain", "Glimpseチェーンを開始"],
    ["Open Glimpse Launcher", "Glimpseランチャーを開く"],
    ["Split View", "分割表示"],
    ["Split Tabs", "タブを分割"],
    ["Unsplit Tabs", "タブ分割を解除"],
    ["Navigation", "ナビゲーション"],
    ["Back", "戻る"],
    ["Back (alt)", "戻る（別操作）"],
    ["Forward", "進む"],
    ["Forward (alt)", "進む（別操作）"],
    ["Home", "ホーム"],
    ["Open File", "ファイルを開く"],
    ["Reload", "再読み込み"],
    ["Reload (override cache)", "キャッシュを無視して再読み込み"],
    ["Stop", "停止"],
    ["Page Options", "ページ操作"],
    ["Copy Current URL", "現在のURLをコピー"],
    ["Copy Current URL as Markdown", "現在のURLをMarkdown形式でコピー"],
    ["Print", "印刷"],
    ["Save Page As", "名前を付けてページを保存"],
    ["Zoom In", "拡大"],
    ["Zoom Out", "縮小"],
    ["Zoom Reset", "ズームをリセット"],
    ["Edit Controls", "編集操作"],
    ["Copy", "コピー"],
    ["Cut", "切り取り"],
    ["Paste", "貼り付け"],
    ["Select All", "すべて選択"],
    ["Undo", "元に戻す"],
    ["Redo", "やり直す"],
    ["Search & Find", "検索"],
    ["Focus Search", "検索へフォーカス"],
    ["Focus Search (alt)", "検索へフォーカス（別操作）"],
    ["Focus Address Bar", "アドレスバーへフォーカス"],
    ["Find in This Page", "ページ内検索"],
    ["Find Again", "次を検索"],
    ["Find Previous", "前を検索"],
    ["Windows & Tabs", "ウィンドウとタブ"],
    ["Close Tab", "タブを閉じる"],
    ["Close Unpinned Tabs", "未ピン留めタブを閉じる"],
    ["Close Window", "ウィンドウを閉じる"],
    ["Select Last Tab", "最後のタブを選択"],
    ["Mute/Unmute Tab", "タブのミュートを切り替え"],
    ["New Tab", "新しいタブ"],
    ["New Window", "新しいウィンドウ"],
    ["New Private Window", "新しいプライベートウィンドウ"],
    ["Toggle Sidebar", "サイドバーを切り替え"],
    ["Reopen last closed tab or window", "最後に閉じたタブまたはウィンドウを開き直す"],
    ["Reopen last closed window", "最後に閉じたウィンドウを開き直す"],
    ["History", "履歴"],
    ["Show History Sidebar", "履歴サイドバーを表示"],
    ["Clear Recent History", "最近の履歴を消去"],
    ["Bookmarks", "ブックマーク"],
    ["Bookmark All Tabs", "すべてのタブをブックマーク"],
    ["Bookmark This Page", "このページをブックマーク"],
    ["Show Bookmarks Sidebar", "ブックマークサイドバーを表示"],
    ["Toggle Bookmarks Toolbar", "ブックマークツールバーを切り替え"],
    ["Show All Bookmarks in Library", "ライブラリーですべてのブックマークを表示"],
    ["Tools", "ツール"],
    ["Open Downloads", "ダウンロードを開く"],
    ["Open Add-ons Manager", "アドオンマネージャーを開く"],
    ["Take a Screenshot", "スクリーンショットを撮る"],
    ["Show Command Palette", "コマンドパレットを表示"],
    ["Workspaces", "ワークスペース"],
    ["Next Workspace", "次のワークスペース"],
    ["Previous Workspace", "前のワークスペース"],
    ["Developer Tools", "開発ツール"],
    ["Toggle Developer Tools", "開発ツールを切り替え"],
    ["Web Console", "ウェブコンソール"],
    ["Inspector", "インスペクター"],
    ["Debugger", "デバッガー"],
    ["Network Monitor", "ネットワークモニター"],
    ["Style Editor", "スタイルエディター"],
    ["Performance", "パフォーマンス"],
    ["Storage", "ストレージ"],
    ["DOM Inspector", "DOMインスペクター"],
    ["Responsive Design View", "レスポンシブデザインモード"],
    ["Other", "その他"],
    ["Toggle Browser Layout", "ブラウザーレイアウトを切り替え"],
    ["Toggle Vertical Tabs", "縦型タブを切り替え"],
    ["Enter Full Screen", "全画面表示にする"],
    ["Exit Full Screen", "全画面表示を終了"],
    ["Toggle Reader Mode", "リーダービューを切り替え"],
  ]);

  const translatedAttributes = [
    "aria-label",
    "label",
    "message",
    "placeholder",
    "text",
    "title",
    "tooltiptext",
  ];

  const dynamicTranslations = [
    [/^Version (.+)$/u, (_match, version) => `バージョン ${version}`],
    [/^Running on Firefox (.+)$/u, (_match, version) => `Firefox ${version} 上で動作中`],
    [/^Running on (.+)$/u, (_match, target) => `${target} 上で動作中`],
    [/^Update to (.+)$/u, (_match, version) => `${version}へ更新`],
    [/^Welcome to Natsumi, (.+)$/u, (_match, name) => `Natsumiへようこそ、${name}`],
    [/^Select Tab ([1-8])$/u, (_match, number) => `タブ${number}を選択`],
    [/^Conflicts with: (.+)$/u, (_match, shortcut) => `競合するショートカット: ${shortcut}`],
    [/^You're currently on Firefox (.+)\. Natsumi requires Firefox (.+)\.$/u,
      (_match, current, required) => `現在のFirefoxは${current}です。NatsumiにはFirefox ${required}が必要です。`],
    [/^Natsumi is incompatible with (.+)\.$/u,
      (_match, browser) => `Natsumiは${browser}に対応していません。`],
  ];

  function translateCore(value) {
    const direct = translations.get(value);
    if (direct !== undefined) {
      return direct;
    }

    for (const [pattern, replacement] of dynamicTranslations) {
      if (pattern.test(value)) {
        return value.replace(pattern, replacement);
      }
    }

    return value;
  }

  function translateValue(value) {
    const leading = value.match(/^\s*/u)?.[0] ?? "";
    const trailing = value.match(/\s*$/u)?.[0] ?? "";
    const coreEnd = value.length - trailing.length;
    const core = value.slice(leading.length, coreEnd).replace(/\s+/gu, " ");

    if (!core) {
      return value;
    }

    const translated = translateCore(core);
    return translated === core ? value : `${leading}${translated}${trailing}`;
  }

  const explicitScopeIds = new Set(["toolbar-context-edit-theme"]);
  const dynamicDataSelector = [
    ".natsumi-miniplayer-site-name",
    ".natsumi-miniplayer-title-container",
    ".natsumi-miniplayer-author-container",
    ".natsumi-miniplayer-title",
    ".natsumi-miniplayer-artist",
    "#natsumi-workspace-indicator-name",
    "#natsumi-glimpse-launcher-input-autocomplete",
    "#natsumi-glimpse-launcher-search",
    "#natsumiFontsGroup option:not([value='default'])",
    ".natsumi-custom-theme-workspace-selector option:not([value='default'])",
    "#natsumi-pinned-toolbar > :not([id*='natsumi']):not([class*='natsumi'])",
    "#natsumi-top-toolbar > :not([id*='natsumi']):not([class*='natsumi'])",
    "#natsumi-bottom-toolbar > :not([id*='natsumi']):not([class*='natsumi'])",
  ].join(",");
  const discoveredRoots = new WeakSet();
  const localizedRoots = new WeakSet();
  const discoveryTimers = [];
  let discoveryObserver;
  let localizationObserver;

  function isLocalizationScope(element) {
    const id = (element.id ?? "").toLowerCase();
    const className = (element.getAttribute?.("class") ?? "").toLowerCase();
    const category = element.getAttribute?.("data-category") ?? "";

    return id.includes("natsumi")
      || className.split(/\s+/u).some((name) => name.startsWith("natsumi-"))
      || category.startsWith("paneNatsumi")
      || category === "paneSineMods"
      || explicitScopeIds.has(element.id);
  }

  function closestComposed(element, selector) {
    let current = element;
    while (current) {
      const match = current.closest(selector);
      if (match) {
        return match;
      }

      const root = current.getRootNode();
      current = root instanceof ShadowRoot ? root.host : null;
    }

    return null;
  }

  function shouldTranslate(node, value) {
    const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
    if (!element) {
      return true;
    }

    if (closestComposed(element, dynamicDataSelector)) {
      return false;
    }

    if (closestComposed(element, ".natsumi-file-current")) {
      const normalized = value.trim().replace(/\s+/gu, " ");
      return normalized === "No image selected"
        || normalized === "No image uploaded"
        || normalized === "No audio selected";
    }

    return true;
  }

  function translateTextNode(node) {
    if (!shouldTranslate(node, node.nodeValue ?? "")) {
      return;
    }

    const translated = translateValue(node.nodeValue ?? "");
    if (translated !== node.nodeValue) {
      node.nodeValue = translated;
    }
  }

  function translateElement(element) {
    for (const attribute of translatedAttributes) {
      if (!element.hasAttribute?.(attribute)) {
        continue;
      }

      const current = element.getAttribute(attribute);
      if (!shouldTranslate(element, current)) {
        continue;
      }

      const translated = translateValue(current);
      if (translated !== current) {
        element.setAttribute(attribute, translated);
      }
    }

    if (element.shadowRoot) {
      observeLocalizedRoot(element.shadowRoot);
    }
  }

  function translateSubtree(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      translateTextNode(node);
      return;
    }

    if (node.nodeType === Node.ELEMENT_NODE) {
      translateElement(node);
    }

    for (const child of Array.from(node.childNodes ?? [])) {
      translateSubtree(child);
    }
  }

  localizationObserver = new MutationObserver((records) => {
    for (const record of records) {
      if (record.type === "characterData") {
        translateTextNode(record.target);
      } else if (record.type === "attributes") {
        translateElement(record.target);
      } else {
        for (const node of record.addedNodes) {
          translateSubtree(node);
        }
      }
    }
  });

  function observeLocalizedRoot(root) {
    if (localizedRoots.has(root)) {
      return;
    }

    localizedRoots.add(root);
    translateSubtree(root);
    localizationObserver.observe(root, {
      attributes: true,
      attributeFilter: translatedAttributes,
      characterData: true,
      childList: true,
      subtree: true,
    });
  }

  function discoverScopes(node) {
    if (node.nodeType === Node.ELEMENT_NODE) {
      if (isLocalizationScope(node)) {
        observeLocalizedRoot(node);
        return;
      }

      if (node.shadowRoot) {
        observeDiscoveryRoot(node.shadowRoot);
      }
    }

    for (const child of Array.from(node.childNodes ?? [])) {
      discoverScopes(child);
    }
  }

  function observeDiscoveryRoot(root) {
    if (discoveredRoots.has(root)) {
      return;
    }

    discoveredRoots.add(root);
    discoverScopes(root);
    discoveryObserver.observe(root, {
      attributes: true,
      attributeFilter: ["class", "data-category", "id"],
      childList: true,
      subtree: true,
    });
  }

  discoveryObserver = new MutationObserver((records) => {
    for (const record of records) {
      if (record.type === "attributes") {
        discoverScopes(record.target);
        continue;
      }

      for (const node of record.addedNodes) {
        discoverScopes(node);
      }
    }
  });

  observeDiscoveryRoot(document);

  // Natsumi's theme editor uses chrome-window alerts instead of DOM nodes.
  // Translate only the exact known messages and leave all other alerts intact.
  const nativeAlert = window.alert;
  const translatedAlert = (message) => nativeAlert.call(window, translateCore(String(message)));
  window.alert = translatedAlert;

  // Custom elements can attach shadow roots after their host is inserted.
  for (const delay of [0, 50, 250, 1000]) {
    discoveryTimers.push(setTimeout(() => discoverScopes(document), delay));
  }

  let cleanedUp = false;
  const cleanup = () => {
    if (cleanedUp) {
      return;
    }

    cleanedUp = true;
    discoveryObserver.disconnect();
    localizationObserver.disconnect();
    for (const timer of discoveryTimers) {
      clearTimeout(timer);
    }
    if (window.alert === translatedAlert) {
      window.alert = nativeAlert;
    }
    if (window[cleanupKey] === cleanup) {
      delete window[cleanupKey];
    }
    window.removeEventListener("unload", cleanup);
  };

  window[cleanupKey] = cleanup;
  window.addEventListener("unload", cleanup, { once: true });
}

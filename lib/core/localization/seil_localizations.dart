import 'package:flutter/widgets.dart';

class SeilLocalizations {
  const SeilLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<SeilLocalizations> delegate =
      _SeilLocalizationsDelegate();

  static SeilLocalizations of(BuildContext context) {
    return Localizations.of<SeilLocalizations>(context, SeilLocalizations) ??
        const SeilLocalizations(Locale('en'));
  }

  static const supportedLocales = [
    Locale('en'),
    Locale('ko'),
    Locale('ja'),
    Locale('zh'),
  ];

  String get _languageCode {
    final code = locale.languageCode.toLowerCase();
    return switch (code) {
      'ko' || 'ja' || 'zh' => code,
      _ => 'en',
    };
  }

  String get appTitle => 'Seil';

  String get initializingFailed => _t(
        en: 'Initialization failed',
        ko: '초기화 실패',
        ja: '初期化に失敗しました',
        zh: '初始化失败',
      );

  String get settings => _t(
        en: 'Settings',
        ko: '설정',
        ja: '設定',
        zh: '设置',
      );

  String get account => _t(
        en: 'Account',
        ko: '계정',
        ja: 'アカウント',
        zh: '账户',
      );

  String get changePassword => _t(
        en: 'Change password',
        ko: '비밀번호 변경',
        ja: 'パスワードを変更',
        zh: '修改密码',
      );

  String get userManagement => _t(
        en: 'User management',
        ko: '사용자 관리',
        ja: 'ユーザー管理',
        zh: '用户管理',
      );

  String get addUser => _t(
        en: 'Add user',
        ko: '사용자 추가',
        ja: 'ユーザーを追加',
        zh: '添加用户',
      );

  String get adminOnlyUserManagement => _t(
        en: 'Only administrators can manage users.',
        ko: '관리자만 사용자를 관리할 수 있습니다.',
        ja: 'ユーザー管理は管理者のみ利用できます。',
        zh: '只有管理员可以管理用户。',
      );

  String get delete => _t(
        en: 'Delete',
        ko: '삭제',
        ja: '削除',
        zh: '删除',
      );

  String get security => _t(
        en: 'Security',
        ko: '보안',
        ja: 'セキュリティ',
        zh: '安全',
      );

  String get keysAndPasswords => _t(
        en: 'Keys and passwords',
        ko: '키와 비밀번호',
        ja: 'キーとパスワード',
        zh: '密钥和密码',
      );

  String get secretsStorageDescription => _t(
        en: 'SSH secrets are stored in Android Keystore or iOS Keychain.',
        ko: 'SSH secret은 Android Keystore 또는 iOS Keychain에 저장됩니다.',
        ja: 'SSH secret は Android Keystore または iOS Keychain に保存されます。',
        zh: 'SSH secret 存储在 Android Keystore 或 iOS Keychain 中。',
      );

  String get appLoginPassword => _t(
        en: 'App login password',
        ko: '앱 로그인 비밀번호',
        ja: 'アプリログインパスワード',
        zh: '应用登录密码',
      );

  String get appLoginPasswordDescription => _t(
        en: 'Disabled by default. When enabled, Seil asks for a password on startup.',
        ko: '기본값은 비활성화입니다. 켜면 시작 화면에서 비밀번호를 요구합니다.',
        ja: 'デフォルトでは無効です。有効にすると起動時にパスワードを要求します。',
        zh: '默认关闭。启用后，启动时需要输入密码。',
      );

  String get lowEndMode => _t(
        en: 'Low-end mode',
        ko: '저사양 모드',
        ja: '低スペックモード',
        zh: '低性能模式',
      );

  String get lowEndModeDescription => _t(
        en: 'Reduces terminal render range and visual effects to prioritize input responsiveness.',
        ko: '터미널 기본 렌더 범위와 시각 효과를 줄여 입력 반응 속도를 우선합니다.',
        ja: '入力応答を優先するため、ターミナルの描画範囲と視覚効果を抑えます。',
        zh: '减少终端渲染范围和视觉效果，优先提升输入响应速度。',
      );

  String get language => _t(
        en: 'Language',
        ko: '언어',
        ja: '言語',
        zh: '语言',
      );

  String get chooseLanguage => _t(
        en: 'Choose language',
        ko: '언어 선택',
        ja: '言語を選択',
        zh: '选择语言',
      );

  String get systemLanguage => _t(
        en: 'System language',
        ko: '시스템 언어',
        ja: 'システム言語',
        zh: '系统语言',
      );

  String languageLabel(String code) {
    return switch (code) {
      'en' => 'English',
      'ja' => '日本語',
      'ko' => '한국어',
      'zh' => '中文',
      _ => systemLanguage,
    };
  }

  String get info => _t(
        en: 'Info',
        ko: '정보',
        ja: '情報',
        zh: '信息',
      );

  String get aboutSeil => _t(
        en: 'About Seil',
        ko: 'About Seil',
        ja: 'Seil について',
        zh: '关于 Seil',
      );

  String get developedByZarathu => _t(
        en: 'Developed by Zarathu',
        ko: 'Zarathu에서 개발',
        ja: 'Zarathu が開発',
        zh: '由 Zarathu 开发',
      );

  String get aboutDescription => _t(
        en: 'Mobile SSH terminal and SFTP workspace.',
        ko: '모바일 SSH 터미널 및 SFTP 워크스페이스입니다.',
        ja: 'モバイル SSH ターミナルと SFTP ワークスペースです。',
        zh: '移动 SSH 终端和 SFTP 工作区。',
      );

  String get developer => _t(
        en: 'Developer',
        ko: '개발자',
        ja: '開発者',
        zh: '开发者',
      );

  String get company => _t(
        en: 'Company',
        ko: '회사',
        ja: '会社',
        zh: '公司',
      );

  String get openSource => _t(
        en: 'Open source',
        ko: '오픈소스',
        ja: 'オープンソース',
        zh: '开源',
      );

  String get license => _t(
        en: 'License',
        ko: '라이선스',
        ja: 'ライセンス',
        zh: '许可证',
      );

  String get ok => _t(
        en: 'OK',
        ko: '확인',
        ja: 'OK',
        zh: '确定',
      );

  String get cancel => _t(
        en: 'Cancel',
        ko: '취소',
        ja: 'キャンセル',
        zh: '取消',
      );

  String get save => _t(
        en: 'Save',
        ko: '저장',
        ja: '保存',
        zh: '保存',
      );

  String get remove => _t(
        en: 'Remove',
        ko: '제거',
        ja: '削除',
        zh: '移除',
      );

  String get enable => _t(
        en: 'Enable',
        ko: '활성화',
        ja: '有効化',
        zh: '启用',
      );

  String get change => _t(
        en: 'Change',
        ko: '변경',
        ja: '変更',
        zh: '修改',
      );

  String get newPassword => _t(
        en: 'New password',
        ko: '새 비밀번호',
        ja: '新しいパスワード',
        zh: '新密码',
      );

  String get confirmNewPassword => _t(
        en: 'Confirm new password',
        ko: '새 비밀번호 확인',
        ja: '新しいパスワードの確認',
        zh: '确认新密码',
      );

  String get passwordsDoNotMatch => _t(
        en: 'New passwords do not match.',
        ko: '새 비밀번호가 일치하지 않습니다.',
        ja: '新しいパスワードが一致しません。',
        zh: '新密码不一致。',
      );

  String get currentPassword => _t(
        en: 'Current password',
        ko: '현재 비밀번호',
        ja: '現在のパスワード',
        zh: '当前密码',
      );

  String get userId => _t(
        en: 'Username',
        ko: '아이디',
        ja: 'ユーザー名',
        zh: '用户名',
      );

  String get name => _t(
        en: 'Name',
        ko: '이름',
        ja: '名前',
        zh: '姓名',
      );

  String get password => _t(
        en: 'Password',
        ko: '비밀번호',
        ja: 'パスワード',
        zh: '密码',
      );

  String get add => _t(
        en: 'Add',
        ko: '추가',
        ja: '追加',
        zh: '添加',
      );

  String get copiedLink => _t(
        en: 'Link copied.',
        ko: '링크를 복사했습니다.',
        ja: 'リンクをコピーしました。',
        zh: '链接已复制。',
      );

  String get copyLink => _t(
        en: 'Copy link',
        ko: '링크 복사',
        ja: 'リンクをコピー',
        zh: '复制链接',
      );

  String get bootstrapWithPasswordDescription => _t(
        en: 'Prepare local secure storage with a password of at least 6 digits.',
        ko: '6자리 이상 비밀번호로 로컬 보안 저장소를 준비합니다.',
        ja: '6 桁以上のパスワードでローカルの安全な保存領域を準備します。',
        zh: '使用至少 6 位密码准备本地安全存储。',
      );

  String get bootstrapWithoutPasswordDescription => _t(
        en: 'Prepare a local workspace without a password.',
        ko: '비밀번호 없이 로컬 작업공간을 준비합니다.',
        ja: 'パスワードなしでローカルワークスペースを準備します。',
        zh: '无需密码即可准备本地工作区。',
      );

  String get loginWithPasswordDescription => _t(
        en: 'Open the saved workspace with your password.',
        ko: '비밀번호로 저장된 작업공간을 엽니다.',
        ja: 'パスワードで保存済みワークスペースを開きます。',
        zh: '使用密码打开已保存的工作区。',
      );

  String get loginWithoutPasswordDescription => _t(
        en: 'Open the saved workspace without a password.',
        ko: '비밀번호 없이 저장된 작업공간을 엽니다.',
        ja: 'パスワードなしで保存済みワークスペースを開きます。',
        zh: '无需密码即可打开已保存的工作区。',
      );

  String get createAdmin => _t(
        en: 'Create admin',
        ko: '관리자 생성',
        ja: '管理者を作成',
        zh: '创建管理员',
      );

  String get userLogin => _t(
        en: 'User login',
        ko: '사용자 로그인',
        ja: 'ユーザーログイン',
        zh: '用户登录',
      );

  String get loginPasswordCanBeEnabled => _t(
        en: 'Login password can be enabled in Settings.',
        ko: '로그인 비밀번호는 설정에서 활성화할 수 있습니다.',
        ja: 'ログインパスワードは設定で有効にできます。',
        zh: '可在设置中启用登录密码。',
      );

  String get start => _t(
        en: 'Start',
        ko: '시작',
        ja: '開始',
        zh: '开始',
      );

  String get login => _t(
        en: 'Log in',
        ko: '로그인',
        ja: 'ログイン',
        zh: '登录',
      );

  String get open => _t(
        en: 'Open',
        ko: '열기',
        ja: '開く',
        zh: '打开',
      );

  String get servers => _t(
        en: 'Servers',
        ko: '서버',
        ja: 'サーバー',
        zh: '服务器',
      );

  String get workspace => _t(
        en: 'Workspace',
        ko: '작업 공간',
        ja: 'ワークスペース',
        zh: '工作区',
      );

  String get newConnection => _t(
        en: 'New connection',
        ko: '새 연결',
        ja: '新規接続',
        zh: '新建连接',
      );

  String get serverSessionSelection => _t(
        en: 'Server / session selection',
        ko: '서버 / 세션 선택',
        ja: 'サーバー / セッション選択',
        zh: '服务器 / 会话选择',
      );

  String get addSessionFromSavedServer => _t(
        en: 'Add a new session from a saved server',
        ko: '저장된 서버로 새 세션 추가',
        ja: '保存済みサーバーから新規セッションを追加',
        zh: '从已保存服务器添加新会话',
      );

  String get connectedServers => _t(
        en: 'Connected servers',
        ko: '연결된 서버',
        ja: '接続中のサーバー',
        zh: '已连接服务器',
      );

  String workspaceCount(int count) => _t(
        en: '$count workspace${count == 1 ? '' : 's'}',
        ko: '작업 $count개',
        ja: 'ワークスペース $count 件',
        zh: '$count 个工作区',
      );

  String get noConnectedServers => _t(
        en: 'No connected servers.',
        ko: '연결된 서버가 없습니다.',
        ja: '接続中のサーバーはありません。',
        zh: '没有已连接服务器。',
      );

  String get activeSessions => _t(
        en: 'Active sessions',
        ko: '활성 세션',
        ja: 'アクティブセッション',
        zh: '活动会话',
      );

  String activeBadge(int count) => _t(
        en: '$count active',
        ko: '$count active',
        ja: '$count active',
        zh: '$count active',
      );

  String get savedServers => _t(
        en: 'Saved servers',
        ko: '저장된 서버',
        ja: '保存済みサーバー',
        zh: '已保存服务器',
      );

  String savedBadge(int count) => _t(
        en: '$count saved',
        ko: '$count saved',
        ja: '$count saved',
        zh: '$count saved',
      );

  String get noSavedConnections => _t(
        en: 'No saved connection templates. Add a new connection to see it here.',
        ko: '저장된 연결 템플릿이 없습니다. 새 연결을 추가하면 여기에 표시됩니다.',
        ja: '保存済み接続テンプレートはありません。新規接続を追加するとここに表示されます。',
        zh: '没有已保存的连接模板。添加新连接后会显示在这里。',
      );

  String get noSavedServers => _t(
        en: 'No saved servers.',
        ko: '저장된 서버가 없습니다.',
        ja: '保存済みサーバーはありません。',
        zh: '没有已保存服务器。',
      );

  String get openSessions => _t(
        en: 'Open sessions',
        ko: '열린 세션',
        ja: '開いているセッション',
        zh: '打开的会话',
      );

  String get noOpenSessions => _t(
        en: 'No open sessions.',
        ko: '열린 세션이 없습니다.',
        ja: '開いているセッションはありません。',
        zh: '没有打开的会话。',
      );

  String get addNewTmuxSession => _t(
        en: 'Add new tmux session',
        ko: '새 tmux 세션 추가',
        ja: '新規 tmux セッションを追加',
        zh: '添加新的 tmux 会话',
      );

  String get addNewTmuxSessionDescription => _t(
        en: 'Create a new work session on this server.',
        ko: '이 서버에 새 작업 세션을 만듭니다.',
        ja: 'このサーバーに新しい作業セッションを作成します。',
        zh: '在此服务器上创建新的工作会话。',
      );

  String get chooseTmuxSession => _t(
        en: 'Choose tmux session',
        ko: 'tmux 세션 선택',
        ja: 'tmux セッションを選択',
        zh: '选择 tmux 会话',
      );

  String get chooseTmuxSessionDescription => _t(
        en: 'Choose from existing tmux sessions on the remote server.',
        ko: '원격 서버의 기존 tmux 목록에서 선택합니다.',
        ja: 'リモートサーバー上の既存 tmux 一覧から選択します。',
        zh: '从远程服务器现有 tmux 列表中选择。',
      );

  String get tmuxSessions => _t(
        en: 'tmux sessions',
        ko: 'tmux 세션',
        ja: 'tmux セッション',
        zh: 'tmux 会话',
      );

  String get noTmuxSessionsOrLoading => _t(
        en: 'No existing tmux sessions, or still loading.',
        ko: '기존 tmux 세션이 없거나 조회 중입니다.',
        ja: '既存の tmux セッションがないか、読み込み中です。',
        zh: '没有现有 tmux 会话，或正在加载。',
      );

  String get connectionTemplates => _t(
        en: 'Connection templates',
        ko: '연결 템플릿',
        ja: '接続テンプレート',
        zh: '连接模板',
      );

  String get noExistingSessions => _t(
        en: 'No existing sessions',
        ko: '기존 세션 없음',
        ja: '既存セッションなし',
        zh: '没有现有会话',
      );

  String get existingTmuxSessions => _t(
        en: 'Existing tmux sessions',
        ko: '기존 tmux 세션',
        ja: '既存の tmux セッション',
        zh: '现有 tmux 会话',
      );

  String get queryingTmuxSessions => _t(
        en: 'Querying tmux sessions.',
        ko: 'tmux 세션을 조회하고 있습니다.',
        ja: 'tmux セッションを照会しています。',
        zh: '正在查询 tmux 会话。',
      );

  String get noExistingTmuxSessions => _t(
        en: 'No existing tmux sessions. You can start a new session.',
        ko: '기존 tmux 세션이 없습니다. 새 세션을 시작할 수 있습니다.',
        ja: '既存の tmux セッションはありません。新規セッションを開始できます。',
        zh: '没有现有 tmux 会话。可以启动新会话。',
      );

  String get startTmuxDefaultPath => _t(
        en: 'Start tmux session',
        ko: '기본 경로에서 tmux 세션 시작',
        ja: 'tmux セッションを開始',
        zh: '启动 tmux 会话',
      );

  String get tagSettings => _t(
        en: 'Tag settings',
        ko: '태그 설정',
        ja: 'タグ設定',
        zh: '标签设置',
      );

  String get endSession => _t(
        en: 'End session',
        ko: '세션 종료',
        ja: 'セッションを終了',
        zh: '结束会话',
      );

  String get deleteCurrentTmuxSession => _t(
        en: 'Delete current tmux session',
        ko: '현재 tmux 세션 삭제',
        ja: '現在の tmux セッションを削除',
        zh: '删除当前 tmux 会话',
      );

  String get deleteTmuxSession => _t(
        en: 'Delete tmux session',
        ko: 'tmux 세션 삭제',
        ja: 'tmux セッションを削除',
        zh: '删除 tmux 会话',
      );

  String deleteTmuxSessionMessage(String name) => _t(
        en: 'Delete the $name tmux session?',
        ko: '$name tmux 세션을 삭제합니다.',
        ja: '$name tmux セッションを削除します。',
        zh: '删除 $name tmux 会话？',
      );

  String tmuxTagTitle(String name) => _t(
        en: '$name tag',
        ko: '$name 태그',
        ja: '$name タグ',
        zh: '$name 标签',
      );

  String get tagName => _t(
        en: 'Tag name',
        ko: '태그 이름',
        ja: 'タグ名',
        zh: '标签名称',
      );

  String get refreshSession => _t(
        en: 'Refresh session',
        ko: '세션 새로고침',
        ja: 'セッションを更新',
        zh: '刷新会话',
      );

  String get disconnectCurrentConnection => _t(
        en: 'Disconnect current connection',
        ko: '현재 연결 종료',
        ja: '現在の接続を終了',
        zh: '断开当前连接',
      );

  String get deleteTemplate => _t(
        en: 'Delete template',
        ko: '템플릿 삭제',
        ja: 'テンプレートを削除',
        zh: '删除模板',
      );

  String deleteTemplateMessage(String name) => _t(
        en: 'Delete the $name connection template?',
        ko: '$name 연결 템플릿을 삭제합니다.',
        ja: '$name の接続テンプレートを削除します。',
        zh: '删除 $name 连接模板？',
      );

  String get connect => _t(
        en: 'Connect',
        ko: '연결',
        ja: '接続',
        zh: '连接',
      );

  String get sshPassword => _t(
        en: 'SSH password',
        ko: 'SSH 비밀번호',
        ja: 'SSH パスワード',
        zh: 'SSH 密码',
      );

  String get secret => _t(
        en: 'Secret',
        ko: 'Secret',
        ja: 'Secret',
        zh: 'Secret',
      );

  String get serverActions => _t(
        en: 'Server actions',
        ko: '서버 작업',
        ja: 'サーバー操作',
        zh: '服务器操作',
      );

  String get connecting => _t(
        en: 'Connecting...',
        ko: '연결 중...',
        ja: '接続中...',
        zh: '连接中...',
      );

  String get refresh => _t(
        en: 'Refresh',
        ko: '새로고침',
        ja: '更新',
        zh: '刷新',
      );

  String get loading => _t(
        en: 'Loading',
        ko: '조회 중',
        ja: '読み込み中',
        zh: '加载中',
      );

  String get secretRequired => _t(
        en: 'secret required',
        ko: 'secret 필요',
        ja: 'secret 必須',
        zh: '需要 secret',
      );

  String get quickConnect => _t(
        en: 'quick connect',
        ko: '빠른 연결',
        ja: 'クイック接続',
        zh: '快速连接',
      );

  String get newSshConnection => _t(
        en: 'New SSH connection',
        ko: '새 SSH 연결',
        ja: '新規 SSH 接続',
        zh: '新建 SSH 连接',
      );

  String get label => _t(
        en: 'Label',
        ko: '라벨',
        ja: 'ラベル',
        zh: '标签',
      );

  String get tmuxDefaultHistoryHelper => _t(
        en: 'tmux default is 2,000 lines.',
        ko: 'tmux 기본값은 2000줄입니다.',
        ja: 'tmux のデフォルトは 2000 行です。',
        zh: 'tmux 默认值为 2000 行。',
      );

  String recommendedLines(int count) => _t(
        en: 'Recommended $count lines',
        ko: '권장 $count줄',
        ja: '推奨 $count 行',
        zh: '建议 $count 行',
      );

  String get privateKeyRaw => _t(
        en: 'Private key text',
        ko: 'Private Key 원문',
        ja: 'Private Key 本文',
        zh: 'Private Key 原文',
      );

  String get saveSecretOnDevice => _t(
        en: 'Save secret on this device',
        ko: '기기에 secret 저장',
        ja: 'このデバイスに secret を保存',
        zh: '在此设备保存 secret',
      );

  String get terminal => _t(
        en: 'Terminal',
        ko: '터미널',
        ja: 'ターミナル',
        zh: '终端',
      );

  String get explorer => _t(
        en: 'Explorer',
        ko: '탐색기',
        ja: 'エクスプローラー',
        zh: '文件浏览器',
      );

  String get loadMoreHistory => _t(
        en: 'Load previous content',
        ko: '이전 내용 더보기',
        ja: '以前の内容をさらに表示',
        zh: '加载之前的内容',
      );

  String get zoomOutTerminal => _t(
        en: 'Zoom out terminal',
        ko: '터미널 축소',
        ja: 'ターミナルを縮小',
        zh: '缩小终端',
      );

  String get zoomInTerminal => _t(
        en: 'Zoom in terminal',
        ko: '터미널 확대',
        ja: 'ターミナルを拡大',
        zh: '放大终端',
      );

  String get sendInput => _t(
        en: 'Send input',
        ko: '입력 전송',
        ja: '入力を送信',
        zh: '发送输入',
      );

  String get keyboardMacros => _t(
        en: 'Keyboard macros',
        ko: '키보드 매크로',
        ja: 'キーボードマクロ',
        zh: '键盘宏',
      );

  String get keyboardMacroSettings => _t(
        en: 'Keyboard macro settings',
        ko: '키보드 매크로 설정',
        ja: 'キーボードマクロ設定',
        zh: '键盘宏设置',
      );

  String get keyboardMacroHint => _t(
        en: 'Type F5 to send a function key.',
        ko: 'F5처럼 입력하면 Function 키로 전송됩니다.',
        ja: 'F5 のように入力すると Function キーとして送信されます。',
        zh: '输入 F5 可作为 Function 键发送。',
      );

  String get clear => _t(
        en: 'Clear',
        ko: '비우기',
        ja: 'クリア',
        zh: '清空',
      );

  String get fileInfoUnavailable => _t(
        en: 'Could not load file information.',
        ko: '파일 정보를 불러오지 못했습니다.',
        ja: 'ファイル情報を読み込めませんでした。',
        zh: '无法加载文件信息。',
      );

  String get folder => _t(
        en: 'Folder',
        ko: '폴더',
        ja: 'フォルダ',
        zh: '文件夹',
      );

  String get filePreviewUnsupported => _t(
        en: 'This file type is not supported for in-app preview.',
        ko: '이 파일 형식은 앱 내 미리보기를 지원하지 않습니다.',
        ja: 'このファイル形式はアプリ内プレビューに対応していません。',
        zh: '此文件类型不支持应用内预览。',
      );

  String get previousFolder => _t(
        en: 'Previous folder',
        ko: '이전 폴더',
        ja: '前のフォルダ',
        zh: '上一个文件夹',
      );

  String get parentFolder => _t(
        en: 'Parent folder',
        ko: '상위 폴더',
        ja: '親フォルダ',
        zh: '父文件夹',
      );

  String get startTerminalHere => _t(
        en: 'Start terminal session from current path',
        ko: '현재 경로에서 터미널 세션 시작',
        ja: '現在のパスからターミナルセッションを開始',
        zh: '从当前路径启动终端会话',
      );

  String get upload => _t(
        en: 'Upload',
        ko: '업로드',
        ja: 'アップロード',
        zh: '上传',
      );

  String get newFolder => _t(
        en: 'New folder',
        ko: '새 폴더',
        ja: '新規フォルダ',
        zh: '新建文件夹',
      );

  String get search => _t(
        en: 'Search',
        ko: '검색',
        ja: '検索',
        zh: '搜索',
      );

  String get showHiddenFiles => _t(
        en: 'Show hidden files',
        ko: '숨김 파일 표시',
        ja: '隠しファイルを表示',
        zh: '显示隐藏文件',
      );

  String dirsCount(int count) => _t(
        en: '$count dirs',
        ko: '$count dirs',
        ja: '$count dirs',
        zh: '$count dirs',
      );

  String filesCount(int count) => _t(
        en: '$count files',
        ko: '$count files',
        ja: '$count files',
        zh: '$count files',
      );

  String get emptyDirectory => _t(
        en: 'Empty directory',
        ko: '비어 있는 디렉토리',
        ja: '空のディレクトリ',
        zh: '空目录',
      );

  String get noSearchResults => _t(
        en: 'No search results',
        ko: '검색 결과 없음',
        ja: '検索結果なし',
        zh: '没有搜索结果',
      );

  String uploadedFiles(int count) => _t(
        en: 'Uploaded $count file${count == 1 ? '' : 's'}.',
        ko: '$count개 파일을 업로드했습니다.',
        ja: '$count 件のファイルをアップロードしました。',
        zh: '已上传 $count 个文件。',
      );

  String uploadedAndSkippedFiles(int uploaded, int skipped) => _t(
        en: 'Uploaded $uploaded file${uploaded == 1 ? '' : 's'}, skipped $skipped.',
        ko: '$uploaded개 업로드, $skipped개 건너뜀',
        ja: '$uploaded 件アップロード、$skipped 件スキップ',
        zh: '已上传 $uploaded 个，跳过 $skipped 个',
      );

  String get folderName => _t(
        en: 'Folder name',
        ko: '폴더 이름',
        ja: 'フォルダ名',
        zh: '文件夹名称',
      );

  String get rename => _t(
        en: 'Rename',
        ko: '이름 변경',
        ja: '名前を変更',
        zh: '重命名',
      );

  String get newName => _t(
        en: 'New name',
        ko: '새 이름',
        ja: '新しい名前',
        zh: '新名称',
      );

  String get currentPath => _t(
        en: 'Current path',
        ko: '현재 경로',
        ja: '現在のパス',
        zh: '当前路径',
      );

  String get copy => _t(
        en: 'Copy',
        ko: '복사',
        ja: 'コピー',
        zh: '复制',
      );

  String get copyAll => _t(
        en: 'Copy all',
        ko: '전체 복사',
        ja: 'すべてコピー',
        zh: '全部复制',
      );

  String get copiedAllText => _t(
        en: 'Copied all text.',
        ko: '전체 텍스트를 복사했습니다.',
        ja: '全文をコピーしました。',
        zh: '已复制全部文本。',
      );

  String get preview => _t(
        en: 'Preview',
        ko: '미리보기',
        ja: 'プレビュー',
        zh: '预览',
      );

  String get edit => _t(
        en: 'Edit',
        ko: '편집',
        ja: '編集',
        zh: '编辑',
      );

  String get fileSaved => _t(
        en: 'File saved.',
        ko: '파일을 저장했습니다.',
        ja: 'ファイルを保存しました。',
        zh: '文件已保存。',
      );

  String saveFailed(Object error) => _t(
        en: 'Save failed: $error',
        ko: '저장 실패: $error',
        ja: '保存に失敗しました: $error',
        zh: '保存失败：$error',
      );

  String get enterContent => _t(
        en: 'Enter content',
        ko: '내용 입력',
        ja: '内容を入力',
        zh: '输入内容',
      );

  String editLanguage(String language) => _t(
        en: 'Edit $language',
        ko: '$language 편집',
        ja: '$language を編集',
        zh: '编辑 $language',
      );

  String get noTerminalText => _t(
        en: 'No terminal text output.',
        ko: '출력된 터미널 텍스트가 없습니다.',
        ja: '出力されたターミナルテキストはありません。',
        zh: '没有终端文本输出。',
      );

  String get sort => _t(
        en: 'Sort',
        ko: '정렬',
        ja: '並び替え',
        zh: '排序',
      );

  String get sortByName => _t(
        en: 'Name',
        ko: '이름순',
        ja: '名前順',
        zh: '按名称',
      );

  String get sortByType => _t(
        en: 'Type',
        ko: '유형순',
        ja: '種類順',
        zh: '按类型',
      );

  String get sortByModified => _t(
        en: 'Modified',
        ko: '수정일순',
        ja: '更新日順',
        zh: '按修改日期',
      );

  String get sortByCreated => _t(
        en: 'Created',
        ko: '생성일순',
        ja: '作成日順',
        zh: '按创建日期',
      );

  String get saveAndConnect => _t(
        en: 'Save and connect',
        ko: '저장 후 연결',
        ja: '保存して接続',
        zh: '保存并连接',
      );

  String get hostRequired => _t(
        en: 'Enter a host.',
        ko: 'Host를 입력하세요.',
        ja: 'Host を入力してください。',
        zh: '请输入 Host。',
      );

  String get usernameRequired => _t(
        en: 'Enter a username.',
        ko: 'Username을 입력하세요.',
        ja: 'Username を入力してください。',
        zh: '请输入 Username。',
      );

  String get portInvalid => _t(
        en: 'Enter a port number between 1 and 65535.',
        ko: 'Port는 1부터 65535 사이 숫자로 입력하세요.',
        ja: 'Port は 1 から 65535 までの数値で入力してください。',
        zh: '请输入 1 到 65535 之间的 Port 数字。',
      );

  String get tmuxHistoryInvalid => _t(
        en: 'Enter a tmux history-limit number of at least 1.',
        ko: 'tmux history-limit은 1 이상의 숫자로 입력하세요.',
        ja: 'tmux history-limit は 1 以上の数値で入力してください。',
        zh: 'tmux history-limit 请输入 1 以上的数字。',
      );

  String authModeLabel(Object mode) {
    final name = mode.toString();
    if (name.endsWith('privateKey')) {
      return _t(en: 'private key', ko: '개인 키', ja: '秘密鍵', zh: '私钥');
    }
    if (name.endsWith('agent')) {
      return 'SSH Agent';
    }
    return _t(en: 'password', ko: '비밀번호', ja: 'パスワード', zh: '密码');
  }

  String _t({
    required String en,
    required String ko,
    required String ja,
    required String zh,
  }) {
    return switch (_languageCode) {
      'ko' => ko,
      'ja' => ja,
      'zh' => zh,
      _ => en,
    };
  }
}

class _SeilLocalizationsDelegate
    extends LocalizationsDelegate<SeilLocalizations> {
  const _SeilLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return {'en', 'ko', 'ja', 'zh'}.contains(locale.languageCode);
  }

  @override
  Future<SeilLocalizations> load(Locale locale) async {
    return SeilLocalizations(locale);
  }

  @override
  bool shouldReload(_SeilLocalizationsDelegate old) => false;
}

extension SeilLocalizationsX on BuildContext {
  SeilLocalizations get l10n => SeilLocalizations.of(this);
}

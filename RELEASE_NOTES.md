# Release Notes

## 0.4.0

<ko-KR>
- SSH 연결 보안을 강화했습니다.
- 처음 연결하는 서버의 SSH host key fingerprint를 확인합니다.
- 신뢰한 서버 키는 기기에 저장해 이후 연결 시 자동 검증합니다.
- 저장된 키와 다른 host key가 감지되면 연결을 차단합니다.
</ko-KR>

<en-US>
- Strengthened SSH connection security.
- Added SSH host key fingerprint confirmation for first-time server connections.
- Trusted server keys are saved on the device and verified automatically on later connections.
- Connections are blocked when a saved host key changes.
</en-US>

<zh-CN>
- 加强了 SSH 连接安全性。
- 首次连接服务器时会确认 SSH host key fingerprint。
- 已信任的服务器密钥会保存在设备上，并在之后连接时自动验证。
- 如果检测到已保存的 host key 发生变化，将阻止连接。
</zh-CN>

<ja-JP>
- SSH 接続のセキュリティを強化しました。
- 初めて接続するサーバーの SSH host key fingerprint を確認できるようにしました。
- 信頼したサーバーキーは端末に保存され、以後の接続時に自動で検証されます。
- 保存済みの host key と異なるキーが検出された場合、接続をブロックします。
</ja-JP>

## 0.3.1

<ko-KR>
- 서버 재연결 안정성을 개선했습니다.
- 끊어진 SSH/tmux 세션 복구와 워크스페이스 상태 유지가 더 안정적으로 동작합니다.
- tmux 세션을 빠르게 추가하는 버튼을 추가했습니다.
- 코드 미리보기 및 편집 화면의 가독성을 개선했습니다.
</ko-KR>

<en-US>
- Improved server reconnection reliability.
- Disconnected SSH/tmux sessions now recover more smoothly while preserving workspace state.
- Added a quick button for creating tmux sessions.
- Improved readability in code preview and editing screens.
</en-US>

<zh-CN>
- 改进了服务器重新连接的稳定性。
- 断开的 SSH/tmux 会话现在可以更顺畅地恢复，并保留工作区状态。
- 新增了快速创建 tmux 会话的按钮。
- 提升了代码预览和编辑界面的可读性。
</zh-CN>

<ja-JP>
- サーバー再接続の安定性を改善しました。
- 切断された SSH/tmux セッションの復旧とワークスペース状態の保持がより安定しました。
- tmux セッションをすばやく追加できるボタンを追加しました。
- コードのプレビュー/編集画面の視認性を改善しました。
</ja-JP>

## 0.3.0

<ko-KR>
- 터미널 세션 알림과 백그라운드 세션 유지 동작을 개선했습니다.
- Claude/Codex 터미널의 주의 필요 상태 감지를 추가했습니다.
- 세션 화면의 상태 처리와 안정성을 개선했습니다.
</ko-KR>

<en-US>
- Added terminal session notifications and improved background session retention.
- Added attention-state detection for Claude/Codex terminal sessions.
- Improved session screen state handling and stability.
</en-US>

<zh-CN>
- 改进了终端会话通知和后台会话保持。
- 新增 Claude/Codex 终端需要关注状态的检测。
- 改进了会话界面的状态处理和稳定性。
</zh-CN>

<ja-JP>
- ターミナルセッション通知とバックグラウンドでのセッション維持を改善しました。
- Claude/Codex ターミナルの注意が必要な状態を検出できるようにしました。
- セッション画面の状態処理と安定性を改善しました。
</ja-JP>

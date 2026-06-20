# Frappe Press 部署笔记

- **部署日期**：2026-06-18
- **镜像**：基于 python:3.10-slim-bookworm 构建的自定义镜像
- **Frappe 框架**：miao-Q777/frappe@fc-ci（Press 官方 CI 验证的 fork）
- **关键修正**：Python 版本从 3.12 降为 3.10（python-telegram-bot==13.15 不兼容 3.12）
- **站点**：press.localhost / admin / admin123，已安装 press 应用
- **验证**：curl -H "Host: press.localhost" http://localhost:8082/api/method/ping → {"message":"pong"}
- **暴露端口**：8082
- **构建时间**：约 20 分钟（2 核 8G）
- **镜像大小**：约 2-3 GB
- **已知限制**：未装 Chromium（截图功能不可用）、未配云厂商凭证
- **是否成功**：✅ 是 (Level 3)

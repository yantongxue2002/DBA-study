@echo off
chcp 65001 >nul
title DBA 自动运维平台

echo ============================================
echo   DBA 自动运维平台 - 启动中...
echo ============================================
echo.

REM 检查 Python 是否安装
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 未找到 Python，请先安装 Python 3.9+
    pause
    exit /b 1
)

echo [1/3] 检查依赖...
pip install -r requirements.txt -q
if %errorlevel% neq 0 (
    echo [警告] 依赖安装可能存在异常，尝试继续...
)

echo [2/3] 初始化数据库...
python -c "from app import app; from core.db import db; app.app_context().push(); db.create_all(); print('数据库初始化完成')"

echo [3/3] 启动 Web 服务...
echo.
echo ============================================
echo   平台已启动！
echo   浏览器访问: http://localhost:5000
echo   按 Ctrl+C 停止服务
echo ============================================
echo.

python app.py

pause

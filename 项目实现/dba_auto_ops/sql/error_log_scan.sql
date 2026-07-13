-- ============================================
-- 错误日志关键字扫描 (SQL Server 2019 兼容)
-- 需要 EXECUTE ON xp_readerrorlog 权限
-- 如无权限，采集器会收到错误并报告
-- ============================================

DECLARE @hours_back INT = 24;
DECLARE @search_start DATETIME = DATEADD(hh, -@hours_back, GETDATE());

-- 直接读取错误日志 (不使用 INSERT..EXEC 避免 TRY/CATCH 静默失败)
-- xp_readerrorlog 参数: 日志编号, 日志类型(1=SQL), 搜索文本1, 搜索文本2, 开始时间, 结束时间
EXEC xp_readerrorlog 0, 1, NULL, NULL, @search_start, NULL;

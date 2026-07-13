/**
 * DBA 自动运维平台 - 公共 JavaScript
 */

// 全局工具函数
const DBAOps = {
    /**
     * 通用 API 请求
     */
    async fetchAPI(url, options = {}) {
        try {
            const res = await fetch(url, options);
            const data = await res.json();
            return data;
        } catch (err) {
            console.error(`API 请求失败: ${url}`, err);
            return { success: false, error: err.message };
        }
    },

    /**
     * 格式化字节为可读大小
     */
    formatBytes(bytes) {
        if (!bytes || bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    },

    /**
     * 格式化毫秒为可读时间
     */
    formatDuration(ms) {
        if (!ms) return '0ms';
        if (ms < 1000) return ms + 'ms';
        if (ms < 60000) return (ms / 1000).toFixed(1) + 's';
        if (ms < 3600000) return (ms / 60000).toFixed(1) + 'min';
        return (ms / 3600000).toFixed(1) + 'h';
    },

    /**
     * 获取状态徽章 HTML
     */
    statusBadge(status) {
        const map = {
            ok: '<span class="badge bg-success">正常</span>',
            warning: '<span class="badge bg-warning text-dark">警告</span>',
            error: '<span class="badge bg-danger">异常</span>',
        };
        return map[status] || `<span class="badge bg-secondary">${status}</span>`;
    },

    /**
     * 获取红绿灯图标
     */
    statusLight(status) {
        const map = {
            green: '<i class="bi bi-circle-fill text-success"></i>',
            yellow: '<i class="bi bi-circle-fill text-warning"></i>',
            red: '<i class="bi bi-circle-fill text-danger"></i>',
        };
        return map[status] || '';
    },

    /**
     * Toast 通知
     */
    showToast(message, type = 'info') {
        // 简单的 alert 实现, 后续可换成 Bootstrap Toast
        const bgColors = {
            success: 'bg-success',
            error: 'bg-danger',
            warning: 'bg-warning',
            info: 'bg-info',
        };
        const toast = document.createElement('div');
        toast.className = `toast align-items-center text-white ${bgColors[type]} border-0 position-fixed bottom-0 end-0 m-3`;
        toast.style.zIndex = '9999';
        toast.innerHTML = `
            <div class="d-flex">
                <div class="toast-body">${message}</div>
                <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
            </div>
        `;
        document.body.appendChild(toast);
        const bsToast = new bootstrap.Toast(toast, { delay: 3000 });
        bsToast.show();
        toast.addEventListener('hidden.bs.toast', () => toast.remove());
    },
};

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', () => {
    // 为所有 [data-tooltip] 元素添加 Bootstrap tooltip
    const tooltipTriggerList = [].slice.call(
        document.querySelectorAll('[data-bs-toggle="tooltip"]')
    );
    tooltipTriggerList.map(el => new bootstrap.Tooltip(el));
});
